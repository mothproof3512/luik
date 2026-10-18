import AppKit
import Foundation
import Observation
import SwiftUI

/// Shodan's REST API with the key from the Keychain. Host and domain lookups cost no query
/// credits on a paid plan; search does (one credit per page). Shodan allows about one request
/// per second, so bulk work is paced. Every call is written to the Log: a lookup is a request
/// to a third party about the client's systems, and the client may ask what was looked up where.
struct ShodanService: Identifiable {
    let id = UUID()
    var port: Int
    var transport: String
    var product: String
    var version: String
    var title: String
    var server: String
    var module: String
    var timestamp: String
    var banner: String
    var cpe: [String]
    var vulns: [String]
    var tags: [String]
    var sslSubject: String
    var sslIssuer: String
    var sslExpires: String

    var serviceLine: String {
        var parts: [String] = []
        if !product.isEmpty { parts.append(product) }
        if !version.isEmpty { parts.append(version) }
        if parts.isEmpty && !module.isEmpty { parts.append(module) }
        if !title.isEmpty { parts.append("“\(title)”") }
        return parts.joined(separator: " ")
    }
}

struct ShodanHost {
    var ip: String
    var hostnames: [String]
    var domains: [String]
    var org: String
    var isp: String
    var asn: String
    var country: String
    var city: String
    var os: String
    var lastUpdate: String
    var tags: [String]
    var vulns: [String]
    var ports: [Int]
    var services: [ShodanService]
    var raw: [String: Any]
}

struct ShodanDomainRecord: Identifiable {
    let id = UUID()
    var subdomain: String
    var type: String
    var value: String
    var lastSeen: String
    var fullName: String
}

struct ShodanDomain {
    var domain: String
    var subdomains: [String]
    var records: [ShodanDomainRecord]
    var tags: [String]
}

struct ShodanSearchHit: Identifiable {
    let id = UUID()
    var ip: String
    var port: Int
    var transport: String
    var org: String
    var hostnames: [String]
    var product: String
    var version: String
    var title: String
    var timestamp: String
    var vulns: [String]
}

struct ShodanSearch {
    var query: String
    var total: Int
    var page: Int
    var hits: [ShodanSearchHit]
}

enum ShodanError: Error, LocalizedError {
    case noKey, http(Int, String), network(String), decode

    var errorDescription: String? {
        switch self {
        case .noKey: return "No Shodan API key — Settings › Integrations › Shodan."
        case .http(let code, let message): return "Shodan answered HTTP \(code)\(message.isEmpty ? "" : ": \(message)")"
        case .network(let message): return message
        case .decode: return "Shodan's answer could not be read."
        }
    }
}

enum ShodanAPI {
    static let base = "https://api.shodan.io"

    static var key: String { KeychainItem.shodanKey.read() ?? "" }
    static var hasKey: Bool { !key.isEmpty }

    /// Synchronous GET (called from a background queue).
    static func get(_ path: String, query: [String: String] = [:]) throws -> Any {
        guard hasKey else { throw ShodanError.noKey }
        var components = URLComponents(string: base + path)!
        var items = [URLQueryItem(name: "key", value: key)]
        for (name, value) in query { items.append(URLQueryItem(name: name, value: value)) }
        components.queryItems = items
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let semaphore = DispatchSemaphore(value: 0)
        var payload: Data?
        var status = 0
        var failure: Error?
        URLSession.shared.dataTask(with: request) { data, response, error in
            payload = data
            status = (response as? HTTPURLResponse)?.statusCode ?? 0
            failure = error
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 35)
        if let failure { throw ShodanError.network(failure.localizedDescription) }
        guard let payload else { throw ShodanError.network("No answer from Shodan (timeout).") }
        let json = try? JSONSerialization.jsonObject(with: payload)
        if status != 200 {
            let message = (json as? [String: Any])?["error"] as? String ?? ""
            throw ShodanError.http(status, message)
        }
        guard let json else { throw ShodanError.decode }
        return json
    }

    static func string(_ dict: [String: Any], _ key: String) -> String {
        if let value = dict[key] as? String { return value }
        if let value = dict[key] as? Int { return String(value) }
        if let value = dict[key] as? Double { return String(value) }
        return ""
    }

    static func strings(_ dict: [String: Any], _ key: String) -> [String] {
        (dict[key] as? [Any])?.compactMap { $0 as? String } ?? []
    }

    static func apiInfo() throws -> (plan: String, queryCredits: Int, scanCredits: Int) {
        guard let info = try get("/api-info") as? [String: Any] else { throw ShodanError.decode }
        return (string(info, "plan"), info["query_credits"] as? Int ?? 0, info["scan_credits"] as? Int ?? 0)
    }

    static func host(_ ip: String) throws -> ShodanHost {
        guard let json = try get("/shodan/host/\(ip)") as? [String: Any] else { throw ShodanError.decode }
        return parseHost(json)
    }

    static func parseHost(_ json: [String: Any]) -> ShodanHost {
        let services = ((json["data"] as? [[String: Any]]) ?? []).map(parseService)
        let vulns = (json["vulns"] as? [String]) ?? Array(((json["vulns"] as? [String: Any]) ?? [:]).keys)
        return ShodanHost(ip: string(json, "ip_str"),
                          hostnames: strings(json, "hostnames"),
                          domains: strings(json, "domains"),
                          org: string(json, "org"), isp: string(json, "isp"), asn: string(json, "asn"),
                          country: string(json, "country_name"), city: string(json, "city"),
                          os: string(json, "os"), lastUpdate: string(json, "last_update"),
                          tags: strings(json, "tags"), vulns: vulns.sorted(),
                          ports: ((json["ports"] as? [Int]) ?? []).sorted(),
                          services: services.sorted { $0.port < $1.port },
                          raw: json)
    }

    static func parseService(_ item: [String: Any]) -> ShodanService {
        let http = item["http"] as? [String: Any] ?? [:]
        let ssl = item["ssl"] as? [String: Any] ?? [:]
        let cert = ssl["cert"] as? [String: Any] ?? [:]
        let subject = cert["subject"] as? [String: Any] ?? [:]
        let issuer = cert["issuer"] as? [String: Any] ?? [:]
        let shodan = item["_shodan"] as? [String: Any] ?? [:]
        let vulns = (item["vulns"] as? [String]) ?? Array(((item["vulns"] as? [String: Any]) ?? [:]).keys)
        return ShodanService(port: item["port"] as? Int ?? 0,
                             transport: string(item, "transport"),
                             product: string(item, "product"), version: string(item, "version"),
                             title: string(http, "title").trimmingCharacters(in: .whitespacesAndNewlines),
                             server: string(http, "server"),
                             module: string(shodan, "module"),
                             timestamp: String(string(item, "timestamp").prefix(16)).replacingOccurrences(of: "T", with: " "),
                             banner: string(item, "data"),
                             cpe: strings(item, "cpe23").isEmpty ? strings(item, "cpe") : strings(item, "cpe23"),
                             vulns: vulns.sorted(), tags: strings(item, "tags"),
                             sslSubject: string(subject, "CN"), sslIssuer: string(issuer, "O").isEmpty ? string(issuer, "CN") : string(issuer, "O"),
                             sslExpires: string(cert, "expires"))
    }

    static func domain(_ domain: String) throws -> ShodanDomain {
        guard let json = try get("/dns/domain/\(domain)") as? [String: Any] else { throw ShodanError.decode }
        let records = ((json["data"] as? [[String: Any]]) ?? []).map { record -> ShodanDomainRecord in
            let sub = string(record, "subdomain")
            return ShodanDomainRecord(subdomain: sub, type: string(record, "type"), value: string(record, "value"),
                                      lastSeen: String(string(record, "last_seen").prefix(10)),
                                      fullName: sub.isEmpty ? domain : "\(sub).\(domain)")
        }
        return ShodanDomain(domain: domain, subdomains: strings(json, "subdomains").sorted(), records: records, tags: strings(json, "tags"))
    }

    static func search(_ query: String, page: Int) throws -> ShodanSearch {
        guard let json = try get("/shodan/host/search", query: ["query": query, "page": String(page)]) as? [String: Any] else { throw ShodanError.decode }
        let hits = ((json["matches"] as? [[String: Any]]) ?? []).map { match -> ShodanSearchHit in
            let http = match["http"] as? [String: Any] ?? [:]
            let vulns = (match["vulns"] as? [String]) ?? Array(((match["vulns"] as? [String: Any]) ?? [:]).keys)
            return ShodanSearchHit(ip: string(match, "ip_str"), port: match["port"] as? Int ?? 0, transport: string(match, "transport"),
                                   org: string(match, "org"), hostnames: strings(match, "hostnames"),
                                   product: string(match, "product"), version: string(match, "version"),
                                   title: string(http, "title").trimmingCharacters(in: .whitespacesAndNewlines),
                                   timestamp: String(string(match, "timestamp").prefix(10)), vulns: vulns.sorted())
        }
        return ShodanSearch(query: query, total: json["total"] as? Int ?? hits.count, page: page, hits: hits)
    }

    // MARK: - Into Targets

    static func parsedHost(_ host: ShodanHost) -> ParsedHost {
        var parsed = ParsedHost(address: host.ip, hostname: host.hostnames.first ?? "")
        parsed.os = host.os.isEmpty ? "" : "OS (Shodan): \(host.os)"
        var extra: [String] = []
        let who = [host.org, host.isp].filter { !$0.isEmpty }
        if !who.isEmpty { extra.append("Shodan: \(who.joined(separator: " / "))\(host.asn.isEmpty ? "" : " · \(host.asn)")\(host.country.isEmpty ? "" : " · \(host.city.isEmpty ? host.country : "\(host.city), \(host.country)")")") }
        if host.hostnames.count > 1 { extra.append("Hostnames (Shodan): \(host.hostnames.joined(separator: ", "))") }
        if !host.tags.isEmpty { extra.append("Tags (Shodan): \(host.tags.joined(separator: ", "))") }
        if !host.vulns.isEmpty { extra.append("Vulns (Shodan, banner-based — verify): \(host.vulns.joined(separator: ", "))") }
        if !host.lastUpdate.isEmpty { extra.append("Shodan last seen: \(String(host.lastUpdate.prefix(10)))") }
        parsed.extra = extra
        for service in host.services {
            var scripts: [String] = ["Shodan \(service.timestamp)\(service.module.isEmpty ? "" : " · \(service.module)")"]
            if !service.title.isEmpty { scripts.append("Title: \(service.title)") }
            if !service.server.isEmpty { scripts.append("Server: \(service.server)") }
            if !service.sslSubject.isEmpty { scripts.append("TLS: \(service.sslSubject) (\(service.sslIssuer))\(service.sslExpires.isEmpty ? "" : ", expires \(String(service.sslExpires.prefix(8)))")") }
            if !service.cpe.isEmpty { scripts.append("CPE: \(service.cpe.joined(separator: ", "))") }
            if !service.vulns.isEmpty { scripts.append("Vulns: \(service.vulns.joined(separator: ", "))") }
            let bannerLines = service.banner.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            scripts.append(contentsOf: bannerLines.prefix(12).map { "  \($0)" })
            parsed.ports.append(ParsedPort(number: service.port, proto: service.transport.isEmpty ? "tcp" : service.transport, state: "open",
                                           service: service.product.isEmpty ? service.module : service.product, version: service.version, scripts: scripts))
        }
        // Ports Shodan lists without a banner record.
        for port in host.ports where !parsed.ports.contains(where: { $0.number == port }) {
            parsed.ports.append(ParsedPort(number: port, proto: "tcp", state: "open", service: "", version: "", scripts: ["Shodan: port listed, no banner"]))
        }
        return parsed
    }

    static func markdown(host: ShodanHost) -> String {
        var out = "## Shodan — \(host.ip)\n\n"
        let facts: [(String, String)] = [("Hostnames", host.hostnames.joined(separator: ", ")), ("Organisation", host.org), ("ISP", host.isp), ("ASN", host.asn),
                                         ("Location", [host.city, host.country].filter { !$0.isEmpty }.joined(separator: ", ")), ("OS", host.os),
                                         ("Tags", host.tags.joined(separator: ", ")), ("Vulns (banner-based)", host.vulns.joined(separator: ", ")), ("Last update", host.lastUpdate)]
        for (label, value) in facts where !value.isEmpty { out += "- \(label): \(value)\n" }
        out += "\n| Port | Service | Seen |\n|---|---|---|\n"
        for service in host.services { out += "| \(service.port)/\(service.transport) | \(service.serviceLine) | \(service.timestamp) |\n" }
        return out + "\n"
    }
}

/// State of the Shodan tool.
@Observable
final class ShodanStore {
    static let shared = ShodanStore()

    enum Mode: String, CaseIterable, Identifiable {
        case host = "Host", domain = "Domain", search = "Search"
        var id: String { rawValue }
    }

    var mode: Mode = .host
    var query = ""
    var isRunning = false
    var error: String?
    var host: ShodanHost?
    var domain: ShodanDomain?
    var search: ShodanSearch?
    var plan: String?
    var credits: Int?

    func checkKey() {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let info = try ShodanAPI.apiInfo()
                DispatchQueue.main.async { self.plan = info.plan; self.credits = info.queryCredits; self.error = nil }
            } catch {
                DispatchQueue.main.async { self.plan = nil; self.credits = nil; self.error = error.localizedDescription }
            }
        }
    }

    func run() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard ShodanAPI.hasKey else { error = ShodanError.noKey.localizedDescription; return }
        isRunning = true
        error = nil
        let mode = self.mode
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                switch mode {
                case .host:
                    let address = DNSLookup.isIPAddress(text) ? text : (DNS.a(text).first ?? text)
                    let host = try ShodanAPI.host(address)
                    DispatchQueue.main.async {
                        self.host = host
                        ActivityLog.shared.record(.action, "Shodan host lookup \(address)\(text == address ? "" : " (\(text))"): \(host.services.count) service(s), \(host.vulns.count) vuln(s)", source: "Tools", host: address)
                    }
                case .domain:
                    let domain = try ShodanAPI.domain(text.lowercased())
                    DispatchQueue.main.async {
                        self.domain = domain
                        ActivityLog.shared.record(.action, "Shodan domain lookup \(text): \(domain.subdomains.count) subdomain(s), \(domain.records.count) record(s)", source: "Tools")
                    }
                case .search:
                    let search = try ShodanAPI.search(text, page: 1)
                    DispatchQueue.main.async {
                        self.search = search
                        ActivityLog.shared.record(.action, "Shodan search “\(text)”: \(search.total) result(s) (1 query credit)", source: "Tools")
                    }
                }
                DispatchQueue.main.async { self.isRunning = false }
            } catch {
                DispatchQueue.main.async { self.error = error.localizedDescription; self.isRunning = false }
            }
        }
    }

    func loadMore(page: Int) {
        guard let current = search else { return }
        isRunning = true
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let next = try ShodanAPI.search(current.query, page: page)
                DispatchQueue.main.async {
                    self.search = ShodanSearch(query: current.query, total: next.total, page: page, hits: current.hits + next.hits)
                    self.isRunning = false
                    ActivityLog.shared.record(.action, "Shodan search “\(current.query)” page \(page) (1 query credit)", source: "Tools")
                }
            } catch {
                DispatchQueue.main.async { self.error = error.localizedDescription; self.isRunning = false }
            }
        }
    }

    /// Looks every host in Targets up (one request per second) and merges what Shodan knows.
    func enrichTargets(addresses: [String]) {
        guard ShodanAPI.hasKey, !addresses.isEmpty else { return }
        isRunning = true
        UIState.shared.progress = "Shodan 0 / \(addresses.count)"
        DispatchQueue.global(qos: .userInitiated).async {
            var done = 0
            var found = 0
            var failures: [String] = []
            for address in addresses {
                do {
                    let host = try ShodanAPI.host(address)
                    found += 1
                    DispatchQueue.main.sync {
                        _ = TargetStore.shared.importParsedHosts([ShodanAPI.parsedHost(host)], source: "Shodan")
                    }
                } catch ShodanError.http(404, _) {
                    // Shodan has nothing on it: fine.
                } catch {
                    failures.append("\(address): \(error.localizedDescription)")
                    if case ShodanError.http(401, _) = error { break }
                }
                done += 1
                DispatchQueue.main.async { UIState.shared.progress = "Shodan \(done) / \(addresses.count)" }
                Thread.sleep(forTimeInterval: 1.1)
            }
            DispatchQueue.main.async {
                self.isRunning = false
                UIState.shared.progress = nil
                self.error = failures.isEmpty ? nil : failures.prefix(3).joined(separator: "\n")
                ActivityLog.shared.record(.action, "Shodan enrichment: \(found) of \(addresses.count) host(s) known to Shodan, merged into Targets", source: "Tools")
                UIState.shared.flash("Shodan: \(found) of \(addresses.count) hosts enriched.", seconds: 3)
            }
        }
    }
}

struct ShodanView: View {
    @Environment(TargetStore.self) private var targets
    @Environment(FindingsStore.self) private var findings
    @Environment(UIState.self) private var ui
    @Environment(\.luikTheme) private var theme
    @State private var expandedBanners: Set<UUID> = []

    var body: some View {
        @Bindable var store = ShodanStore.shared
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Picker("", selection: $store.mode) {
                    ForEach(ShodanStore.Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
                TextField(placeholder, text: $store.query)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 360)
                    .onSubmit { store.run() }
                Button {
                    store.run()
                } label: {
                    Label(store.mode == .search ? "Search (1 credit)" : "Look up", systemImage: "binoculars")
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.isRunning || store.query.trimmingCharacters(in: .whitespaces).isEmpty)
                if store.isRunning {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                Menu {
                    let addresses = targets.hosts.map { $0.address }.filter { DNSLookup.isIPAddress($0) }
                    Button("Enrich all \(addresses.count) hosts in Targets (\(addresses.count) requests)") { store.enrichTargets(addresses: addresses) }
                        .disabled(addresses.isEmpty || store.isRunning)
                    Divider()
                    Button("Check API key and credits") { store.checkKey() }
                    Button("Settings › Integrations › Shodan") { ui.showSettings = true }
                } label: {
                    Label(store.plan.map { "\($0) · \(store.credits ?? 0) credits" } ?? "Shodan", systemImage: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            if let error = store.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .padding()
            }
            if !ShodanAPI.hasKey {
                EmptyState(icon: "binoculars", title: "Shodan",
                           message: "Put your API key in Settings › Integrations (it is kept in the Keychain). Host and domain lookups are free on a paid plan; a search costs one credit per page.") {
                    Button("Open Settings") { ui.showSettings = true }
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        switch store.mode {
                        case .host: if let host = store.host { hostView(host) } else { intro("Host: an IP address (or a name, resolved first) — what Shodan has seen on it: organisation, ports, banners, titles, certificates, CVEs by banner. Free on a paid plan.") }
                        case .domain: if let domain = store.domain { domainView(domain) } else { intro("Domain: the subdomains and DNS records Shodan knows for a domain — a second subdomain source next to Certificate Transparency.") }
                        case .search: if let search = store.search { searchView(search) } else { intro("Search: a Shodan query such as org:\"Example Corp\", net:203.0.113.0/24, ssl.cert.subject.cn:example.com or hostname:example.com. One query credit per page of 100 results.") }
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .onAppear { if ShodanAPI.hasKey, ShodanStore.shared.plan == nil { ShodanStore.shared.checkKey() } }
    }

    private var placeholder: String {
        switch ShodanStore.shared.mode {
        case .host: return "IP address or host name"
        case .domain: return "example.com"
        case .search: return "org:\"Example Corp\"  ·  net:203.0.113.0/24  ·  ssl.cert.subject.cn:example.com"
        }
    }

    private func intro(_ text: String) -> some View {
        Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Host

    private func hostView(_ host: ShodanHost) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(host.ip).font(.title2.weight(.semibold))
                if !host.hostnames.isEmpty { Text(host.hostnames.prefix(3).joined(separator: ", ") + (host.hostnames.count > 3 ? " +\(host.hostnames.count - 3)" : "")).font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(ShodanAPI.markdown(host: host), forType: .string)
                } label: { Label("Copy as Markdown", systemImage: "doc.on.doc") }
                Button {
                    let result = targets.importParsedHosts([ShodanAPI.parsedHost(host)], source: "Shodan")
                    ui.flash("Shodan → Targets: \(result.summary)", seconds: 3)
                } label: { Label("Add to Targets", systemImage: "network") }
                    .help("Host, ports, products/versions and banners into Targets — merged like a scan import")
                if !host.vulns.isEmpty {
                    Button { createFinding(host) } label: { Label("Finding from vulns", systemImage: "exclamationmark.triangle") }
                        .help("A finding that lists the CVEs Shodan derived from banners — mark it as to-verify")
                }
                Link(destination: URL(string: "https://www.shodan.io/host/\(host.ip)")!) { Image(systemName: "arrow.up.right.square") }
                    .help("Open on shodan.io")
            }
            .controlSize(.small)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
                fact("Organisation", host.org); fact("ISP", host.isp); fact("ASN", host.asn)
                fact("Location", [host.city, host.country].filter { !$0.isEmpty }.joined(separator: ", "))
                fact("OS", host.os); fact("Tags", host.tags.joined(separator: ", ")); fact("Last update", String(host.lastUpdate.prefix(16)).replacingOccurrences(of: "T", with: " "))
                fact("Hostnames", host.hostnames.joined(separator: ", "))
                fact("Domains", host.domains.joined(separator: ", "))
            }
            .font(.caption)
            if !host.vulns.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Vulnerabilities by banner (\(host.vulns.count)) — Shodan matches versions to CVEs; it does not test. Verify before reporting.")
                        .font(.caption.weight(.semibold)).foregroundStyle(.orange)
                    Text(host.vulns.joined(separator: "  ")).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                }
                .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            }
            Text("Services (\(host.services.count)) · ports \(host.ports.map(String.init).joined(separator: ", "))")
                .font(.subheadline.weight(.semibold))
            ForEach(host.services) { service in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("\(service.port)/\(service.transport)").font(.system(.callout, design: .monospaced).weight(.semibold)).frame(width: 90, alignment: .leading)
                        Text(service.serviceLine.isEmpty ? "—" : service.serviceLine).lineLimit(1)
                        if !service.vulns.isEmpty { Text("\(service.vulns.count) CVE").font(.caption2).padding(.horizontal, 5).background(Color.orange.opacity(0.3), in: Capsule()) }
                        if !service.sslSubject.isEmpty { Text("TLS \(service.sslSubject)").font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                        Spacer()
                        Text(service.timestamp).font(.caption2).foregroundStyle(.tertiary)
                        Button(expandedBanners.contains(service.id) ? "Hide banner" : "Banner") {
                            if expandedBanners.contains(service.id) { expandedBanners.remove(service.id) } else { expandedBanners.insert(service.id) }
                        }
                        .controlSize(.mini).buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                    if expandedBanners.contains(service.id) {
                        Text(service.banner.isEmpty ? "(no banner)" : service.banner)
                            .font(.system(.caption2, design: .monospaced)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(6)
                            .background(Color.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                        if !service.cpe.isEmpty { Text("CPE: \(service.cpe.joined(separator: ", "))").font(.caption2).foregroundStyle(.secondary).textSelection(.enabled) }
                        if !service.vulns.isEmpty { Text("Vulns: \(service.vulns.joined(separator: ", "))").font(.caption2).foregroundStyle(.orange).textSelection(.enabled) }
                    }
                }
                .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                .contextMenu {
                    if !service.product.isEmpty {
                        Button("Version check: \(service.product) \(service.version)") {
                            VersionCheck.shared.prefill(product: service.product, version: service.version)
                            ui.open(.versionCheck)
                        }
                    }
                    Button("Copy banner") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(service.banner, forType: .string)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func fact(_ label: String, _ value: String) -> some View {
        if !value.isEmpty {
            GridRow {
                Text(label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                Text(value).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func createFinding(_ host: ShodanHost) {
        var finding = Finding(title: "Publicly indexed services with known vulnerabilities on \(host.ip)")
        finding.severity = .medium
        finding.description = "Shodan lists \(host.vulns.count) CVE(s) for \(host.ip)\(host.hostnames.isEmpty ? "" : " (\(host.hostnames.joined(separator: ", ")))"), derived from service banners (not tested):\n\n" + host.vulns.map { "- \($0)" }.joined(separator: "\n")
            + "\n\nServices: " + host.services.map { "\($0.port)/\($0.transport) \($0.serviceLine)" }.joined(separator: "; ")
            + "\n\nTO VERIFY: banner-based matches include false positives (backported patches); confirm each CVE before reporting."
        finding.impact = "Services whose version strings match public CVEs are the first thing any attacker tries; internet-wide indexes make them trivially discoverable."
        finding.recommendation = "Verify the listed CVEs against the actual patch level, update or mitigate the affected services, and reduce the exposed service set and banner detail."
        finding.affected = [host.ip] + host.hostnames.prefix(3)
        finding.references = "https://www.shodan.io/host/\(host.ip)"
        finding.source = "Shodan"
        _ = findings.add(finding)
        ActivityLog.shared.record(.action, "Finding “\(finding.title)” created from Shodan (to verify)", source: "Tools", host: host.ip)
    }

    // MARK: Domain

    private func domainView(_ domain: ShodanDomain) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(domain.domain).font(.title2.weight(.semibold))
                Text("\(domain.subdomains.count) subdomains · \(domain.records.count) records\(domain.tags.isEmpty ? "" : " · \(domain.tags.joined(separator: ", "))")").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    let names = domain.records.filter { $0.type == "A" }.map { $0.fullName }
                    addNames(Array(Set(names)).sorted())
                } label: { Label("Add A-record hosts to Targets", systemImage: "network") }
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(domain.subdomains.map { "\($0).\(domain.domain)" }.joined(separator: "\n"), forType: .string)
                } label: { Label("Copy subdomains", systemImage: "doc.on.doc") }
            }
            .controlSize(.small)
            VStack(spacing: 0) {
                ForEach(domain.records.sorted { ($0.subdomain, $0.type) < ($1.subdomain, $1.type) }) { record in
                    HStack(spacing: 8) {
                        Text(record.fullName).font(.system(.caption, design: .monospaced)).frame(minWidth: 260, alignment: .leading).textSelection(.enabled)
                        Text(record.type).font(.caption2.weight(.semibold)).frame(width: 46, alignment: .leading)
                        Text(record.value).font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1).textSelection(.enabled)
                        Spacer()
                        Text(record.lastSeen).font(.caption2).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 2)
                    .contextMenu {
                        Button("Shodan host lookup \(record.type == "A" ? record.value : record.fullName)") {
                            ShodanStore.shared.mode = .host
                            ShodanStore.shared.query = record.type == "A" ? record.value : record.fullName
                            ShodanStore.shared.run()
                        }
                        Button("DNS & RDAP lookup") {
                            DNSLookup.shared.query = record.fullName
                            ui.open(.dnsLookup)
                            DNSLookup.shared.run()
                        }
                        Button("Add to Targets") { addNames([record.fullName]) }
                    }
                }
            }
            .padding(8).background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    // MARK: Search

    private func searchView(_ search: ShodanSearch) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("\(search.total) results").font(.title3.weight(.semibold))
                Text("for \(search.query) · \(search.hits.count) loaded").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    addNames(Array(Set(search.hits.map { $0.ip })).sorted())
                } label: { Label("Add all hosts to Targets", systemImage: "network") }
                if search.hits.count < search.total {
                    Button("Load page \(search.page + 1) (1 credit)") { ShodanStore.shared.loadMore(page: search.page + 1) }
                        .disabled(ShodanStore.shared.isRunning)
                }
            }
            .controlSize(.small)
            VStack(spacing: 0) {
                ForEach(search.hits) { hit in
                    HStack(spacing: 8) {
                        Text("\(hit.ip):\(hit.port)").font(.system(.caption, design: .monospaced)).frame(width: 170, alignment: .leading).textSelection(.enabled)
                        Text([hit.product, hit.version].filter { !$0.isEmpty }.joined(separator: " ") + (hit.title.isEmpty ? "" : " “\(hit.title)”")).font(.caption).lineLimit(1)
                        if !hit.vulns.isEmpty { Text("\(hit.vulns.count) CVE").font(.caption2).padding(.horizontal, 5).background(Color.orange.opacity(0.3), in: Capsule()) }
                        Spacer()
                        Text(hit.hostnames.first ?? hit.org).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        Text(hit.timestamp).font(.caption2).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 2)
                    .contextMenu {
                        Button("Shodan host lookup \(hit.ip)") {
                            ShodanStore.shared.mode = .host
                            ShodanStore.shared.query = hit.ip
                            ShodanStore.shared.run()
                        }
                        Button("Add to Targets") { addNames([hit.ip]) }
                    }
                }
            }
            .padding(8).background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private func addNames(_ names: [String]) {
        guard !names.isEmpty else { return }
        let store = targets
        DispatchQueue.global(qos: .userInitiated).async {
            let resolved = names.map { ($0, DNSLookup.isIPAddress($0) ? $0 : (DNS.a($0).first ?? $0)) }
            DispatchQueue.main.async {
                for (name, address) in resolved {
                    let node = store.addHost(address: address, hostname: DNSLookup.isIPAddress(name) ? "" : name)
                    if node.subtitle.isEmpty, !DNSLookup.isIPAddress(name) { node.subtitle = name }
                }
                store.scheduleSave()
                UIState.shared.flash("\(resolved.count) host(s) added to Targets.", seconds: 2)
            }
        }
    }
}
