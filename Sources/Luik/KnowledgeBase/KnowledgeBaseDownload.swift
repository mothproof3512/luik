import AppKit
import Foundation
import Observation
import Security

/// One downloadable knowledge base in a catalogue (catalog.json): a file next to the catalogue,
/// or any absolute URL.
struct KBCatalogEntry: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var language: String?
    var version: String?
    var file: String
    var records: Int?
    var description: String?

    func fileURL(relativeTo catalogURL: URL?) -> URL? {
        if let absolute = URL(string: file), absolute.scheme != nil {
            return absolute
        }
        guard let catalogURL else { return nil }
        return URL(string: file, relativeTo: catalogURL.deletingLastPathComponent())?.absoluteURL
    }

    /// "Attack vectors knowledge base (English) · 1.0 · 349 rows"
    var detail: String {
        var parts: [String] = []
        if let language, !language.isEmpty { parts.append(language) }
        if let version, !version.isEmpty { parts.append("version \(version)") }
        if let records, records > 0 { parts.append("\(records) rows") }
        return parts.joined(separator: " · ")
    }
}

/// A catalogue: a name and a list of entries. Luik ships one in the repository
/// (knowledge-base/catalog.json); teams can host their own and point Settings › Tools at it.
struct KBCatalog: Codable {
    var name: String?
    var entries: [KBCatalogEntry]
}

/// Downloads knowledge bases from the Luik repository, another catalogue or a direct file link,
/// and hands them to the knowledge-base store. Everything runs on the main actor; the fetches are
/// async URLSession calls.
@Observable
final class KnowledgeBaseDownloader {
    static let shared = KnowledgeBaseDownloader()

    /// The catalogue in the Luik repository.
    static let defaultCatalogURL = "https://raw.githubusercontent.com/\(AppInfo.repository)/main/knowledge-base/catalog.json"

    var catalog: KBCatalog?
    var catalogURL: URL?
    var catalogError: String?
    var isLoadingCatalog = false
    var isDownloading = false
    /// Last result, shown in the sheet.
    var status: String?
    var statusIsError = false
    /// Field contents of the sheet (remembered between sessions).
    var customURL: String = ""
    var token: String = ""
    /// Set when a download finished and was imported, so the sheet can close.
    var importedAt: Date?

    private var fieldsLoaded = false

    /// Settings › Tools, or the Luik catalogue when empty.
    static var configuredCatalogURL: String {
        let value = (UserDefaults.standard.string(forKey: SettingsKey.knowledgeBaseCatalogURL) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? defaultCatalogURL : value
    }

    var isUsingDefaultCatalog: Bool {
        catalogURL?.absoluteString == KnowledgeBaseDownloader.normalize(KnowledgeBaseDownloader.configuredCatalogURL)?.absoluteString
    }

    /// Called when the sheet opens: remembered URL and token, and the configured catalogue.
    func prepare() {
        if !fieldsLoaded {
            fieldsLoaded = true
            customURL = UserDefaults.standard.string(forKey: SettingsKey.knowledgeBaseCustomURL) ?? ""
            token = KeychainItem.githubToken.read() ?? ""
        }
        importedAt = nil
        if catalog == nil || !isUsingDefaultCatalog {
            loadCatalog()
        }
    }

    // MARK: - Catalogue

    /// Loads the configured catalogue (or the given one).
    func loadCatalog(from text: String? = nil) {
        let source = text ?? KnowledgeBaseDownloader.configuredCatalogURL
        guard let url = KnowledgeBaseDownloader.normalize(source) else {
            catalogError = "“\(source)” is not a valid URL."
            return
        }
        isLoadingCatalog = true
        catalogError = nil
        Task { @MainActor in
            do {
                let data = try await self.fetch(url)
                let decoded = try KnowledgeBaseDownloader.decodeCatalog(data)
                self.catalog = decoded
                self.catalogURL = url
            } catch {
                self.catalog = nil
                self.catalogURL = url
                self.catalogError = error.localizedDescription
            }
            self.isLoadingCatalog = false
        }
    }

    static func decodeCatalog(_ data: Data) throws -> KBCatalog {
        let decoder = JSONDecoder()
        if let catalog = try? decoder.decode(KBCatalog.self, from: data) {
            return catalog
        }
        // A bare array of entries is fine too.
        if let entries = try? decoder.decode([KBCatalogEntry].self, from: data) {
            return KBCatalog(name: nil, entries: entries)
        }
        throw DownloadError.notACatalog
    }

    // MARK: - Downloads

    func download(_ entry: KBCatalogEntry) {
        guard let url = entry.fileURL(relativeTo: catalogURL) else {
            fail("The catalogue entry “\(entry.name)” has no usable file link.")
            return
        }
        download(url: url, name: entry.name, catalogID: entry.id, version: entry.version)
    }

    /// The URL typed in the sheet: a direct file link, a GitHub “blob” link (converted to a raw
    /// download), or another catalogue (then its entries are listed instead).
    func importCustomURL() {
        let text = customURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = KnowledgeBaseDownloader.normalize(text) else {
            fail("“\(text)” is not a valid URL.")
            return
        }
        UserDefaults.standard.set(text, forKey: SettingsKey.knowledgeBaseCustomURL)
        KeychainItem.githubToken.write(token.trimmingCharacters(in: .whitespacesAndNewlines))
        isDownloading = true
        statusIsError = false
        status = "Downloading \(url.lastPathComponent)…"
        Task { @MainActor in
            do {
                let data = try await self.fetch(url)
                if let catalog = try? KnowledgeBaseDownloader.decodeCatalog(data), !catalog.entries.isEmpty {
                    self.catalog = catalog
                    self.catalogURL = url
                    self.catalogError = nil
                    self.status = "Catalogue loaded: \(catalog.entries.count) knowledge base(s) — choose one above."
                } else {
                    try self.importData(data, from: url, name: url.lastPathComponent, catalogID: nil, version: nil)
                }
            } catch {
                self.fail("Download failed: \(error.localizedDescription)")
            }
            self.isDownloading = false
        }
    }

    private func download(url: URL, name: String, catalogID: String?, version: String?) {
        isDownloading = true
        statusIsError = false
        status = "Downloading \(name)…"
        Task { @MainActor in
            do {
                let data = try await self.fetch(url)
                try self.importData(data, from: url, name: name, catalogID: catalogID, version: version)
            } catch {
                self.fail("Download failed: \(error.localizedDescription)")
            }
            self.isDownloading = false
        }
    }

    /// Writes the download to a temporary file (the importer goes by the extension) and imports it.
    private func importData(_ data: Data, from url: URL, name: String, catalogID: String?, version: String?) throws {
        var fileName = url.lastPathComponent
        let knownExtensions = ["xlsx", "xlsm", "csv", "tsv", "txt", "json"]
        if fileName.isEmpty || fileName == "/" || !knownExtensions.contains((fileName as NSString).pathExtension.lowercased()) {
            let base = fileName.isEmpty || fileName == "/" ? "knowledge-base" : (fileName as NSString).deletingPathExtension
            fileName = base + "." + KnowledgeBaseDownloader.sniffExtension(data)
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Luik Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let fileURL = folder.appendingPathComponent(fileName)
        try data.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let store = KnowledgeBaseStore.shared
        store.importFile(at: fileURL, sourceName: name, sourceURL: url.absoluteString, catalogID: catalogID, version: version)
        if let error = store.lastError {
            fail("Import failed: \(error)")
        } else {
            let rows = store.knowledgeBase?.recordCount ?? 0
            statusIsError = false
            status = "Imported \(name) (\(rows) rows)."
            importedAt = Date()
        }
    }

    private func fail(_ message: String) {
        status = message
        statusIsError = true
    }

    /// xlsx is a zip ("PK"), JSON starts with { or [, anything else is treated as CSV.
    static func sniffExtension(_ data: Data) -> String {
        if data.count >= 2, data[data.startIndex] == 0x50, data[data.startIndex + 1] == 0x4B { return "xlsx" }
        let head = String(decoding: data.prefix(64), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if head.hasPrefix("{") || head.hasPrefix("[") { return "json" }
        return "csv"
    }

    // MARK: - Networking

    func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        request.setValue("Luik/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        let secret = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if !secret.isEmpty {
            let host = url.host?.lowercased() ?? ""
            let isGitHub = host == "github.com" || host.hasSuffix(".github.com") || host.hasSuffix("githubusercontent.com")
            request.setValue(isGitHub ? "token \(secret)" : "Bearer \(secret)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw DownloadError.http(http.statusCode)
        }
        return data
    }

    /// Trims, adds https:// when the scheme is missing and turns GitHub page links into raw
    /// downloads: github.com/<owner>/<repo>/blob/<branch>/<path> → raw.githubusercontent.com/….
    static func normalize(_ text: String) -> URL? {
        var string = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !string.isEmpty else { return nil }
        if !string.contains("://") {
            string = "https://" + string
        }
        guard var components = URLComponents(string: string), let host = components.host?.lowercased() else { return nil }
        if host == "github.com" || host == "www.github.com" {
            let parts = components.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            // /owner/repo/blob/branch/path/to/file  or  /owner/repo/raw/branch/path/to/file
            if parts.count >= 5, parts[2] == "blob" || parts[2] == "raw" {
                components.host = "raw.githubusercontent.com"
                components.path = "/" + ([parts[0], parts[1], parts[3]] + parts[4...]).joined(separator: "/")
                components.query = nil
            }
        }
        return components.url
    }

    enum DownloadError: LocalizedError {
        case http(Int)
        case notACatalog

        var errorDescription: String? {
            switch self {
            case .http(let code):
                switch code {
                case 401, 403: return "HTTP \(code) — not allowed. For a private repository, add an access token with read access to its contents."
                case 404: return "HTTP 404 — nothing at that address. Check the link (for GitHub, the branch and path)."
                default: return "HTTP \(code) from the server."
                }
            case .notACatalog:
                return "The file is not a catalogue (expected JSON with an \"entries\" list)."
            }
        }
    }
}

/// Small secrets in the login keychain (service "dev.luik.app"): the access token for private
/// repositories, shared by the knowledge-base and library downloads.
enum KeychainItem: String {
    case githubToken = "github-token"

    private static let service = "dev.luik.app"

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: KeychainItem.service,
         kSecAttrAccount as String: rawValue]
    }

    func read() -> String? {
        var query = self.query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Replaces the stored value; an empty value removes it.
    func write(_ value: String) {
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty, let data = value.data(using: .utf8) else { return }
        var attributes = query
        attributes[kSecValueData as String] = data
        SecItemAdd(attributes as CFDictionary, nil)
    }
}
