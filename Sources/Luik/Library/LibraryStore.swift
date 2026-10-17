import AppKit
import Foundation
import Observation

/// One Markdown (or text) file in the library.
struct LibraryDocument: Identifiable, Hashable, Sendable {
    /// Path relative to the library folder, e.g. "PayloadsAllTheThings/SQL Injection/README.md".
    let id: String
    let url: URL
    let title: String
    /// Top-level folder (the collection): "Cheatsheets", "PayloadsAllTheThings", …
    let collection: String
    /// Folder inside the collection ("" at the top).
    let folder: String

    var fileName: String { url.lastPathComponent }
    var breadcrumb: String { folder.isEmpty ? collection : "\(collection) › \(folder.replacingOccurrences(of: "/", with: " › "))" }
}

/// A row in the library outline: a document or a folder with children.
struct LibraryNode: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let document: LibraryDocument?
    var children: [LibraryNode]?

    var documentCount: Int {
        document != nil ? 1 : (children ?? []).reduce(0) { $0 + $1.documentCount }
    }
}

/// Where a downloaded collection came from (Library/<name>/.luik-source.json).
struct LibrarySourceInfo: Codable, Hashable, Sendable {
    var sourceID: String
    var repository: String
    var branch: String
    var commit: String
    var commitDate: Date?
    var downloadedAt: Date
    var documentCount: Int

    var shortCommit: String { String(commit.prefix(7)) }
}

/// A top-level folder of the library.
struct LibraryCollection: Identifiable, Hashable, Sendable {
    let id: String      // folder name
    let url: URL
    var documents: [LibraryDocument]
    var tree: [LibraryNode]
    var source: LibrarySourceInfo?

    var name: String { id }
}

/// The library: Markdown documents on disk in ~/Library/Application Support/Luik/Library/
/// (one subfolder per collection), shared by all engagements. Cheat sheets are copied in with
/// "Import folder…"; documentation such as PayloadsAllTheThings is downloaded from GitHub
/// (LibraryDownloader). Documents are read when selected and written back when edited.
@Observable
final class LibraryStore {
    static let shared = LibraryStore()

    static let sourceFileName = ".luik-source.json"
    static let documentExtensions: Set<String> = ["md", "markdown", "txt"]

    var collections: [LibraryCollection] = []
    var isScanning = false
    var lastError: String?

    @ObservationIgnored private var contents: [String: String] = [:]
    @ObservationIgnored private var searchIndex: [String: String] = [:]   // id → lowercased text
    @ObservationIgnored private var savers: [String: Debouncer] = [:]
    @ObservationIgnored private var scanned = false

    static var directory: URL {
        let dir = Storage.url(for: "Library")
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    var documentCount: Int {
        collections.reduce(0) { $0 + $1.documents.count }
    }

    var isEmpty: Bool { collections.isEmpty }

    // MARK: - Scanning

    /// Reads the folder structure (titles come from the first "# heading" of each file). Runs in
    /// the background; the first call happens when the Notes tab is shown.
    func scanIfNeeded() {
        guard !scanned else { return }
        rescan()
    }

    func rescan() {
        scanned = true
        isScanning = true
        let root = LibraryStore.directory
        DispatchQueue.global(qos: .userInitiated).async {
            let result = LibraryStore.scan(root: root)
            DispatchQueue.main.async {
                self.collections = result
                self.searchIndex = [:]
                self.contents = [:]
                self.isScanning = false
            }
        }
    }

    /// Scans the library folder on the calling thread.
    static func scan(root: URL) -> [LibraryCollection] {
        let fm = FileManager.default
        guard let topLevel = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return []
        }
        var collections: [LibraryCollection] = []
        for folder in topLevel.sorted(by: { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }) {
            guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            let name = folder.lastPathComponent
            // Left over from an interrupted download — not a collection.
            if name.hasSuffix(".downloading") || name.hasSuffix(".previous") { continue }
            var documents: [LibraryDocument] = []
            if let enumerator = fm.enumerator(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
                for case let file as URL in enumerator {
                    guard documentExtensions.contains(file.pathExtension.lowercased()),
                          (try? file.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory != true else { continue }
                    let relative = relativePath(of: file, in: root)
                    let inside = relativePath(of: file.deletingLastPathComponent(), in: folder)
                    documents.append(LibraryDocument(id: relative, url: file, title: title(of: file), collection: name, folder: inside))
                }
            }
            guard !documents.isEmpty else { continue }
            documents.sort { $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending }
            let source = try? JSONDecoder.iso.decode(LibrarySourceInfo.self, from: Data(contentsOf: folder.appendingPathComponent(sourceFileName)))
            collections.append(LibraryCollection(id: name, url: folder, documents: documents, tree: buildTree(documents, collection: name), source: source))
        }
        return collections
    }

    private static func relativePath(of url: URL, in base: URL) -> String {
        let basePath = base.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(basePath) else { return url.lastPathComponent }
        var relative = String(path.dropFirst(basePath.count))
        while relative.hasPrefix("/") { relative.removeFirst() }
        return relative
    }

    /// The first "# Heading" in the file, else the folder name for a README, else the file name.
    static func title(of file: URL) -> String {
        if let handle = try? FileHandle(forReadingFrom: file) {
            let head = handle.readData(ofLength: 4096)
            try? handle.close()
            let text = String(decoding: head, as: UTF8.self)
            for line in text.split(separator: "\n", omittingEmptySubsequences: true).prefix(40) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("# ") {
                    let title = trimmed.dropFirst(2).trimmingCharacters(in: CharacterSet(charactersIn: "# \t"))
                    if !title.isEmpty { return title }
                }
            }
        }
        let name = file.deletingPathExtension().lastPathComponent
        if name.lowercased() == "readme" || name.lowercased() == "index" {
            return file.deletingLastPathComponent().lastPathComponent
        }
        return name
    }

    /// Folders become nodes with children; a folder that holds only a README collapses into one row.
    static func buildTree(_ documents: [LibraryDocument], collection: String) -> [LibraryNode] {
        final class FolderBuilder {
            let name: String
            var folders: [String: FolderBuilder] = [:]
            var documents: [LibraryDocument] = []
            init(name: String) { self.name = name }

            func node(path: String) -> [LibraryNode] {
                var rows: [LibraryNode] = []
                for key in folders.keys.sorted(by: { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }) {
                    let folder = folders[key]!
                    let folderPath = path.isEmpty ? key : path + "/" + key
                    let children = folder.node(path: folderPath)
                    if children.count == 1, let only = children.first, only.document != nil, only.document?.fileName.lowercased().hasPrefix("readme") == true {
                        rows.append(only)
                    } else {
                        rows.append(LibraryNode(id: "folder:" + folderPath, title: key, document: nil, children: children))
                    }
                }
                let sorted = documents.sorted { a, b in
                    let aReadme = a.fileName.lowercased().hasPrefix("readme")
                    let bReadme = b.fileName.lowercased().hasPrefix("readme")
                    if aReadme != bReadme { return aReadme }
                    return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
                }
                for document in sorted {
                    rows.append(LibraryNode(id: document.id, title: document.title, document: document, children: nil))
                }
                return rows
            }
        }
        let root = FolderBuilder(name: collection)
        for document in documents {
            var current = root
            for part in document.folder.split(separator: "/").map(String.init) {
                if let existing = current.folders[part] {
                    current = existing
                } else {
                    let created = FolderBuilder(name: part)
                    current.folders[part] = created
                    current = created
                }
            }
            current.documents.append(document)
        }
        return root.node(path: collection)
    }

    // MARK: - Lookup

    func document(id: String?) -> LibraryDocument? {
        guard let id else { return nil }
        for collection in collections {
            if let document = collection.documents.first(where: { $0.id == id }) { return document }
        }
        return nil
    }

    func collection(named name: String) -> LibraryCollection? {
        collections.first { $0.id == name }
    }

    /// Resolves a relative link inside a document (./MySQL%20Injection.md, ../Other/README.md).
    func document(linked path: String, from document: LibraryDocument) -> LibraryDocument? {
        var target = path.removingPercentEncoding ?? path
        if let hash = target.firstIndex(of: "#") { target = String(target[..<hash]) }
        target = target.trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty else { return nil }
        let base = document.url.deletingLastPathComponent()
        var resolved = URL(fileURLWithPath: target, relativeTo: base).standardizedFileURL
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        if fm.fileExists(atPath: resolved.path, isDirectory: &isDirectory), isDirectory.boolValue {
            resolved = resolved.appendingPathComponent("README.md")
        }
        let relative = LibraryStore.relativePath(of: resolved, in: LibraryStore.directory)
        return self.document(id: relative)
    }

    /// A document for a topic name as other tabs mention it ("Insecure Direct Object References"):
    /// the folder or title that matches best, exact matches first.
    func document(topic: String, in collectionName: String? = nil) -> LibraryDocument? {
        let needle = topic.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return nil }
        let pool = collections.filter { collectionName == nil || $0.id.lowercased() == collectionName?.lowercased() }
        let documents = pool.flatMap { $0.documents }
        func lastFolder(_ doc: LibraryDocument) -> String {
            doc.folder.split(separator: "/").last.map(String.init)?.lowercased() ?? ""
        }
        if let exact = documents.first(where: { $0.title.lowercased() == needle || lastFolder($0) == needle }) { return exact }
        let readmes = documents.filter { $0.fileName.lowercased().hasPrefix("readme") }
        if let folder = readmes.first(where: { lastFolder($0).contains(needle) || needle.contains(lastFolder($0)) && !lastFolder($0).isEmpty }) { return folder }
        return documents.first { $0.title.lowercased().contains(needle) }
    }

    // MARK: - Contents

    func text(of document: LibraryDocument) -> String {
        if let cached = contents[document.id] { return cached }
        let text = (try? String(contentsOf: document.url, encoding: .utf8))
            ?? (try? String(contentsOf: document.url, encoding: .isoLatin1))
            ?? ""
        contents[document.id] = text
        return text
    }

    /// Saves an edit (debounced); the title in the outline follows the first heading.
    func update(_ document: LibraryDocument, text: String) {
        contents[document.id] = text
        searchIndex[document.id] = nil
        let saver = savers[document.id] ?? Debouncer()
        savers[document.id] = saver
        saver.call { [weak self] in
            do {
                try text.write(to: document.url, atomically: true, encoding: .utf8)
                self?.refreshTitle(of: document)
            } catch {
                self?.lastError = "Could not save \(document.fileName): \(error.localizedDescription)"
            }
        }
    }

    func flush() {
        for saver in savers.values { saver.flush() }
    }

    private func refreshTitle(of document: LibraryDocument) {
        let title = LibraryStore.title(of: document.url)
        guard title != document.title,
              let collectionIndex = collections.firstIndex(where: { $0.id == document.collection }),
              let documentIndex = collections[collectionIndex].documents.firstIndex(where: { $0.id == document.id }) else { return }
        let updated = LibraryDocument(id: document.id, url: document.url, title: title, collection: document.collection, folder: document.folder)
        collections[collectionIndex].documents[documentIndex] = updated
        collections[collectionIndex].tree = LibraryStore.buildTree(collections[collectionIndex].documents, collection: document.collection)
    }

    // MARK: - Search

    /// Documents whose title, path or text contains every word of the query (titles rank first).
    func search(_ query: String, limit: Int = 50) -> [LibraryDocument] {
        let words = query.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !words.isEmpty else { return [] }
        var titleHits: [LibraryDocument] = []
        var textHits: [LibraryDocument] = []
        for collection in collections {
            for document in collection.documents {
                let label = (document.title + " " + document.id).lowercased()
                if words.allSatisfy({ label.contains($0) }) {
                    titleHits.append(document)
                } else if words.allSatisfy({ indexedText(of: document).contains($0) }) {
                    textHits.append(document)
                }
                if titleHits.count >= limit { return titleHits }
            }
        }
        return Array((titleHits + textHits).prefix(limit))
    }

    private func indexedText(of document: LibraryDocument) -> String {
        if let cached = searchIndex[document.id] { return cached }
        let text = self.text(of: document).lowercased()
        searchIndex[document.id] = text
        return text
    }

    // MARK: - Importing files

    /// Copies Markdown/text files into the library. Folders become a collection named after the
    /// folder (subfolders kept); loose files go into "Cheatsheets". Existing files with the same
    /// name are replaced. Returns a one-line summary.
    @discardableResult
    func importItems(_ urls: [URL]) -> String {
        let fm = FileManager.default
        var copied = 0
        var skipped = 0
        var collectionsTouched: Set<String> = []

        func copy(_ file: URL, to destination: URL) {
            do {
                try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
                try fm.copyItem(at: file, to: destination)
                copied += 1
            } catch {
                skipped += 1
                lastError = "Could not copy \(file.lastPathComponent): \(error.localizedDescription)"
            }
        }

        for url in urls {
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                let collection = url.lastPathComponent
                let target = LibraryStore.directory.appendingPathComponent(collection, isDirectory: true)
                collectionsTouched.insert(collection)
                guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
                for case let file as URL in enumerator {
                    let name = file.lastPathComponent
                    if name == "node_modules" || name == ".git" {
                        enumerator.skipDescendants()
                        continue
                    }
                    guard LibraryStore.documentExtensions.contains(file.pathExtension.lowercased()),
                          (try? file.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory != true else { continue }
                    let relative = LibraryStore.relativePath(of: file, in: url)
                    copy(file, to: target.appendingPathComponent(relative))
                }
            } else if LibraryStore.documentExtensions.contains(url.pathExtension.lowercased()) {
                collectionsTouched.insert("Cheatsheets")
                copy(url, to: LibraryStore.directory.appendingPathComponent("Cheatsheets", isDirectory: true).appendingPathComponent(url.lastPathComponent))
            } else {
                skipped += 1
            }
        }
        rescan()
        let where_ = collectionsTouched.sorted().joined(separator: ", ")
        let summary = "Imported \(copied) file(s) into \(where_.isEmpty ? "the library" : where_)\(skipped > 0 ? ", \(skipped) skipped" : "")."
        ActivityLog.shared.record(.import, summary, source: "Library")
        return summary
    }

    /// Collections you can write a note into: your own folders (not the downloaded ones).
    var writableCollectionNames: [String] {
        var names = collections.filter { $0.source == nil }.map { $0.id }
        if !names.contains(LibraryStore.personalCollection) { names.insert(LibraryStore.personalCollection, at: 0) }
        return names
    }

    static let personalCollection = "Personal"

    /// Writes a note as a Markdown file into a collection (default "Personal"); the first heading
    /// becomes the title. Returns the new document's id, after a rescan.
    @discardableResult
    func saveNote(title: String, text: String, collection: String = LibraryStore.personalCollection) -> String? {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        var body = text
        let firstLine = body.split(separator: "\n", omittingEmptySubsequences: true).first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        if !cleanTitle.isEmpty, !firstLine.hasPrefix("# ") {
            body = "# \(cleanTitle)\n\n" + body
        }
        var slug = (cleanTitle.isEmpty ? "note" : cleanTitle)
            .lowercased()
            .map { $0.isLetter || $0.isNumber ? String($0) : "-" }
            .joined()
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        while slug.contains("--") { slug = slug.replacingOccurrences(of: "--", with: "-") }
        if slug.isEmpty { slug = "note" }
        let folder = LibraryStore.directory.appendingPathComponent(collection, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var url = folder.appendingPathComponent(slug + ".md")
            var counter = 2
            while FileManager.default.fileExists(atPath: url.path) {
                url = folder.appendingPathComponent("\(slug)-\(counter).md")
                counter += 1
            }
            try body.write(to: url, atomically: true, encoding: .utf8)
            ActivityLog.shared.record(.action, "Note “\(cleanTitle.isEmpty ? slug : cleanTitle)” saved to the library (\(collection))", source: "Notes")
            rescan()
            return collection + "/" + url.lastPathComponent
        } catch {
            lastError = "Could not save to the library: \(error.localizedDescription)"
            return nil
        }
    }

    /// Open panel for "Import folder…": folders and/or .md files.
    func importWithPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.message = "Choose a folder of Markdown cheat sheets (subfolders are kept), or individual .md files"
        panel.prompt = "Import"
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        importItems(panel.urls)
    }

    /// Deletes a collection folder (the user's own copy only).
    func removeCollection(_ name: String) {
        let url = LibraryStore.directory.appendingPathComponent(name, isDirectory: true)
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        } catch {
            try? FileManager.default.removeItem(at: url)
        }
        ActivityLog.shared.record(.action, "Library collection removed: \(name)", source: "Library")
        rescan()
    }

    func revealInFinder(_ collection: LibraryCollection? = nil) {
        NSWorkspace.shared.activateFileViewerSelecting([collection?.url ?? LibraryStore.directory])
    }
}

extension JSONDecoder {
    /// ISO-8601 dates, as Storage writes them.
    static var iso: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

extension JSONEncoder {
    static var iso: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
