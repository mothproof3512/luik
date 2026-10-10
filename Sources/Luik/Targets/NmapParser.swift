import Foundation

struct ParsedPort {
    var number: Int
    var proto: String       // tcp / udp / sctp
    var state: String       // open, filtered, open|filtered, closed, ...
    var service: String
    var version: String
    var scripts: [String]   // NSE script output (lines)

    var key: String { "\(number)/\(proto)" }
}

struct ParsedHost {
    var address: String
    var hostname: String = ""
    var os: String = ""
    var mac: String = ""
    var ports: [ParsedPort] = []
    var extra: [String] = []   // other host info (host scripts, OS details, ...)
}

/// Reads nmap output in three formats: normal (screen output / -oN), grepable (-oG) and XML (-oX).
/// Multiple hosts in one output are all returned.
enum NmapParser {
    static func parse(_ text: String) -> [ParsedHost] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var hosts: [ParsedHost] = []
        if trimmed.contains("<nmaprun") {
            // Several XML files pasted together: parse each piece separately.
            // Piece 0 is whatever precedes the first "<?xml" (empty if the text starts with it).
            let chunks = trimmed.components(separatedBy: "<?xml")
            for (index, chunk) in chunks.enumerated() {
                let piece = index == 0 ? chunk : "<?xml" + chunk
                if piece.contains("<nmaprun") {
                    hosts.append(contentsOf: parseXML(piece))
                } else if piece.contains("Nmap scan report") {
                    hosts.append(contentsOf: parseNormal(piece))
                }
            }
        } else if isGrepable(trimmed) {
            hosts = parseGrepable(trimmed)
        } else {
            hosts = parseNormal(trimmed)
        }
        return merge(hosts)
    }

    /// Merges hosts with the same address (e.g. from several scans pasted at once).
    private static func merge(_ hosts: [ParsedHost]) -> [ParsedHost] {
        var result: [ParsedHost] = []
        for host in hosts {
            if let index = result.firstIndex(where: { $0.address == host.address }) {
                var existing = result[index]
                if existing.hostname.isEmpty { existing.hostname = host.hostname }
                if existing.os.isEmpty { existing.os = host.os }
                if existing.mac.isEmpty { existing.mac = host.mac }
                let newExtra = host.extra.filter { !existing.extra.contains($0) }
                existing.extra.append(contentsOf: newExtra)
                for port in host.ports {
                    if let portIndex = existing.ports.firstIndex(where: { $0.key == port.key }) {
                        var existingPort = existing.ports[portIndex]
                        if !port.service.isEmpty { existingPort.service = port.service }
                        if !port.version.isEmpty { existingPort.version = port.version }
                        if port.state == "open" { existingPort.state = "open" }
                        let newScripts = port.scripts.filter { !existingPort.scripts.contains($0) }
                        existingPort.scripts.append(contentsOf: newScripts)
                        existing.ports[portIndex] = existingPort
                    } else {
                        existing.ports.append(port)
                    }
                }
                result[index] = existing
            } else {
                result.append(host)
            }
        }
        return result
    }

    // MARK: - Regex helpers

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // The patterns are constants; a mistake in them is a programming error.
        return try! NSRegularExpression(pattern: pattern, options: [])
    }

    /// Returns the capture groups (index 0 = whole match), or nil if the pattern does not match.
    private static func match(_ regex: NSRegularExpression, _ line: String) -> [String]? {
        let nsLine = line as NSString
        guard let result = regex.firstMatch(in: line, options: [], range: NSRange(location: 0, length: nsLine.length)) else {
            return nil
        }
        return (0..<result.numberOfRanges).map { index in
            let range = result.range(at: index)
            return range.location == NSNotFound ? "" : nsLine.substring(with: range)
        }
    }

    // MARK: - Normal output

    private static let hostLineRegex = regex(#"^Nmap scan report for (\S+)(?: \(([^)]+)\))?"#)
    private static let portLineRegex = regex(#"^(\d+)/(tcp|udp|sctp)\s+(\S+)\s+(\S+)(?:\s+(.*))?$"#)

    static func parseNormal(_ text: String) -> [ParsedHost] {
        var hosts: [ParsedHost] = []
        var current: ParsedHost?
        var currentPortIndex: Int?

        func flush() {
            if let host = current {
                hosts.append(host)
            }
            current = nil
            currentPortIndex = nil
        }

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if let groups = match(hostLineRegex, line) {
                flush()
                if line.contains("[host down]") { continue }
                let first = groups[1]
                let second = groups[2]
                if second.isEmpty {
                    current = ParsedHost(address: first)
                } else {
                    current = ParsedHost(address: second, hostname: first)
                }
                continue
            }

            guard current != nil else { continue }

            if let groups = match(portLineRegex, line) {
                let port = ParsedPort(number: Int(groups[1]) ?? 0,
                                      proto: groups[2],
                                      state: groups[3],
                                      service: groups[4],
                                      version: groups[5].trimmingCharacters(in: .whitespaces),
                                      scripts: [])
                current?.ports.append(port)
                currentPortIndex = (current?.ports.count ?? 1) - 1
                continue
            }

            if line.hasPrefix("|") {
                // NSE script output: "| ssh-hostkey:" / "|_http-title: ..."
                let cleaned = line.replacingOccurrences(of: #"^\|_?\s?"#, with: "", options: .regularExpression)
                if let index = currentPortIndex {
                    current?.ports[index].scripts.append(cleaned)
                } else {
                    current?.extra.append(cleaned)
                }
                continue
            }

            if line.hasPrefix("Host script results") {
                currentPortIndex = nil
                continue
            }
            if line.hasPrefix("MAC Address:") {
                current?.mac = String(line.dropFirst("MAC Address:".count)).trimmingCharacters(in: .whitespaces)
                continue
            }
            if line.hasPrefix("OS details:") || line.hasPrefix("Running:") || line.hasPrefix("Aggressive OS guesses:") {
                if current?.os.isEmpty == true {
                    current?.os = line
                } else {
                    current?.extra.append(line)
                }
                continue
            }
            if line.hasPrefix("Service Info:") || line.hasPrefix("Device type:") || line.hasPrefix("Network Distance:") {
                current?.extra.append(line)
                continue
            }
        }
        flush()
        return hosts
    }

    // MARK: - Grepable output (-oG)

    private static let grepHostRegex = regex(#"^Host: (\S+)(?: \(([^)]*)\))?"#)
    /// Separator regex for grepable fields when pasting turned the tabs into spaces.
    private static let grepFieldSeparatorRegex = regex(#"\s+(?=(?:Ports|Status|OS|Ignored State|Seq Index|IP ID Seq|TCP Sequence|OS ID Seq): )"#)

    static func isGrepable(_ text: String) -> Bool {
        text.contains("Host: ")
            && (text.contains("Ports: ") || text.contains("Status: "))
            && !text.contains("Nmap scan report for")
    }

    private static func grepableFields(_ line: String) -> [String] {
        if line.contains("\t") {
            return line.components(separatedBy: "\t")
        }
        let nsLine = line as NSString
        var fields: [String] = []
        var start = 0
        for result in grepFieldSeparatorRegex.matches(in: line, options: [], range: NSRange(location: 0, length: nsLine.length)) {
            fields.append(nsLine.substring(with: NSRange(location: start, length: result.range.location - start)))
            start = result.range.location + result.range.length
        }
        fields.append(nsLine.substring(from: start))
        return fields
    }

    static func parseGrepable(_ text: String) -> [ParsedHost] {
        var hosts: [ParsedHost] = []

        for rawLine in text.components(separatedBy: .newlines) {
            guard rawLine.hasPrefix("Host:") else { continue }
            let fields = grepableFields(rawLine)
            guard let first = fields.first, let groups = match(grepHostRegex, first) else { continue }

            let address = groups[1]
            let hostname = groups[2]
            let hostIndex: Int
            if let index = hosts.firstIndex(where: { $0.address == address }) {
                hostIndex = index
            } else {
                hosts.append(ParsedHost(address: address, hostname: hostname))
                hostIndex = hosts.count - 1
            }
            if hosts[hostIndex].hostname.isEmpty && !hostname.isEmpty {
                hosts[hostIndex].hostname = hostname
            }

            for field in fields.dropFirst() {
                if field.hasPrefix("Ports:") {
                    let list = field.dropFirst("Ports:".count).trimmingCharacters(in: .whitespaces)
                    for entry in list.components(separatedBy: ", ") {
                        // port/state/protocol/owner/service/rpc/version/
                        let parts = entry.components(separatedBy: "/")
                        guard parts.count >= 5, let number = Int(parts[0].trimmingCharacters(in: .whitespaces)) else { continue }
                        let version = parts.count > 6 ? parts[6].replacingOccurrences(of: "|", with: "/") : ""
                        hosts[hostIndex].ports.append(ParsedPort(number: number,
                                                                 proto: parts[2],
                                                                 state: parts[1],
                                                                 service: parts[4],
                                                                 version: version,
                                                                 scripts: []))
                    }
                } else if field.hasPrefix("OS:") {
                    hosts[hostIndex].os = field.dropFirst("OS:".count).trimmingCharacters(in: .whitespaces)
                }
            }
        }
        return hosts
    }

    // MARK: - XML output (-oX)

    static func parseXML(_ text: String) -> [ParsedHost] {
        guard let data = text.data(using: .utf8) else { return [] }
        let parser = XMLParser(data: data)
        let delegate = NmapXMLDelegate()
        parser.delegate = delegate
        parser.parse()
        return delegate.hosts
    }
}

private final class NmapXMLDelegate: NSObject, XMLParserDelegate {
    var hosts: [ParsedHost] = []
    private var host: ParsedHost?
    private var port: ParsedPort?

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch elementName {
        case "host":
            host = ParsedHost(address: "")
        case "address":
            let type = attributeDict["addrtype"] ?? ""
            let addr = attributeDict["addr"] ?? ""
            if type == "ipv4" {
                host?.address = addr
            } else if type == "ipv6" {
                if host?.address.isEmpty == true { host?.address = addr }
            } else if type == "mac" {
                let vendor = attributeDict["vendor"].map { " (\($0))" } ?? ""
                host?.mac = addr + vendor
            }
        case "hostname":
            if host?.hostname.isEmpty == true {
                host?.hostname = attributeDict["name"] ?? ""
            }
        case "port":
            port = ParsedPort(number: Int(attributeDict["portid"] ?? "") ?? 0,
                              proto: attributeDict["protocol"] ?? "tcp",
                              state: "",
                              service: "",
                              version: "",
                              scripts: [])
        case "state":
            if port != nil {
                port?.state = attributeDict["state"] ?? ""
            }
        case "service":
            if port != nil {
                port?.service = attributeDict["name"] ?? ""
                let parts = [attributeDict["product"], attributeDict["version"], attributeDict["extrainfo"]]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty }
                port?.version = parts.joined(separator: " ")
            }
        case "script":
            let id = attributeDict["id"] ?? "script"
            let output = (attributeDict["output"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let line = output.isEmpty ? id : "\(id): \(output)"
            if port != nil {
                port?.scripts.append(line)
            } else {
                host?.extra.append(line)
            }
        case "osmatch":
            if host?.os.isEmpty == true, let name = attributeDict["name"] {
                let accuracy = attributeDict["accuracy"].map { " (\($0)%)" } ?? ""
                host?.os = "OS: " + name + accuracy
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "port":
            if let finished = port {
                host?.ports.append(finished)
            }
            port = nil
        case "host":
            if let finished = host, !finished.address.isEmpty {
                hosts.append(finished)
            }
            host = nil
        default:
            break
        }
    }
}
