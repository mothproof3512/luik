import Foundation
import SwiftUI

/// Turns a port node's service description ("http — Apache httpd 2.4.49 ((Ubuntu))") into
/// search terms for Exploit-DB and the knowledge base.
struct ServiceQuery {
    let service: String        // nmap service name, e.g. "http"
    let product: [String]      // e.g. ["apache"]
    let version: String?       // e.g. "2.4.49"

    /// Words that say nothing about the product.
    private static let noise: Set<String> = [
        "httpd", "sshd", "ftpd", "smbd", "named", "daemon", "server", "service", "protocol", "version",
        "ubuntu", "debian", "linux", "unix", "centos", "redhat", "fedora", "freebsd", "x86_64", "i386",
        "or", "and", "the", "with", "workgroup", "domain",
    ]

    /// Friendlier search words for nmap service names that are not product names.
    private static let serviceWords: [String: String] = [
        "microsoft-ds": "smb", "netbios-ssn": "netbios", "ms-wbt-server": "rdp", "domain": "dns",
        "ms-sql-s": "mssql", "kerberos-sec": "kerberos", "ssl/http": "https", "http-proxy": "proxy",
        "wsman": "winrm", "submission": "smtp", "ldapssl": "ldap", "globalcatldap": "ldap",
    ]

    private static let versionRegex = try! NSRegularExpression(pattern: #"^v?(\d+(?:\.\d+)+)"#)

    init(node: TargetNode) {
        let parts = node.subtitle.components(separatedBy: " — ")
        service = parts.first?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        var detail = parts.dropFirst().joined(separator: " ")
        // Drop everything after the first "[" (state) and the parenthesised extras.
        if let bracket = detail.firstIndex(of: "[") { detail = String(detail[..<bracket]) }
        detail = detail.replacingOccurrences(of: #"\([^)]*\)"#, with: " ", options: .regularExpression)

        var product: [String] = []
        var version: String? = nil
        for token in detail.split(whereSeparator: { $0.isWhitespace }) {
            let word = String(token).trimmingCharacters(in: CharacterSet(charactersIn: ",;:"))
            if version == nil, let match = ServiceQuery.versionRegex.firstMatch(in: word, range: NSRange(word.startIndex..., in: word)),
               let range = Range(match.range(at: 1), in: word) {
                version = String(word[range])
                break   // the product name is everything before the version
            }
            let lower = word.lowercased()
            // A bare number (Windows Server 2019, build 17763) ends the product name too.
            if !lower.isEmpty, lower.allSatisfy({ $0.isNumber }) { break }
            if !lower.isEmpty, !ServiceQuery.noise.contains(lower), lower.rangeOfCharacter(from: .letters) != nil {
                product.append(lower)
            }
            if product.count == 3 { break }
        }
        self.product = product
        self.version = version
    }

    /// Words that are useless on their own as an Exploit-DB query.
    private static let generic: Set<String> = ["windows", "microsoft", "linux", "unix", "http", "https", "ssl", "tcp", "udp"]

    /// Terms for Exploit-DB: product words plus the version (version-aware search). Nil when
    /// there is no usable product name, because a bare service name would match far too much.
    var exploitTerms: [String]? {
        guard !product.isEmpty else { return nil }
        if version == nil, product.allSatisfy({ ServiceQuery.generic.contains($0) }) { return nil }
        return version.map { product + [$0] } ?? product
    }

    /// Fallback without the version, when the precise search finds nothing.
    var exploitTermsLoose: [String]? {
        product.isEmpty ? nil : Array(product.prefix(2))
    }

    /// Terms for the knowledge base: the product, or otherwise the service word.
    var knowledgeTerms: [String] {
        if !product.isEmpty { return Array(product.prefix(2)) }
        let word = ServiceQuery.serviceWords[service] ?? service
        return word.isEmpty ? [] : [word]
    }

    var displayQuery: String {
        (exploitTerms ?? knowledgeTerms).joined(separator: " ")
    }
}

/// Exploit-DB and knowledge-base hits for the service on a port node, with one-click navigation.
struct SuggestionsPanel: View {
    let node: TargetNode
    @Environment(ExploitStore.self) private var exploits
    @Environment(KnowledgeBaseStore.self) private var knowledge
    @State private var exploitHits: [ExploitHit] = []
    @State private var exploitQuery = ""
    @State private var expanded = true

    private var query: ServiceQuery { ServiceQuery(node: node) }

    var body: some View {
        let kbTerms = query.knowledgeTerms
        let kbHits = knowledge.quickSearch(terms: kbTerms, limit: 6)
        let hasExploitDB = exploits.hasDatabase
        DisclosureGroup(isExpanded: $expanded) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Exploit-DB", systemImage: "ladybug")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if !hasExploitDB {
                        Text("No database yet — open the Searchsploit tab and click Download.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if query.exploitTerms == nil {
                        Text("No product/version in the nmap output for this port.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if exploitHits.isEmpty {
                        Text("Nothing found for \"\(exploitQuery)\".")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(exploitHits) { hit in
                            Button {
                                exploits.show(entryID: hit.entry.id, query: exploitQuery)
                            } label: {
                                HStack(spacing: 6) {
                                    Text(hit.entry.date.prefix(4))
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                    Text(hit.entry.title)
                                        .font(.caption)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    if hit.entry.verified {
                                        Image(systemName: "checkmark.seal.fill")
                                            .font(.caption2)
                                            .foregroundStyle(.green)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help(hit.entry.title)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    Label("Knowledge base", systemImage: "books.vertical")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if knowledge.isEmpty {
                        Text("No knowledge base imported yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if kbTerms.isEmpty {
                        Text("No service name for this port.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if kbHits.isEmpty {
                        Text("Nothing found for \"\(kbTerms.joined(separator: " "))\".")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(kbHits) { hit in
                            let roles = knowledge.roles(for: hit.table)
                            Button {
                                knowledge.show(recordID: hit.record.id, query: kbTerms.joined(separator: " "))
                            } label: {
                                HStack(spacing: 6) {
                                    if let id = roles.idColumn {
                                        Text(hit.record.value(id))
                                            .font(.system(.caption2, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(roles.titleColumn.map { hit.record.value($0) } ?? "")
                                        .font(.caption)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    if let severity = roles.severityColumn.map({ hit.record.value($0) }), !severity.isEmpty {
                                        SeverityBadge(value: severity)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 4)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "lightbulb")
                Text("Suggestions for \(query.displayQuery.isEmpty ? node.title : query.displayQuery)")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if hasExploitDB, !exploitHits.isEmpty {
                    Text("\(exploitHits.count) exploit\(exploitHits.count == 1 ? "" : "s")")
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.white.opacity(0.1), in: Capsule())
                }
                if !kbHits.isEmpty {
                    Text("\(kbHits.count) finding\(kbHits.count == 1 ? "" : "s")")
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.white.opacity(0.1), in: Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: "\(node.subtitle)|\(exploits.entries.count)") {
            runExploitSearch()
        }
    }

    private func runExploitSearch() {
        guard let terms = query.exploitTerms else {
            exploitHits = []
            return
        }
        exploitQuery = terms.joined(separator: " ")
        exploits.quickSearch(terms: terms, limit: 6) { hits in
            if !hits.isEmpty || query.exploitTermsLoose == nil || query.exploitTermsLoose == terms {
                exploitHits = hits
                return
            }
            // Nothing for the exact version: try the product alone.
            let loose = query.exploitTermsLoose ?? []
            exploits.quickSearch(terms: loose, limit: 6) { looseHits in
                exploitHits = looseHits
                if !looseHits.isEmpty { exploitQuery = loose.joined(separator: " ") }
            }
        }
    }
}
