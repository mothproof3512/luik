import AppKit
import Foundation
import Observation

/// A GitHub repository of Markdown documentation that can be downloaded into the library.
struct LibrarySource: Identifiable, Codable, Hashable {
    var id: String
    /// Collection (folder) name in the library.
    var name: String
    /// "owner/repo"
    var repository: String
    /// nil = the repository's default branch.
    var branch: String?
    var summary: String
    var builtIn: Bool = false

    var pageURL: String { "https://github.com/\(repository)" }

    static let builtIn: [LibrarySource] = [
        LibrarySource(id: "payloadsallthethings", name: "PayloadsAllTheThings", repository: "swisskyrepo/PayloadsAllTheThings",
                      summary: "Payloads and bypasses for web application security: injection, authentication, file upload, SSRF, XSS, deserialisation, … one folder per technique, with a methodology section. MIT licence.", builtIn: true),
        LibrarySource(id: "internalallthethings", name: "InternalAllTheThings", repository: "swisskyrepo/InternalAllTheThings",
                      summary: "Active Directory and internal network cheat sheets by the same author: enumeration, Kerberos, ADCS, delegation, lateral movement, persistence, cloud. MIT licence.", builtIn: true),
    ]

    private enum CodingKeys: String, CodingKey { case id, name, repository, branch, summary, builtIn }

    init(id: String, name: String, repository: String, branch: String? = nil, summary: String, builtIn: Bool = false) {
        self.id = id
        self.name = name
        self.repository = repository
        self.branch = branch
        self.summary = summary
        self.builtIn = builtIn
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        repository = try c.decode(String.self, forKey: .repository)
        branch = try c.decodeIfPresent(String.self, forKey: .branch)
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        builtIn = try c.decodeIfPresent(Bool.self, forKey: .builtIn) ?? false
    }
}

/// Downloads a repository as a zip (codeload.github.com), keeps the Markdown files and places
/// them in Library/<name>/. The latest commit is remembered, so "Check for updates" can compare.
@Observable
final class LibraryDownloader {
    static let shared = LibraryDownloader()

    private static let customSourcesFile = "library-sources.json"

    /// User-added repositories (Library/../library-sources.json).
    var customSources: [LibrarySource] = []
    /// Source id → progress text while a download runs.
    var progress: [String: String] = [:]
    /// Source id → latest commit on GitHub, after "Check for updates".
    var latestCommit: [String: (sha: String, date: Date?)] = [:]
    var isChecking = false
    var status: String?
    var statusIsError = false
    var token: String = ""

    private var fieldsLoaded = false

    init() {
        customSources = Storage.load([LibrarySource].self, from: LibraryDownloader.customSourcesFile) ?? []
    }

    var sources: [LibrarySource] { LibrarySource.builtIn + customSources }

    func source(id: String) -> LibrarySource? {
        sources.first { $0.id == id }
    }

    func prepare() {
        if !fieldsLoaded {
            fieldsLoaded = true
            token = KeychainItem.githubToken.read() ?? ""
        }
    }

    func saveToken() {
        KeychainItem.githubToken.write(token.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - Custom sources

    /// Adds "owner/repo" (a GitHub URL is accepted too). Returns an error line, or nil.
    @discardableResult
    func addCustomSource(repository rawRepository: String, name rawName: String, branch rawBranch: String) -> String? {
        var repository = rawRepository.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = repository.range(of: "github.com/") {
            repository = String(repository[range.upperBound...])
        }
        repository = repository.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if repository.hasSuffix(".git") { repository.removeLast(4) }
        let parts = repository.split(separator: "/").map(String.init)
        guard parts.count >= 2, !parts[0].isEmpty, !parts[1].isEmpty else {
            return "Enter the repository as owner/name, e.g. yourname/cheatsheets."
        }
        repository = parts[0] + "/" + parts[1]
        var branch = rawBranch.trimmingCharacters(in: .whitespacesAndNewlines)
        if parts.count >= 4, parts[2] == "tree", branch.isEmpty { branch = parts[3] }
        var name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { name = parts[1] }
        name = name.replacingOccurrences(of: "/", with: "-")
        let id = "custom-" + repository.lowercased().replacingOccurrences(of: "/", with: "-")
        guard source(id: id) == nil else { return "\(repository) is already in the list." }
        guard !sources.contains(where: { $0.name.lowercased() == name.lowercased() }) else {
            return "A collection named “\(name)” exists already; choose another name."
        }
        customSources.append(LibrarySource(id: id, name: name, repository: repository, branch: branch.isEmpty ? nil : branch, summary: "Your repository"))
        Storage.save(customSources, to: LibraryDownloader.customSourcesFile)
        return nil
    }

    func removeCustomSource(_ source: LibrarySource) {
        customSources.removeAll { $0.id == source.id }
        Storage.save(customSources, to: LibraryDownloader.customSourcesFile)
    }

    // MARK: - State

    func isDownloaded(_ source: LibrarySource) -> LibrarySourceInfo? {
        LibraryStore.shared.collection(named: source.name)?.source
    }

    func hasUpdate(_ source: LibrarySource) -> Bool {
        guard let info = isDownloaded(source), let latest = latestCommit[source.id] else { return false }
        return latest.sha != info.commit
    }

    // MARK: - Updates

    /// Asks GitHub for the latest commit of every downloaded source.
    func checkForUpdates() {
        isChecking = true
        statusIsError = false
        status = "Checking GitHub…"
        let downloaded = sources.filter { isDownloaded($0) != nil }
        Task { @MainActor in
            var updates = 0
            var failures: [String] = []
            for source in downloaded {
                do {
                    let branch = try await self.resolveBranch(source)
                    let commit = try await self.fetchLatestCommit(repository: source.repository, branch: branch)
                    self.latestCommit[source.id] = commit
                    if self.hasUpdate(source) { updates += 1 }
                } catch {
                    failures.append("\(source.name): \(error.localizedDescription)")
                }
            }
            self.isChecking = false
            if !failures.isEmpty {
                self.statusIsError = true
                self.status = failures.joined(separator: " · ")
            } else if downloaded.isEmpty {
                self.status = "Nothing downloaded yet."
            } else {
                self.status = updates == 0 ? "Everything is up to date." : "\(updates) update(s) available."
            }
        }
    }

    // MARK: - Download

    func download(_ source: LibrarySource) {
        guard progress[source.id] == nil else { return }
        progress[source.id] = "Preparing…"
        statusIsError = false
        status = nil
        Task { @MainActor in
            do {
                let branch = try await self.resolveBranch(source)
                let commit = try await self.fetchLatestCommit(repository: source.repository, branch: branch)
                self.progress[source.id] = "Downloading \(source.repository) (\(branch))…"
                let zip = try await self.downloadArchive(repository: source.repository, branch: branch)
                defer { try? FileManager.default.removeItem(at: zip) }
                self.progress[source.id] = "Unpacking…"
                let count = try await Task.detached(priority: .userInitiated) {
                    try LibraryDownloader.install(zip: zip, source: source, branch: branch, commit: commit)
                }.value
                self.latestCommit[source.id] = commit
                self.progress[source.id] = nil
                self.status = "\(source.name): \(count) documents from \(source.repository) (\(String(commit.sha.prefix(7))))."
                ActivityLog.shared.record(.import, "Library: \(source.name) downloaded from \(source.repository) (\(count) documents, commit \(String(commit.sha.prefix(7))))", source: "Library")
                LibraryStore.shared.rescan()
            } catch {
                self.progress[source.id] = nil
                self.statusIsError = true
                self.status = "\(source.name): \(error.localizedDescription)"
            }
        }
    }

    func resolveBranch(_ source: LibrarySource) async throws -> String {
        if let branch = source.branch, !branch.isEmpty { return branch }
        let data = try await fetch(URL(string: "https://api.github.com/repos/\(source.repository)")!, accept: "application/vnd.github+json")
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let branch = json["default_branch"] as? String else {
            throw DownloadError.unexpectedAnswer
        }
        return branch
    }

    func fetchLatestCommit(repository: String, branch: String) async throws -> (sha: String, date: Date?) {
        let encodedBranch = branch.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? branch
        let data = try await fetch(URL(string: "https://api.github.com/repos/\(repository)/commits/\(encodedBranch)")!, accept: "application/vnd.github+json")
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sha = json["sha"] as? String else {
            throw DownloadError.unexpectedAnswer
        }
        var date: Date? = nil
        if let commit = json["commit"] as? [String: Any], let committer = commit["committer"] as? [String: Any],
           let text = committer["date"] as? String {
            date = ISO8601DateFormatter().date(from: text)
        }
        return (sha, date)
    }

    private func downloadArchive(repository: String, branch: String) async throws -> URL {
        let encodedBranch = branch.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? branch
        let url = URL(string: "https://codeload.github.com/\(repository)/zip/refs/heads/\(encodedBranch)")!
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 300)
        request.setValue("Luik/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        applyToken(to: &request, url: url)
        let (temporary, response) = try await URLSession.shared.download(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            try? FileManager.default.removeItem(at: temporary)
            throw DownloadError.http(http.statusCode)
        }
        // Keep our own copy: the system removes the temporary file when this call returns.
        let zip = FileManager.default.temporaryDirectory.appendingPathComponent("luik-\(UUID().uuidString).zip")
        try FileManager.default.moveItem(at: temporary, to: zip)
        return zip
    }

    /// Unpacks the Markdown files of the archive and swaps them into Library/<name>/.
    private static func install(zip: URL, source: LibrarySource, branch: String, commit: (sha: String, date: Date?)) throws -> Int {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("luik-unzip-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        try unzipMarkdown(zip, to: work)

        // The archive has one top-level folder: <repo>-<branch>.
        let top = try fm.contentsOfDirectory(at: work, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        let root = top.count == 1 && (try? top[0].resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true ? top[0] : work

        let staging = LibraryStore.directory.appendingPathComponent(source.name + ".downloading", isDirectory: true)
        try? fm.removeItem(at: staging)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        var count = 0
        if let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            for case let file as URL in enumerator {
                let name = file.lastPathComponent
                if name == ".github" || name == "node_modules" {
                    enumerator.skipDescendants()
                    continue
                }
                guard LibraryStore.documentExtensions.contains(file.pathExtension.lowercased()),
                      (try? file.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory != true else { continue }
                let relative = file.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let destination = staging.appendingPathComponent(relative)
                try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: file, to: destination)
                count += 1
            }
        }
        guard count > 0 else {
            try? fm.removeItem(at: staging)
            throw DownloadError.noDocuments
        }
        let info = LibrarySourceInfo(sourceID: source.id, repository: source.repository, branch: branch, commit: commit.sha,
                                     commitDate: commit.date, downloadedAt: Date(), documentCount: count)
        try JSONEncoder.iso.encode(info).write(to: staging.appendingPathComponent(LibraryStore.sourceFileName))

        let final = LibraryStore.directory.appendingPathComponent(source.name, isDirectory: true)
        let old = LibraryStore.directory.appendingPathComponent(source.name + ".previous", isDirectory: true)
        try? fm.removeItem(at: old)
        if fm.fileExists(atPath: final.path) {
            try fm.moveItem(at: final, to: old)
        }
        try fm.moveItem(at: staging, to: final)
        try? fm.removeItem(at: old)
        return count
    }

    /// unzip extracts only the Markdown files; ditto (fallback) extracts everything.
    private static func unzipMarkdown(_ zip: URL, to directory: URL) throws {
        let candidates: [(String, [String], Set<Int32>)] = [
            ("/usr/bin/unzip", ["-q", "-o", zip.path, "*.md", "*.markdown", "-d", directory.path], [0, 11]),
            ("/usr/bin/ditto", ["-x", "-k", zip.path, directory.path], [0]),
        ]
        var lastError = "no unzip tool found"
        for (tool, arguments, okCodes) in candidates where FileManager.default.isExecutableFile(atPath: tool) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = arguments
            let errorPipe = Pipe()
            process.standardError = errorPipe
            process.standardOutput = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                lastError = error.localizedDescription
                continue
            }
            if okCodes.contains(process.terminationStatus) {
                return
            }
            let output = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            lastError = output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "exit code \(process.terminationStatus)" : output
        }
        throw DownloadError.unzipFailed(lastError)
    }

    // MARK: - Networking

    private func applyToken(to request: inout URLRequest, url: URL) {
        let secret = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !secret.isEmpty else { return }
        let host = url.host?.lowercased() ?? ""
        let isGitHub = host == "github.com" || host.hasSuffix(".github.com") || host.hasSuffix("githubusercontent.com")
        request.setValue(isGitHub ? "token \(secret)" : "Bearer \(secret)", forHTTPHeaderField: "Authorization")
    }

    private func fetch(_ url: URL, accept: String? = nil) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("Luik/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        if let accept { request.setValue(accept, forHTTPHeaderField: "Accept") }
        applyToken(to: &request, url: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw DownloadError.http(http.statusCode)
        }
        return data
    }

    enum DownloadError: LocalizedError {
        case http(Int)
        case unexpectedAnswer
        case unzipFailed(String)
        case noDocuments

        var errorDescription: String? {
            switch self {
            case .http(let code):
                switch code {
                case 401, 403: return "HTTP \(code) — not allowed (private repository, or GitHub's rate limit for anonymous requests; add a token)."
                case 404: return "HTTP 404 — repository or branch not found."
                default: return "HTTP \(code) from GitHub."
                }
            case .unexpectedAnswer: return "Unexpected answer from GitHub."
            case .unzipFailed(let detail): return "The archive could not be unpacked: \(detail)"
            case .noDocuments: return "The repository contains no Markdown files."
            }
        }
    }
}
