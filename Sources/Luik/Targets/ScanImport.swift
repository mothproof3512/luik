import Foundation

/// Which scanner output the import sheet is looking at.
enum ScanFormat: String {
    case nmap
    case nessus
    case nuclei
    case masscanList
    case masscanJSON

    var label: String {
        switch self {
        case .nmap: return "nmap (normal / -oG / -oX; masscan -oG)"
        case .nessus: return "Nessus (.nessus)"
        case .nuclei: return "nuclei (JSON / JSONL)"
        case .masscanList: return "masscan (-oL)"
        case .masscanJSON: return "masscan (-oJ)"
        }
    }

    /// Scanners that report vulnerabilities, not just ports.
    var hasFindings: Bool { self == .nessus || self == .nuclei }
}

/// A vulnerability-ish item a scanner reported for a host/port.
struct ScanFinding {
    var scanner: String            // "Nessus", "nuclei"
    var sourceID: String           // stable key for merging: "Nessus 57608", "nuclei http-missing-security-headers"
    var address: String
    var hostname = ""
    var port = 0
    var proto = "tcp"
    var severity: Severity = .info
    var title: String
    var synopsis = ""
    var description = ""
    var solution = ""
    var output = ""
    var references: [String] = []
    var cves: [String] = []
    var cvssVector = ""
    var cvssScore = ""
    var matchedAt = ""

    var affectedLabel: String {
        port > 0 ? "\(address):\(port)/\(proto)" : address
    }

    /// Notes for the node under the port (everything the scanner said, compact).
    var notesText: String {
        var lines: [String] = ["Severity: \(severity.label)" + (cvssScore.isEmpty ? "" : " · CVSS \(cvssScore)") + (cvssVector.isEmpty ? "" : " · \(cvssVector)")]
        if !matchedAt.isEmpty { lines.append("Matched at: \(matchedAt)") }
        if !synopsis.isEmpty { lines.append("\n" + synopsis) }
        if !description.isEmpty { lines.append("\n" + description) }
        if !solution.isEmpty { lines.append("\nSolution: " + solution) }
        if !output.isEmpty { lines.append("\nOutput:\n" + output) }
        if !cves.isEmpty { lines.append("\nCVE: " + cves.joined(separator: ", ")) }
        if !references.isEmpty { lines.append("\nReferences:\n" + references.joined(separator: "\n")) }
        return lines.joined(separator: "\n")
    }
}

struct ScanParseResult {
    var format: ScanFormat
    var hosts: [ParsedHost] = []
    var findings: [ScanFinding] = []
}

/// Detects and parses nmap, Nessus, nuclei and masscan output into hosts/ports (+ scanner findings).
enum ScanImport {
    static func detect(_ text: String) -> ScanFormat {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("<NessusClientData") { return .nessus }
        if trimmed.contains("<nmaprun") || trimmed.contains("Nmap scan report") || NmapParser.isGrepable(trimmed) { return .nmap }
        if trimmed.contains("\"template-id\"") || trimmed.contains("\"templateID\"") || trimmed.contains("\"matched-at\"") { return .nuclei }
        if (trimmed.hasPrefix("[") || trimmed.hasPrefix("{")) && trimmed.contains("\"ports\"") && trimmed.contains("\"ip\"") { return .masscanJSON }
        if masscanListLine.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil { return .masscanList }
        return .nmap
    }

    static func parse(_ text: String) -> ScanParseResult {
        let format = detect(text)
        switch format {
        case .nmap: return ScanParseResult(format: .nmap, hosts: NmapParser.parse(text))
        case .nessus: return parseNessus(text)
        case .nuclei: return parseNuclei(text)
        case .masscanList: return ScanParseResult(format: .masscanList, hosts: parseMasscanList(text))
        case .masscanJSON: return ScanParseResult(format: .masscanJSON, hosts: parseMasscanJSON(text))
        }
    }

    // MARK: - Nessus

    static func parseNessus(_ text: String) -> ScanParseResult {
        guard let data = text.data(using: .utf8) else { return ScanParseResult(format: .nessus) }
        let parser = XMLParser(data: data)
        let delegate = NessusDelegate()
        parser.delegate = delegate
        parser.parse()
        return ScanParseResult(format: .nessus, hosts: delegate.hosts, findings: delegate.findings)
    }

    /// Nessus service names → nmap-style names used by the service templates.
    static func normalizeService(_ name: String) -> String {
        switch name.lowercased() {
        case "www", "http?", "http_proxy": return "http"
        case "cifs": return "smb"
        case "msrdp": return "rdp"
        case "epmap", "dce-rpc", "dcerpc": return "msrpc"
        case "rpc-portmapper", "sunrpc": return "rpcbind"
        case "general", "unknown", "?": return ""
        default: return name.lowercased()
        }
    }

    // MARK: - nuclei

    static func parseNuclei(_ text: String) -> ScanParseResult {
        var objects: [[String: Any]] = []
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("["), let data = trimmed.data(using: .utf8),
           let array = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] {
            objects = array
        } else {
            for line in trimmed.components(separatedBy: .newlines) {
                let piece = line.trimmingCharacters(in: .whitespaces)
                guard piece.hasPrefix("{"), let data = piece.data(using: .utf8),
                      let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { continue }
                objects.append(object)
            }
        }

        var result = ScanParseResult(format: .nuclei)
        for object in objects {
            let templateID = (object["template-id"] as? String) ?? (object["templateID"] as? String) ?? "unknown"
            let info = object["info"] as? [String: Any] ?? [:]
            let name = (info["name"] as? String) ?? templateID
            let severity = Severity.parse((info["severity"] as? String) ?? "") ?? .info
            let hostField = (object["host"] as? String) ?? ""
            let matchedAt = (object["matched-at"] as? String) ?? (object["matched"] as? String) ?? hostField
            let ip = (object["ip"] as? String) ?? ""
            let (hostName, urlPort) = hostAndPort(from: hostField.isEmpty ? matchedAt : hostField)
            let address = ip.isEmpty ? hostName : ip
            guard !address.isEmpty else { continue }
            var port = Int((object["port"] as? String) ?? "") ?? (object["port"] as? Int) ?? urlPort
            if port == 0, let type = object["type"] as? String, type == "dns" { port = 53 }

            var finding = ScanFinding(scanner: "nuclei", sourceID: "nuclei \(templateID)", address: address, title: name)
            finding.hostname = ip.isEmpty ? "" : hostName
            finding.port = port
            finding.proto = (object["type"] as? String) == "dns" ? "udp" : "tcp"
            finding.severity = severity
            finding.description = (info["description"] as? String) ?? ""
            finding.matchedAt = matchedAt
            if let refs = info["reference"] as? [String] { finding.references = refs }
            else if let ref = info["reference"] as? String, !ref.isEmpty { finding.references = [ref] }
            if let classification = info["classification"] as? [String: Any] {
                if let vector = classification["cvss-metrics"] as? String { finding.cvssVector = vector }
                if let score = classification["cvss-score"] as? Double { finding.cvssScore = String(format: "%.1f", score) }
                if let cves = classification["cve-id"] as? [String] { finding.cves = cves.map { $0.uppercased() } }
                else if let cve = classification["cve-id"] as? String, !cve.isEmpty { finding.cves = [cve.uppercased()] }
            }
            var outputParts: [String] = []
            if let matcher = object["matcher-name"] as? String, !matcher.isEmpty { outputParts.append("matcher: \(matcher)") }
            if let extracted = object["extracted-results"] as? [String], !extracted.isEmpty { outputParts.append("extracted: " + extracted.joined(separator: ", ")) }
            if let curl = object["curl-command"] as? String, !curl.isEmpty { outputParts.append(curl) }
            finding.output = outputParts.joined(separator: "\n")
            result.findings.append(finding)

            if let index = result.hosts.firstIndex(where: { $0.address == address }) {
                if port > 0, !result.hosts[index].ports.contains(where: { $0.number == port && $0.proto == finding.proto }) {
                    result.hosts[index].ports.append(ParsedPort(number: port, proto: finding.proto, state: "open", service: serviceGuess(for: hostField, port: port), version: "", scripts: []))
                }
            } else {
                var host = ParsedHost(address: address, hostname: ip.isEmpty ? "" : hostName)
                if port > 0 {
                    host.ports.append(ParsedPort(number: port, proto: finding.proto, state: "open", service: serviceGuess(for: hostField, port: port), version: "", scripts: []))
                }
                result.hosts.append(host)
            }
        }
        return result
    }

    /// "https://app.example.com:8443/path" → ("app.example.com", 8443); "10.0.0.5:22" → ("10.0.0.5", 22).
    static func hostAndPort(from text: String) -> (String, Int) {
        var value = text.trimmingCharacters(in: .whitespaces)
        var defaultPort = 0
        if let range = value.range(of: "://") {
            let scheme = value[..<range.lowerBound].lowercased()
            defaultPort = scheme == "https" ? 443 : (scheme == "http" ? 80 : (scheme == "ftp" ? 21 : (scheme == "ssh" ? 22 : 0)))
            value = String(value[range.upperBound...])
        }
        if let slash = value.firstIndex(of: "/") { value = String(value[..<slash]) }
        if let at = value.lastIndex(of: "@") { value = String(value[value.index(after: at)...]) }
        if value.hasPrefix("[") {
            // [IPv6]:port
            if let close = value.firstIndex(of: "]") {
                let host = String(value[value.index(after: value.startIndex)..<close])
                let rest = value[value.index(after: close)...]
                let port = rest.hasPrefix(":") ? Int(rest.dropFirst()) ?? defaultPort : defaultPort
                return (host, port)
            }
        }
        let parts = value.split(separator: ":")
        if parts.count == 2, let port = Int(parts[1]) {
            return (String(parts[0]), port)
        }
        return (value, defaultPort)
    }

    private static func serviceGuess(for hostField: String, port: Int) -> String {
        let lower = hostField.lowercased()
        if lower.hasPrefix("https://") { return "https" }
        if lower.hasPrefix("http://") { return "http" }
        switch port {
        case 80, 8080, 8000, 8888: return "http"
        case 443, 8443: return "https"
        case 22: return "ssh"
        case 21: return "ftp"
        case 53: return "dns"
        case 445: return "smb"
        case 3389: return "rdp"
        default: return ""
        }
    }

    // MARK: - masscan

    private static let masscanListLine = try! NSRegularExpression(pattern: #"(?m)^(open|closed|banner)[ \t]+(tcp|udp|sctp|icmp)[ \t]+(\d+)[ \t]+(\S+)(?:[ \t]+(\d+))?(?:[ \t]+(.*))?$"#)

    /// -oL: "open tcp 80 10.0.0.1 1700000000" (and "banner tcp 80 10.0.0.1 ts service text").
    static func parseMasscanList(_ text: String) -> [ParsedHost] {
        var hosts: [ParsedHost] = []
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let m = masscanListLine.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) else { continue }
            func group(_ i: Int) -> String {
                guard let r = Range(m.range(at: i), in: trimmed) else { return "" }
                return String(trimmed[r])
            }
            let kind = group(1), proto = group(2), address = group(4)
            guard let port = Int(group(3)) else { continue }
            let hostIndex: Int
            if let index = hosts.firstIndex(where: { $0.address == address }) {
                hostIndex = index
            } else {
                hosts.append(ParsedHost(address: address))
                hostIndex = hosts.count - 1
            }
            if let portIndex = hosts[hostIndex].ports.firstIndex(where: { $0.number == port && $0.proto == proto }) {
                if kind == "banner" {
                    let banner = group(6).trimmingCharacters(in: .whitespaces)
                    if !banner.isEmpty {
                        var p = hosts[hostIndex].ports[portIndex]
                        if p.version.isEmpty { p.version = banner } else { p.scripts.append(banner) }
                        hosts[hostIndex].ports[portIndex] = p
                    }
                }
            } else {
                let banner = kind == "banner" ? group(6).trimmingCharacters(in: .whitespaces) : ""
                hosts[hostIndex].ports.append(ParsedPort(number: port, proto: proto, state: kind == "closed" ? "closed" : "open",
                                                         service: "", version: banner, scripts: []))
            }
        }
        return hosts
    }

    /// -oJ: a JSON array of {"ip", "timestamp", "ports": [{"port", "proto", "status", …}]} objects.
    /// masscan's JSON is not always valid (trailing comma, "finished" record), so there is a line-based fallback.
    static func parseMasscanJSON(_ text: String) -> [ParsedHost] {
        var hosts: [ParsedHost] = []
        func add(address: String, port: Int, proto: String, status: String, service: String, banner: String) {
            let hostIndex: Int
            if let index = hosts.firstIndex(where: { $0.address == address }) {
                hostIndex = index
            } else {
                hosts.append(ParsedHost(address: address))
                hostIndex = hosts.count - 1
            }
            if let portIndex = hosts[hostIndex].ports.firstIndex(where: { $0.number == port && $0.proto == proto }) {
                if !banner.isEmpty, hosts[hostIndex].ports[portIndex].version.isEmpty { hosts[hostIndex].ports[portIndex].version = banner }
                if !service.isEmpty, hosts[hostIndex].ports[portIndex].service.isEmpty { hosts[hostIndex].ports[portIndex].service = service }
            } else {
                hosts[hostIndex].ports.append(ParsedPort(number: port, proto: proto, state: status, service: service, version: banner, scripts: []))
            }
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8), let array = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] {
            for object in array {
                guard let address = object["ip"] as? String, let ports = object["ports"] as? [[String: Any]] else { continue }
                for entry in ports {
                    guard let port = entry["port"] as? Int else { continue }
                    let service = entry["service"] as? [String: Any]
                    add(address: address, port: port, proto: (entry["proto"] as? String) ?? "tcp",
                        status: (entry["status"] as? String) ?? "open",
                        service: (service?["name"] as? String) ?? "", banner: (service?["banner"] as? String) ?? "")
                }
            }
            return hosts
        }

        // Fallback: one host object per line.
        let ipRegex = try! NSRegularExpression(pattern: #""ip"\s*:\s*"([^"]+)""#)
        let portRegex = try! NSRegularExpression(pattern: #""port"\s*:\s*(\d+)\s*,\s*"proto"\s*:\s*"(\w+)"\s*,\s*"status"\s*:\s*"(\w+)""#)
        for line in trimmed.components(separatedBy: .newlines) {
            let range = NSRange(line.startIndex..., in: line)
            guard let ipMatch = ipRegex.firstMatch(in: line, range: range), let ipRange = Range(ipMatch.range(at: 1), in: line) else { continue }
            let address = String(line[ipRange])
            for m in portRegex.matches(in: line, range: range) {
                guard let p = Range(m.range(at: 1), in: line), let port = Int(line[p]),
                      let pr = Range(m.range(at: 2), in: line), let st = Range(m.range(at: 3), in: line) else { continue }
                add(address: address, port: port, proto: String(line[pr]), status: String(line[st]), service: "", banner: "")
            }
        }
        return hosts
    }
}

/// XML delegate for .nessus files (NessusClientData_v2).
private final class NessusDelegate: NSObject, XMLParserDelegate {
    var hosts: [ParsedHost] = []
    var findings: [ScanFinding] = []

    private var host: ParsedHost?
    private var hostFindings: [ScanFinding] = []
    private var item: ScanFinding?
    private var itemPort = 0
    private var itemProto = "tcp"
    private var itemService = ""
    private var text = ""
    private var tagName = ""
    private var inHostProperties = false

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        text = ""
        switch elementName {
        case "ReportHost":
            host = ParsedHost(address: attributeDict["name"] ?? "")
            hostFindings = []
        case "HostProperties":
            inHostProperties = true
        case "tag":
            tagName = attributeDict["name"] ?? ""
        case "ReportItem":
            itemPort = Int(attributeDict["port"] ?? "") ?? 0
            itemProto = attributeDict["protocol"] ?? "tcp"
            itemService = ScanImport.normalizeService(attributeDict["svc_name"] ?? "")
            let pluginID = attributeDict["pluginID"] ?? ""
            var finding = ScanFinding(scanner: "Nessus", sourceID: "Nessus \(pluginID)", address: host?.address ?? "",
                                      title: attributeDict["pluginName"] ?? "Plugin \(pluginID)")
            finding.hostname = host?.hostname ?? ""
            finding.port = itemPort
            finding.proto = itemProto
            finding.severity = Severity.parse(attributeDict["severity"] ?? "0") ?? .info
            item = finding
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "tag" where inHostProperties:
            switch tagName {
            case "host-ip":
                if !value.isEmpty { host?.address = value }
            case "host-fqdn", "hostname":
                if host?.hostname.isEmpty == true { host?.hostname = value }
            case "netbios-name":
                if host?.hostname.isEmpty == true { host?.hostname = value }
                else { host?.extra.append("NetBIOS: \(value)") }
            case "operating-system":
                if host?.os.isEmpty == true { host?.os = "OS: \(value)" }
            case "mac-address":
                host?.mac = value
            default:
                break
            }
        case "HostProperties":
            inHostProperties = false
        case "synopsis": item?.synopsis = value
        case "description": item?.description = value
        case "solution": item?.solution = value
        case "plugin_output": item?.output = String(value.prefix(4000))
        case "cvss3_vector": item?.cvssVector = value
        case "cvss3_base_score": item?.cvssScore = value
        case "cvss_base_score": if item?.cvssScore.isEmpty == true { item?.cvssScore = value }
        case "cve": if !value.isEmpty { item?.cves.append(value) }
        case "see_also":
            item?.references.append(contentsOf: value.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
        case "risk_factor":
            if let parsed = Severity.parse(value), item?.severity == .info, parsed != .info { item?.severity = parsed }
        case "ReportItem":
            if let finished = item { finishItem(finished) }
            item = nil
        case "ReportHost":
            if let finished = host, !finished.address.isEmpty {
                hosts.append(finished)
                findings.append(contentsOf: hostFindings.map { f in
                    var copy = f
                    copy.address = finished.address
                    copy.hostname = finished.hostname
                    return copy
                })
            }
            host = nil
            hostFindings = []
        default:
            break
        }
    }

    private func finishItem(_ finding: ScanFinding) {
        guard host != nil else { return }
        if itemPort > 0 {
            if let index = host!.ports.firstIndex(where: { $0.number == itemPort && $0.proto == itemProto }) {
                if host!.ports[index].service.isEmpty { host!.ports[index].service = itemService }
                if host!.ports[index].version.isEmpty, let version = NessusDelegate.versionHint(from: finding) {
                    host!.ports[index].version = version
                }
            } else {
                let version = NessusDelegate.versionHint(from: finding) ?? ""
                host!.ports.append(ParsedPort(number: itemPort, proto: itemProto, state: "open", service: itemService, version: version, scripts: []))
            }
        } else if finding.severity == .info, finding.title.localizedCaseInsensitiveContains("OS Identification"),
                  host!.os.isEmpty, let line = finding.output.components(separatedBy: .newlines).first(where: { $0.contains("Remote operating system") }) {
            host!.os = "OS: " + line.replacingOccurrences(of: "Remote operating system :", with: "").trimmingCharacters(in: .whitespaces)
        }
        if finding.severity != .info || finding.cvssScore.isEmpty == false {
            hostFindings.append(finding)
        } else if finding.title.localizedCaseInsensitiveContains("Detection") == false,
                  finding.title.localizedCaseInsensitiveContains("Version") == false,
                  finding.title.localizedCaseInsensitiveContains("Information") == false {
            // Plain informational plugins are still useful as nodes when the user asks for "Info" too.
            hostFindings.append(finding)
        }
    }

    /// Picks a service version line from version-detection plugins ("Apache/2.4.41 (Ubuntu)").
    static func versionHint(from finding: ScanFinding) -> String? {
        let title = finding.title.lowercased()
        guard title.contains("version") || title.contains("server type") || title.contains("banner") else { return nil }
        let lines = finding.output.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasSuffix(":") && !$0.lowercased().hasPrefix("the remote") && !$0.lowercased().hasPrefix("nessus") }
        guard let first = lines.first else { return nil }
        let cleaned = first.replacingOccurrences(of: #"^(SSH version|Server|Version|Banner)\s*:\s*"#, with: "", options: .regularExpression)
        return cleaned.count > 100 ? String(cleaned.prefix(100)) : cleaned
    }
}
