import AppKit
import Foundation
import Observation
import SwiftUI

struct DNSRecordSet: Identifiable {
    let id = UUID()
    var type: String
    var values: [String]
}

struct DNSLookupResult {
    var query: String
    var isAddress: Bool
    var checkedAt: Date
    var records: [DNSRecordSet] = []
    var reverse: [String] = []
    /// Name server → outcome of the zone-transfer attempt.
    var axfr: [(server: String, outcome: String, transferred: Bool)] = []
    var rdap: [(label: String, value: String)] = []
    var asn: String?
    var items: [CheckItem] = []
    var error: String?

    /// Every address seen (A/AAAA of the name, or the address itself) — for Targets.
    var addresses: [String] {
        if isAddress { return [query] }
        return records.filter { $0.type == "A" || $0.type == "AAAA" }.flatMap { $0.values }
    }
    var problems: [CheckItem] { items.filter { $0.level == .warn || $0.level == .fail } }
}

/// Records of a name (A, AAAA, CNAME, MX, NS, TXT, SOA, CAA, SRV for the common services),
/// reverse lookup for an address, a read-only zone-transfer attempt on each name server, and
/// who owns the domain / address range through RDAP (plus the ASN via Team Cymru's DNS).
@Observable
final class DNSLookup {
    static let shared = DNSLookup()

    static let recordTypes = ["A", "AAAA", "CNAME", "MX", "NS", "TXT", "SOA", "CAA"]
    static let srvServices = ["_ldap._tcp", "_kerberos._tcp", "_sip._tcp", "_sips._tcp", "_xmpp-server._tcp", "_autodiscover._tcp", "_caldavs._tcp", "_imaps._tcp", "_submission._tcp"]

    var query = ""
    var tryZoneTransfer = true
    var useRDAP = true
    var isRunning = false
    var result: DNSLookupResult?
    var error: String?

    func run() {
        var text = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for prefix in ["https://", "http://"] where text.hasPrefix(prefix) { text = String(text.dropFirst(prefix.count)) }
        text = text.split(separator: "/").first.map(String.init) ?? text
        if text.hasSuffix(".") { text.removeLast() }
        guard !text.isEmpty else { error = "Enter a domain name or an IP address."; return }
        isRunning = true
        error = nil
        let axfr = tryZoneTransfer
        let rdap = useRDAP
        DispatchQueue.global(qos: .userInitiated).async {
            let result = DNSLookup.lookup(text, zoneTransfer: axfr, rdap: rdap)
            DispatchQueue.main.async {
                self.result = result
                self.isRunning = false
                self.error = result.error
                ActivityLog.shared.record(.action, "DNS lookup for \(text): \(result.records.reduce(0) { $0 + $1.values.count }) record(s)\(result.axfr.contains { $0.transferred } ? ", ZONE TRANSFER ALLOWED" : "")", source: "Tools", host: result.isAddress ? text : nil)
            }
        }
    }

    static func isIPAddress(_ text: String) -> Bool {
        let v4 = text.split(separator: ".")
        if v4.count == 4, v4.allSatisfy({ Int($0).map { (0...255).contains($0) } ?? false }) { return true }
        return text.contains(":") && text.allSatisfy { $0.isHexDigit || $0 == ":" }
    }

    static func lookup(_ query: String, zoneTransfer: Bool, rdap: Bool) -> DNSLookupResult {
        var result = DNSLookupResult(query: query, isAddress: isIPAddress(query), checkedAt: Date())
        var items: [CheckItem] = []

        if result.isAddress {
            result.reverse = DNS.dig("-x", type: "PTR", extra: [query]).map { $0.hasSuffix(".") ? String($0.dropLast()) : $0 }
            items.append(CheckItem(level: result.reverse.isEmpty ? .info : .pass, text: result.reverse.isEmpty ? "No PTR record for \(query)." : "PTR: \(result.reverse.joined(separator: ", "))"))
            if let asn = cymruASN(query) {
                result.asn = asn
                items.append(CheckItem(level: .info, text: "ASN: \(asn)"))
            }
            if rdap { result.rdap = rdapIP(query) }
        } else {
            for type in recordTypes {
                let values = DNS.dig(query, type: type).map { $0.hasSuffix(".") && type != "TXT" ? String($0.dropLast()) : $0 }
                if !values.isEmpty { result.records.append(DNSRecordSet(type: type, values: values)) }
            }
            for service in srvServices {
                let values = DNS.dig("\(service).\(query)", type: "SRV")
                if !values.isEmpty { result.records.append(DNSRecordSet(type: "SRV \(service)", values: values)) }
            }
            let addresses = result.addresses
            if addresses.isEmpty {
                let cname = result.records.first { $0.type == "CNAME" }?.values ?? []
                items.append(CheckItem(level: cname.isEmpty ? .warn : .info, text: cname.isEmpty ? "No A/AAAA record for \(query)." : "CNAME → \(cname.joined(separator: ", ")) without a resolved address."))
            } else {
                items.append(CheckItem(level: .pass, text: "Resolves to \(addresses.joined(separator: ", "))."))
                for address in addresses.prefix(4) {
                    let ptr = DNS.dig("-x", type: "PTR", extra: [address]).map { $0.hasSuffix(".") ? String($0.dropLast()) : $0 }
                    if !ptr.isEmpty { result.reverse.append("\(address) → \(ptr.joined(separator: ", "))") }
                }
                if let first = addresses.first(where: { !$0.contains(":") }), let asn = cymruASN(first) {
                    result.asn = asn
                    items.append(CheckItem(level: .info, text: "ASN of \(first): \(asn)"))
                }
            }
            if let cname = result.records.first(where: { $0.type == "CNAME" })?.values.first {
                let target = cname.lowercased()
                let danglingHints = ["amazonaws.com", "azurewebsites.net", "cloudfront.net", "github.io", "herokuapp.com", "trafficmanager.net", "cloudapp.net", "s3-website", "myshopify.com", "zendesk.com", "readme.io", "ghost.io", "pantheonsite.io", "netlify.app", "surge.sh", "wpengine.com", "fastly.net", "blob.core.windows.net"]
                if danglingHints.contains(where: { target.hasSuffix($0) || target.contains($0) }) {
                    items.append(CheckItem(level: .info, text: "CNAME points at a third-party service (\(cname)) — check for subdomain takeover if the service answers with a “not found” page."))
                }
            }
            let nameServers = result.records.first { $0.type == "NS" }?.values ?? []
            if nameServers.isEmpty {
                items.append(CheckItem(level: .info, text: "No NS records at this name (a host name rather than a zone apex)."))
            } else {
                items.append(CheckItem(level: .pass, text: "Name servers: \(nameServers.joined(separator: ", "))."))
                if nameServers.count == 1 { items.append(CheckItem(level: .info, text: "Only one name server — no redundancy.")) }
                if zoneTransfer {
                    for server in nameServers {
                        let output = DNS.raw(["@\(server)", query, "AXFR", "+time=5", "+tries=1"])
                        let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty && !$0.hasPrefix(";") }
                        if output.contains("Transfer failed") || output.contains("transfer failed") || output.contains("REFUSED") || lines.isEmpty || output.contains("connection timed out") || output.contains("no servers could be reached") {
                            result.axfr.append((server, output.contains("timed out") || output.contains("no servers") ? "no answer" : "refused", false))
                        } else {
                            result.axfr.append((server, "\(lines.count) records transferred", true))
                            items.append(CheckItem(level: .fail, text: "Zone transfer allowed by \(server): \(lines.count) records of \(query) handed out to anyone — the whole zone is in the raw output below."))
                        }
                    }
                    if !result.axfr.contains(where: { $0.transferred }) {
                        items.append(CheckItem(level: .pass, text: "Zone transfer refused by all \(nameServers.count) name server(s)."))
                    }
                }
            }
            if let caa = result.records.first(where: { $0.type == "CAA" }) {
                items.append(CheckItem(level: .pass, text: "CAA: \(caa.values.joined(separator: "; ")) — only these CAs may issue certificates."))
            } else {
                items.append(CheckItem(level: .info, text: "No CAA record: any public CA may issue certificates for \(query)."))
            }
            if let txt = result.records.first(where: { $0.type == "TXT" }) {
                let verifications = txt.values.filter { $0.contains("-site-verification") || $0.contains("verification=") || $0.contains("_domainkey") || $0.hasPrefix("\"MS=") || $0.contains("docusign") || $0.contains("atlassian") }
                if !verifications.isEmpty {
                    items.append(CheckItem(level: .info, text: "TXT verification tokens reveal \(verifications.count) third-party service(s) in use (Google, Microsoft, Atlassian, …) — see the records."))
                }
            }
            if rdap { result.rdap = rdapDomain(query) }
        }
        if let expiry = result.rdap.first(where: { $0.label == "Expires" })?.value {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let date = formatter.date(from: expiry) ?? ISO8601DateFormatter().date(from: expiry)
            if let date {
                let days = Int(date.timeIntervalSinceNow / 86400)
                if days < 30 { items.append(CheckItem(level: days < 0 ? .fail : .warn, text: days < 0 ? "Domain registration expired \(-days) day(s) ago." : "Domain registration expires in \(days) day(s).")) }
            }
        }
        if let status = result.rdap.first(where: { $0.label == "Status" })?.value.lowercased() {
            if !status.contains("transfer prohibited") && !status.contains("transferprohibited") && !result.isAddress {
                items.append(CheckItem(level: .info, text: "No transfer lock on the domain (status: \(status))."))
            }
        }
        result.items = items.sorted { $0.level.rawValue > $1.level.rawValue }
        return result
    }

    /// `origin.asn.cymru.com` TXT: "15169 | 8.8.8.0/24 | US | arin | 2023-12-28"
    static func cymruASN(_ ipv4: String) -> String? {
        let parts = ipv4.split(separator: ".")
        guard parts.count == 4 else { return nil }
        let reversed = parts.reversed().joined(separator: ".")
        guard let record = DNS.txt("\(reversed).origin.asn.cymru.com").first else { return nil }
        let fields = record.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        guard fields.count >= 3 else { return record }
        var text = "AS\(fields[0]) · \(fields[1]) · \(fields[2])"
        if let name = DNS.txt("AS\(fields[0]).asn.cymru.com").first {
            let nameFields = name.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            if let last = nameFields.last, !last.isEmpty { text += " · \(last)" }
        }
        return text
    }

    // MARK: RDAP

    private static func rdapJSON(_ url: String) -> [String: Any]? {
        guard let url = URL(string: url) else { return nil }
        var request = URLRequest(url: url)
        request.setValue("application/rdap+json, application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10
        let semaphore = DispatchSemaphore(value: 0)
        var json: [String: Any]?
        URLSession.shared.dataTask(with: request) { data, _, _ in
            if let data { json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] }
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 12)
        return json
    }

    private static func entities(_ json: [String: Any]) -> [(role: String, name: String)] {
        var out: [(role: String, name: String)] = []
        func walk(_ list: [[String: Any]]) {
            for entity in list {
                let roles = (entity["roles"] as? [String]) ?? []
                var name = (entity["handle"] as? String) ?? ""
                if let vcard = entity["vcardArray"] as? [Any], vcard.count > 1, let props = vcard[1] as? [[Any]] {
                    for prop in props where (prop.first as? String) == "fn" {
                        if let value = prop.last as? String, !value.isEmpty { name = value }
                    }
                }
                if !roles.isEmpty { out.append((roles.joined(separator: "/"), name)) }
                if let nested = entity["entities"] as? [[String: Any]] { walk(nested) }
            }
        }
        if let list = json["entities"] as? [[String: Any]] { walk(list) }
        return out
    }

    private static func events(_ json: [String: Any]) -> [(action: String, date: String)] {
        ((json["events"] as? [[String: Any]]) ?? []).compactMap { event in
            guard let action = event["eventAction"] as? String, let date = event["eventDate"] as? String else { return nil }
            return (action, date)
        }
    }

    static func rdapDomain(_ domain: String) -> [(label: String, value: String)] {
        guard let json = rdapJSON("https://rdap.org/domain/\(domain)") else { return [("RDAP", "no answer (unsupported TLD or rate limit)")] }
        var out: [(label: String, value: String)] = []
        if let name = json["ldhName"] as? String { out.append(("Domain", name)) }
        if let status = json["status"] as? [String] { out.append(("Status", status.joined(separator: ", "))) }
        for event in events(json) {
            switch event.action {
            case "registration": out.append(("Registered", event.date))
            case "expiration": out.append(("Expires", event.date))
            case "last changed": out.append(("Changed", event.date))
            default: break
            }
        }
        for entity in entities(json) where entity.role.contains("registrar") || entity.role.contains("registrant") || entity.role.contains("administrative") {
            out.append((entity.role.capitalized, entity.name))
        }
        if let servers = json["nameservers"] as? [[String: Any]] {
            let names = servers.compactMap { $0["ldhName"] as? String }
            if !names.isEmpty { out.append(("Name servers (registry)", names.joined(separator: ", "))) }
        }
        if let dnssec = json["secureDNS"] as? [String: Any], let signed = dnssec["delegationSigned"] as? Bool {
            out.append(("DNSSEC", signed ? "signed" : "not signed"))
        }
        return out
    }

    static func rdapIP(_ address: String) -> [(label: String, value: String)] {
        guard let json = rdapJSON("https://rdap.org/ip/\(address)") else { return [("RDAP", "no answer")] }
        var out: [(label: String, value: String)] = []
        if let name = json["name"] as? String { out.append(("Network", name)) }
        if let handle = json["handle"] as? String { out.append(("Handle", handle)) }
        if let start = json["startAddress"] as? String, let end = json["endAddress"] as? String { out.append(("Range", "\(start) – \(end)")) }
        if let cidr = json["cidr0_cidrs"] as? [[String: Any]] {
            let list = cidr.compactMap { entry -> String? in
                guard let length = entry["length"] as? Int else { return nil }
                let prefix = (entry["v4prefix"] as? String) ?? (entry["v6prefix"] as? String) ?? ""
                return "\(prefix)/\(length)"
            }
            if !list.isEmpty { out.append(("CIDR", list.joined(separator: ", "))) }
        }
        if let country = json["country"] as? String { out.append(("Country", country)) }
        if let type = json["type"] as? String { out.append(("Type", type)) }
        for entity in entities(json).prefix(6) { out.append((entity.role.capitalized, entity.name)) }
        for event in events(json) where event.action == "last changed" { out.append(("Changed", event.date)) }
        return out
    }

    static func markdown(_ result: DNSLookupResult) -> String {
        var out = "## DNS — \(result.query)\n\n_Checked \(result.checkedAt.formatted(date: .abbreviated, time: .shortened))_\n\n"
        out += ShellTool.markdownList(result.items) + "\n\n"
        for set in result.records {
            out += "**\(set.type)**\n\n" + set.values.map { "- `\($0)`" }.joined(separator: "\n") + "\n\n"
        }
        if !result.reverse.isEmpty { out += "**Reverse**\n\n" + result.reverse.map { "- \($0)" }.joined(separator: "\n") + "\n\n" }
        if !result.axfr.isEmpty { out += "**Zone transfer**\n\n" + result.axfr.map { "- \($0.server): \($0.outcome)" }.joined(separator: "\n") + "\n\n" }
        if !result.rdap.isEmpty { out += "**RDAP**\n\n" + result.rdap.map { "- \($0.label): \($0.value)" }.joined(separator: "\n") + "\n\n" }
        return out
    }
}

extension DNS {
    /// dig with any arguments; raw output.
    static func raw(_ arguments: [String]) -> String {
        ShellTool.run("/usr/bin/dig", arguments, timeout: 12)
    }

    /// `dig +short -t <type> <extra...>` — for `-x address`.
    static func dig(_ first: String, type: String, extra: [String]) -> [String] {
        raw(["+short", "+time=4", "+tries=1", "-t", type, first] + extra)
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix(";") }
    }
}

struct DNSLookupView: View {
    @Environment(TargetStore.self) private var targets
    @Environment(FindingsStore.self) private var findings
    @Environment(UIState.self) private var ui

    var body: some View {
        @Bindable var lookup = DNSLookup.shared
        VStack(spacing: 0) {
            CheckToolbar(text: $lookup.query, placeholder: "Domain or IP address (example.com, 203.0.113.10)", isRunning: lookup.isRunning, hasOptions: true, optionsHelp: "Zone transfer, RDAP", run: { lookup.run() }) {
                Toggle("Try a zone transfer (AXFR) on every name server", isOn: $lookup.tryZoneTransfer)
                Text("Read-only, but a request the client's DNS logs will show.").font(.caption).foregroundStyle(.secondary)
                Toggle("Ownership through RDAP (rdap.org)", isOn: $lookup.useRDAP)
            } trailing: {
                if let result = lookup.result {
                    CheckResultButtons(markdown: { DNSLookup.markdown(result) },
                                       findingTitle: result.axfr.contains { $0.transferred } ? "DNS zone transfer allowed for \(result.query)" : nil,
                                       createFinding: { createFinding(result) },
                                       addToTargets: result.addresses.isEmpty ? nil : { addToTargets(result) })
                }
            }
            Divider()
            if let error = lookup.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .padding()
            }
            if let result = lookup.result {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Text(result.query)
                                .font(.title2.weight(.semibold))
                            Text("\(result.records.reduce(0) { $0 + $1.values.count }) record(s) · \(result.problems.count) issue(s)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(result.items) { CheckItemRow(item: $0) }
                        if !result.records.isEmpty {
                            Text("Records")
                                .font(.subheadline.weight(.semibold))
                            ForEach(result.records) { set in
                                HStack(alignment: .top, spacing: 8) {
                                    Text(set.type)
                                        .font(.caption.weight(.semibold))
                                        .frame(width: 130, alignment: .leading)
                                    VStack(alignment: .leading, spacing: 2) {
                                        ForEach(Array(set.values.enumerated()), id: \.offset) { _, value in
                                            Text(value)
                                                .font(.system(.caption, design: .monospaced))
                                                .textSelection(.enabled)
                                                .contextMenu {
                                                    if DNSLookup.isIPAddress(value) || set.type == "NS" || set.type == "MX" || set.type == "CNAME" {
                                                        Button("Look up \(value)") {
                                                            lookup.query = set.type == "MX" ? String(value.split(separator: " ").last ?? "") : value
                                                            lookup.run()
                                                        }
                                                    }
                                                    Button("Copy") {
                                                        NSPasteboard.general.clearContents()
                                                        NSPasteboard.general.setString(value, forType: .string)
                                                    }
                                                }
                                        }
                                    }
                                }
                                .padding(6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                            }
                        }
                        if !result.reverse.isEmpty {
                            Text("Reverse")
                                .font(.subheadline.weight(.semibold))
                            ForEach(Array(result.reverse.enumerated()), id: \.offset) { _, line in
                                Text(line).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            }
                        }
                        if !result.axfr.isEmpty {
                            Text("Zone transfer")
                                .font(.subheadline.weight(.semibold))
                            ForEach(Array(result.axfr.enumerated()), id: \.offset) { _, attempt in
                                HStack(spacing: 6) {
                                    Image(systemName: attempt.transferred ? "xmark.octagon.fill" : "checkmark.circle")
                                        .foregroundStyle(attempt.transferred ? Color.red : Color.green)
                                    Text("\(attempt.server): \(attempt.outcome)")
                                        .font(.caption)
                                }
                            }
                        }
                        if !result.rdap.isEmpty {
                            Text("Ownership (RDAP)")
                                .font(.subheadline.weight(.semibold))
                            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
                                ForEach(Array(result.rdap.enumerated()), id: \.offset) { _, row in
                                    GridRow {
                                        Text(row.label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                        Text(row.value).font(.caption).textSelection(.enabled)
                                    }
                                }
                            }
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if lookup.error == nil {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "globe")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Enter a domain or an address: A/AAAA/CNAME/MX/NS/TXT/SOA/CAA and the common SRV records, reverse lookup, a zone-transfer attempt per name server, and who owns the domain or the address range (RDAP, ASN).")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Text("DNS goes through dig and your normal resolver; RDAP is one request to rdap.org; the ASN comes from Team Cymru's DNS service.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
        }
    }

    private func createFinding(_ result: DNSLookupResult) {
        var finding = Finding(title: "DNS zone transfer allowed for \(result.query)")
        finding.severity = .medium
        finding.description = "The name server(s) \(result.axfr.filter { $0.transferred }.map { $0.server }.joined(separator: ", ")) answer AXFR requests from any client, handing out the complete zone of \(result.query).\n\n" + result.axfr.map { "- \($0.server): \($0.outcome)" }.joined(separator: "\n")
        finding.impact = "The full list of host names and addresses — including internal and forgotten systems — is available to anyone, which greatly simplifies reconnaissance."
        finding.recommendation = "Restrict zone transfers to the secondary name servers (allow-transfer / TSIG) on every authoritative server, and review the zone for records that should not exist."
        finding.affected = result.axfr.filter { $0.transferred }.map { $0.server }
        finding.references = "https://cwe.mitre.org/data/definitions/200.html"
        finding.source = "DNS lookup"
        _ = findings.add(finding)
        ActivityLog.shared.record(.action, "Finding “\(finding.title)” created from the DNS lookup", source: "Tools")
    }

    private func addToTargets(_ result: DNSLookupResult) {
        var added = 0
        for address in result.addresses {
            let hostname = result.isAddress ? (result.reverse.first ?? "") : result.query
            let node = targets.addHost(address: address, hostname: hostname)
            if node.subtitle.isEmpty, !hostname.isEmpty { node.subtitle = hostname }
            added += 1
        }
        targets.scheduleSave()
        ui.flash("\(added) host(s) added to Targets.", seconds: 2)
    }
}
