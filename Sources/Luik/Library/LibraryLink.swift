import AppKit
import Foundation
import SwiftUI

/// The glue between one-liners, checklist items and the library: a link is a library page
/// (its path "Collection/Folder/Page.md", or a topic name such as "SMB"), or a URL. Resolution is
/// cached per text until the library is rescanned.
enum LibraryLink {
    private static var cache: [String: String?] = [:]   // text → document id
    private static var cacheGeneration = 0

    static func invalidate() {
        cache = [:]
        cacheGeneration += 1
    }

    static func isURL(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.hasPrefix("http://") || lower.hasPrefix("https://")
    }

    /// The library document a link text points at (nil for URLs and unknown topics).
    static func resolve(_ text: String) -> LibraryDocument? {
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !isURL(key) else { return nil }
        let library = LibraryStore.shared
        if let cached = cache[key] { return cached.flatMap { library.document(id: $0) } }
        let found = library.document(id: key) ?? library.document(topic: key)
        cache[key] = .some(found?.id)
        return found
    }

    /// First topic among several that has a page (services first, then the title).
    static func resolve(any topics: [String]) -> LibraryDocument? {
        for topic in topics {
            let cleaned = topic.trimmingCharacters(in: .whitespaces)
            guard cleaned.count >= 3 else { continue }
            if let document = resolve(cleaned) { return document }
        }
        return nil
    }

    /// Opens the link: a URL in the browser, a page in the Notes tab.
    static func open(_ text: String) {
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if isURL(key), let url = URL(string: key) {
            NSWorkspace.shared.open(url)
            return
        }
        if let document = resolve(key) {
            NotesStore.shared.open(document)
            UIState.shared.open(.notes)
        }
    }

    static func open(_ document: LibraryDocument) {
        NotesStore.shared.open(document)
        UIState.shared.open(.notes)
    }

    // MARK: - Topics of the things that can link

    /// Service names a one-liner is tagged with, as topics ("http" → also "web", "smb" → "SMB").
    static func topics(for snippet: Snippet) -> [String] {
        var topics: [String] = []
        if !snippet.link.isEmpty { topics.append(snippet.link) }
        for service in snippet.services where service != "host" && service != "port" && Int(service) == nil {
            topics.append(service)
            topics.append(contentsOf: aliases[service.lowercased()] ?? [])
        }
        return topics
    }

    static func document(for snippet: Snippet) -> LibraryDocument? {
        resolve(any: topics(for: snippet))
    }

    /// For a checklist item under a service: the item's own link, else the service.
    static func document(for item: ChecklistItem?, service: String?) -> LibraryDocument? {
        if let item, !item.link.isEmpty, let document = resolve(item.link) { return document }
        guard let service, !service.isEmpty else { return nil }
        return resolve(any: [service] + (aliases[service.lowercased()] ?? []))
    }

    /// Common nmap service names → the words library pages use.
    static let aliases: [String: [String]] = [
        "http": ["web", "http", "Methodology and Resources"], "https": ["web", "http"], "ssl/http": ["web"], "http-proxy": ["web", "proxy"],
        "microsoft-ds": ["SMB"], "netbios-ssn": ["SMB", "NetBIOS"], "smb": ["SMB"],
        "ms-wbt-server": ["RDP"], "rdp": ["RDP"],
        "domain": ["DNS"], "dns": ["DNS"],
        "ldap": ["LDAP", "Active Directory"], "ldaps": ["LDAP"], "kerberos-sec": ["Kerberos"], "kerberos": ["Kerberos"],
        "ms-sql-s": ["MSSQL", "SQL Server"], "mssql": ["MSSQL"], "mysql": ["MySQL"], "postgresql": ["PostgreSQL", "Postgres"],
        "smtp": ["SMTP", "Mail"], "submission": ["SMTP"], "imap": ["IMAP"], "pop3": ["POP3"],
        "snmp": ["SNMP"], "telnet": ["Telnet"], "vnc": ["VNC"], "nfs": ["NFS"], "rpcbind": ["RPC"], "msrpc": ["RPC"],
        "winrm": ["WinRM"], "wsman": ["WinRM"], "redis": ["Redis"], "mongodb": ["MongoDB"], "elasticsearch": ["Elasticsearch"],
        "docker": ["Docker"], "ssh": ["SSH"], "ftp": ["FTP"],
    ]

    /// One-liners that point at (or whose topics resolve to) a document.
    static func snippets(for document: LibraryDocument) -> [Snippet] {
        SnippetStore.shared.snippets.filter { snippet in
            if !snippet.link.isEmpty { return resolve(snippet.link)?.id == document.id }
            return self.document(for: snippet)?.id == document.id
        }
    }
}

/// "Read more" button: book icon with the page title, opens the page in the Notes tab.
struct LibraryLinkButton: View {
    let document: LibraryDocument
    var compact = false

    var body: some View {
        Group {
            if compact {
                Button {
                    LibraryLink.open(document)
                } label: {
                    Image(systemName: "book")
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    LibraryLink.open(document)
                } label: {
                    Label("Read more: \(document.title)", systemImage: "book")
                        .font(.caption)
                        .lineLimit(1)
                }
                .buttonStyle(.link)
            }
        }
        .help("Open “\(document.title)” (\(document.breadcrumb)) in the library")
    }
}

/// Field to pick a library page (or type a URL) for a one-liner or checklist item.
struct LibraryLinkField: View {
    @Binding var link: String
    @State private var query = ""
    @State private var showResults = false

    var body: some View {
        HStack(spacing: 6) {
            TextField("Library page or URL (optional)", text: $link)
                .textFieldStyle(.roundedBorder)
                .onChange(of: link) { _, value in
                    query = value
                    showResults = !value.isEmpty && !LibraryLink.isURL(value) && LibraryLink.resolve(value) == nil
                }
            if let document = LibraryLink.resolve(link) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .help("Resolves to “\(document.title)” (\(document.breadcrumb))")
            } else if LibraryLink.isURL(link) {
                Image(systemName: "link")
                    .foregroundStyle(.secondary)
            } else if !link.isEmpty {
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(.orange)
                    .help("No library page matches this yet")
            }
            Menu {
                let results = query.count >= 2 ? LibraryStore.shared.search(query, limit: 12) : []
                if results.isEmpty {
                    Text(query.count >= 2 ? "No pages match" : "Type a few letters first")
                } else {
                    ForEach(results) { document in
                        Button("\(document.title) — \(document.breadcrumb)") { link = document.id }
                    }
                }
            } label: {
                Image(systemName: "book")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Pick a library page that matches the text")
        }
    }
}
