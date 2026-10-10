import AppKit
import Foundation
import Observation

struct Snippet: Identifiable, Codable, Equatable, Hashable {
    var id = UUID()
    var title: String
    var command: String
    var category: String
    /// Where the one-liner is offered in Targets: service names / port numbers ("http", "445") show
    /// it under matching ports, "port" under every port, "host" under every host. Empty = only in
    /// the One-liners tab.
    var services: [String] = []

    init(id: UUID = UUID(), title: String, command: String, category: String, services: [String] = []) {
        self.id = id
        self.title = title
        self.command = command
        self.category = category
        self.services = services
    }

    private enum CodingKeys: String, CodingKey { case id, title, command, category, services }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        command = try c.decodeIfPresent(String.self, forKey: .command) ?? ""
        category = try c.decodeIfPresent(String.self, forKey: .category) ?? "General"
        services = try c.decodeIfPresent([String].self, forKey: .services) ?? []
    }

    var servicesText: String { services.joined(separator: ", ") }

    static func parseServices(_ text: String) -> [String] {
        text.split(whereSeparator: { $0 == "," || $0 == ";" || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
    }

    /// Offered under a port with this service name / number?
    func applies(toService service: String, port: Int) -> Bool {
        guard !services.isEmpty else { return false }
        if services.contains("port") { return true }
        let name = service.lowercased().trimmingCharacters(in: .whitespaces)
        if !name.isEmpty {
            let short = name.split(separator: "/").last.map(String.init) ?? name
            if services.contains(name) || services.contains(short) { return true }
        }
        return port > 0 && services.contains(String(port))
    }

    var appliesToHosts: Bool { services.contains("host") }
}

/// One-liners are stored in snippets.json in the Luik data folder.
/// `$RHOST` (or `${RHOST}`) in a command is replaced by the target you entered;
/// the older forms `<ip>`, `<target>` and `$TARGET` keep working too.
@Observable
final class SnippetStore {
    static let shared = SnippetStore()

    private static let fileName = "snippets.json"
    /// Name of the shell variable that serves as the placeholder.
    static let variableName = "RHOST"

    var snippets: [Snippet] = []
    var search: String = ""
    var target: String = ""     // $RHOST
    var lhost: String = ""      // $LHOST — your own (VPN) address
    var lport: String = ""      // $LPORT
    var rport: String = ""      // $RPORT (in Targets the selected port is used instead)
    @ObservationIgnored private var saver = Debouncer()

    init() {
        snippets = Storage.load([Snippet].self, from: SnippetStore.fileName) ?? SnippetStore.defaultSnippets
        let defaults = UserDefaults.standard
        target = defaults.string(forKey: SettingsKey.snippetTarget) ?? ""
        lhost = defaults.string(forKey: SettingsKey.snippetLHost) ?? ""
        lport = defaults.string(forKey: SettingsKey.snippetLPort) ?? ""
        rport = defaults.string(forKey: SettingsKey.snippetRPort) ?? ""
        if lhost.isEmpty, let suggested = LocalAddress.suggested() {
            lhost = suggested.address
        }
        migrateIfNeeded()
        migrateServiceTagsIfNeeded()
    }

    /// Fills $LHOST with the detected VPN/tunnel address (or the first interface).
    func detectLHost() {
        if let suggested = LocalAddress.suggested() {
            lhost = suggested.address
            saveTarget()
        }
    }

    /// One-time migrations of stored snippets: `<ip>` → `$RHOST` (0.7) and the Dutch default
    /// titles/categories of versions up to 0.7 → English (0.8).
    private func migrateIfNeeded() {
        var changed = false
        for index in snippets.indices {
            if snippets[index].command.contains("<ip>") {
                snippets[index].command = snippets[index].command.replacingOccurrences(of: "<ip>", with: "$RHOST")
                changed = true
            }
            if let title = SnippetStore.legacyTitles[snippets[index].title] {
                snippets[index].title = title
                changed = true
            }
            if let category = SnippetStore.legacyCategories[snippets[index].category] {
                snippets[index].category = category
                changed = true
            }
        }
        if changed {
            scheduleSave()
        }
    }

    /// One-liners offered under a port node.
    func snippets(forService service: String, port: Int) -> [Snippet] {
        snippets.filter { $0.applies(toService: service, port: port) }
    }

    /// One-liners offered under a host node.
    var hostSnippets: [Snippet] {
        snippets.filter { $0.appliesToHosts }
    }

    /// Default tags for one-liners that pre-date the tags (0.16): copied from the default list by
    /// title, otherwise guessed from the "Service:" prefix of the title or the category.
    private func migrateServiceTagsIfNeeded() {
        let flag = "snippetServiceTagsMigrated_v16"
        guard !UserDefaults.standard.bool(forKey: flag) else { return }
        UserDefaults.standard.set(true, forKey: flag)
        var changed = false
        for index in snippets.indices {
            // A default one-liner that was never edited gets the new command ($RPORT / $RURL).
            if let legacy = SnippetStore.legacyCommands[snippets[index].title], snippets[index].command == legacy,
               let current = SnippetStore.defaultSnippets.first(where: { $0.title == snippets[index].title }) {
                snippets[index].command = current.command
                changed = true
            }
        }
        for index in snippets.indices where snippets[index].services.isEmpty {
            let snippet = snippets[index]
            if let match = SnippetStore.defaultSnippets.first(where: { $0.title == snippet.title }), !match.services.isEmpty {
                snippets[index].services = match.services
                changed = true
            } else if let guessed = SnippetStore.guessServices(title: snippet.title, category: snippet.category), !guessed.isEmpty {
                snippets[index].services = guessed
                changed = true
            }
        }
        if changed { scheduleSave() }
    }

    /// Commands of the defaults up to 0.15, by title (used once to upgrade untouched copies).
    private static let legacyCommands: [String: String] = [
        "HTTP headers": "curl -sI http://$RHOST",
        "WhatWeb (technologies)": "whatweb -a 3 http://$RHOST",
        "Gobuster: directories": "gobuster dir -u http://$RHOST -w /usr/share/wordlists/dirb/common.txt -x php,txt,html -o scans/gobuster.txt",
        "Nikto": "nikto -h http://$RHOST -o scans/nikto.txt",
        "Inspect TLS certificate": "openssl s_client -connect $RHOST:443 -servername $RHOST </dev/null 2>/dev/null | openssl x509 -noout -text",
        "robots.txt / sitemap": "curl -s http://$RHOST/robots.txt; curl -s http://$RHOST/sitemap.xml | head -50",
        "SSH: algorithms and host key": "nmap -p22 --script ssh2-enum-algos,ssh-hostkey $RHOST",
        "FTP: test anonymous login": "nmap -p21 --script ftp-anon,ftp-syst $RHOST",
        "Banner grab": "nc -nv $RHOST 80",
    ]

    static func guessServices(title: String, category: String) -> [String]? {
        let known: [String: [String]] = [
            "ssh": ["ssh", "22"], "ftp": ["ftp", "21"], "smb": ["smb", "microsoft-ds", "netbios-ssn", "445", "139"],
            "dns": ["dns", "domain", "53"], "http": ["http", "https", "80", "443", "8080", "8443"], "web": ["http", "https", "80", "443", "8080", "8443"],
            "ldap": ["ldap", "ldaps", "389", "636"], "snmp": ["snmp", "161"], "rdp": ["rdp", "ms-wbt-server", "3389"],
            "mysql": ["mysql", "3306"], "mssql": ["mssql", "ms-sql-s", "1433"], "smtp": ["smtp", "25", "587"], "nfs": ["nfs", "2049"],
            "rpc": ["rpcbind", "msrpc", "111", "135"], "winrm": ["winrm", "5985", "5986"], "vnc": ["vnc", "5900"], "telnet": ["telnet", "23"],
            "kerberos": ["kerberos", "kerberos-sec", "88"], "redis": ["redis", "6379"], "postgres": ["postgresql", "5432"],
        ]
        let lower = title.lowercased()
        if let colon = lower.firstIndex(of: ":") {
            let prefix = lower[..<colon].trimmingCharacters(in: .whitespaces)
            if let tags = known[prefix] { return tags }
        }
        for (key, tags) in known where lower.hasPrefix(key + " ") || lower.hasPrefix(key + "-") {
            return tags
        }
        switch category.lowercased() {
        case "nmap", "scanning": return ["host"]
        case "web": return known["web"]
        default: return nil
        }
    }

    var filtered: [Snippet] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return snippets }
        return snippets.filter {
            $0.title.lowercased().contains(query)
                || $0.command.lowercased().contains(query)
                || $0.category.lowercased().contains(query)
        }
    }

    /// Categories in order of first appearance.
    var filteredCategories: [String] {
        var seen: [String] = []
        for snippet in filtered where !seen.contains(snippet.category) {
            seen.append(snippet.category)
        }
        return seen
    }

    /// `$RHOST` / `${RHOST}` (whole name, so not `$RHOSTS`) plus the legacy placeholders.
    private static let rhostRegex = try! NSRegularExpression(
        pattern: #"\$\{RHOST\}|\$RHOST\b|<ip>|<target>|\$TARGET\b"#, options: [])
    private static let lhostRegex = try! NSRegularExpression(pattern: #"\$\{LHOST\}|\$LHOST\b"#, options: [])
    private static let lportRegex = try! NSRegularExpression(pattern: #"\$\{LPORT\}|\$LPORT\b"#, options: [])
    private static let rportRegex = try! NSRegularExpression(pattern: #"\$\{RPORT\}|\$RPORT\b"#, options: [])
    private static let rurlRegex = try! NSRegularExpression(pattern: #"\$\{RURL\}|\$RURL\b"#, options: [])

    /// Fills the placeholders with the values from the One-liners tab.
    func resolve(_ command: String) -> String {
        resolve(command, rhost: nil, rport: nil, service: nil)
    }

    /// Fills the placeholders for a specific host/port (Targets), falling back to the tab's values:
    /// `$RHOST`, `$RPORT`, `$RURL` (http(s)://host:port) plus `$LHOST` / `$LPORT`.
    func resolve(_ command: String, rhost: String?, rport: Int?, service: String?) -> String {
        var result = command
        let host = (rhost?.isEmpty == false ? rhost : nil) ?? target
        let portText = rport.map { String($0) } ?? self.rport
        let portNumber = Int(portText.trimmingCharacters(in: .whitespaces))
        let url = host.trimmingCharacters(in: .whitespaces).isEmpty ? "" : SnippetStore.url(host: host, port: portNumber, service: service)
        for (regex, raw) in [(SnippetStore.rurlRegex, url), (SnippetStore.rhostRegex, host), (SnippetStore.lhostRegex, lhost),
                             (SnippetStore.lportRegex, lport), (SnippetStore.rportRegex, portText)] {
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            let range = NSRange(location: 0, length: (result as NSString).length)
            // Neutralise template escapes ($ and \) in the replacement value.
            let escaped = NSRegularExpression.escapedTemplate(for: value)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: escaped)
        }
        return result
    }

    /// `http://host:port` for a service — https when the service name says so (https, ssl/http, …)
    /// or the port is 443/8443; the default port of the scheme is left out; IPv6 is bracketed.
    static func url(host: String, port: Int?, service: String?) -> String {
        let name = (service ?? "").lowercased()
        let secure = name.contains("https") || name.contains("ssl") || name.contains("tls") || port == 443 || port == 8443
        let scheme = secure ? "https" : "http"
        var address = host.trimmingCharacters(in: .whitespaces)
        if address.contains(":"), !address.hasPrefix("[") { address = "[\(address)]" }
        var url = "\(scheme)://\(address)"
        if let port, port > 0, port != (secure ? 443 : 80) { url += ":\(port)" }
        return url
    }

    /// Shell line that sets the variables, for the terminal: `export RHOST=10.10.10.5 LHOST=10.8.0.2 LPORT=4444`.
    var exportLine: String? {
        var parts: [String] = []
        let url = target.trimmingCharacters(in: .whitespaces).isEmpty ? "" : SnippetStore.url(host: target, port: Int(rport.trimmingCharacters(in: .whitespaces)), service: nil)
        for (name, raw) in [("RHOST", target), ("RPORT", rport), ("RURL", url), ("LHOST", lhost), ("LPORT", lport)] {
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            // Only "safe" characters go unquoted; anything else is single-quoted.
            let safe = value.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || ".-_:/".unicodeScalars.contains($0) }
            let quoted = safe ? value : "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
            parts.append("\(name)=\(quoted)")
        }
        guard !parts.isEmpty else { return nil }
        return "export " + parts.joined(separator: " ")
    }

    func copyToClipboard(_ snippet: Snippet) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(resolve(snippet.command), forType: .string)
    }

    func upsert(_ snippet: Snippet) {
        if let index = snippets.firstIndex(where: { $0.id == snippet.id }) {
            snippets[index] = snippet
        } else {
            snippets.append(snippet)
        }
        scheduleSave()
    }

    func delete(_ id: UUID) {
        snippets.removeAll { $0.id == id }
        scheduleSave()
    }

    /// Adds the default one-liners that are not in the list yet (matched by title).
    func addMissingDefaults() {
        let existingTitles = Set(snippets.map { $0.title })
        for snippet in SnippetStore.defaultSnippets where !existingTitles.contains(snippet.title) {
            snippets.append(snippet)
        }
        scheduleSave()
    }

    func saveTarget() {
        let defaults = UserDefaults.standard
        defaults.set(target, forKey: SettingsKey.snippetTarget)
        defaults.set(lhost, forKey: SettingsKey.snippetLHost)
        defaults.set(lport, forKey: SettingsKey.snippetLPort)
        defaults.set(rport, forKey: SettingsKey.snippetRPort)
    }

    func scheduleSave() {
        saver.call { [weak self] in
            guard let self else { return }
            Storage.save(self.snippets, to: SnippetStore.fileName)
        }
    }

    func flush() {
        saver.flush()
    }

    // MARK: - Default list (freely editable in the app)

    static let defaultSnippets: [Snippet] = [
        // Scanning
        Snippet(title: "Nmap: default scan (scripts + versions)", command: "nmap -sC -sV -oA scans/initial $RHOST", category: "Nmap", services: ["host"]),
        Snippet(title: "Nmap: all TCP ports", command: "nmap -p- --min-rate 2000 -T4 -oA scans/allports $RHOST", category: "Nmap", services: ["host"]),
        Snippet(title: "Nmap: targeted scan of discovered ports", command: "nmap -sC -sV -p 22,80,443 -oA scans/targeted $RHOST", category: "Nmap", services: ["host"]),
        Snippet(title: "Nmap: top UDP ports", command: "sudo nmap -sU --top-ports 50 -oA scans/udp $RHOST", category: "Nmap", services: ["host"]),
        Snippet(title: "Nmap: host discovery in a subnet", command: "nmap -sn 10.10.10.0/24 -oG scans/hosts.gnmap", category: "Nmap"),
        Snippet(title: "Nmap: XML output (for importing into Luik)", command: "nmap -sC -sV -oX scans/scan.xml $RHOST", category: "Nmap", services: ["host"]),

        // Web
        Snippet(title: "HTTP headers", command: "curl -sI $RURL", category: "Web", services: ["http", "https", "http-proxy", "http-alt", "80", "443", "8080", "8443", "8000"]),
        Snippet(title: "WhatWeb (technologies)", command: "whatweb -a 3 $RURL", category: "Web", services: ["http", "https", "http-proxy", "http-alt", "80", "443", "8080", "8443", "8000"]),
        Snippet(title: "Gobuster: directories", command: "gobuster dir -u $RURL -w /usr/share/wordlists/dirb/common.txt -x php,txt,html -o scans/gobuster.txt", category: "Web", services: ["http", "https", "http-proxy", "http-alt", "80", "443", "8080", "8443", "8000"]),
        Snippet(title: "Nikto", command: "nikto -h $RURL -o scans/nikto.txt", category: "Web", services: ["http", "https", "http-proxy", "http-alt", "80", "443", "8080", "8443", "8000"]),
        Snippet(title: "Inspect TLS certificate", command: "openssl s_client -connect $RHOST:$RPORT -servername $RHOST </dev/null 2>/dev/null | openssl x509 -noout -text", category: "Web", services: ["https", "ssl/http", "443", "8443", "ldaps", "636", "smtps", "imaps", "pop3s"]),
        Snippet(title: "robots.txt / sitemap", command: "curl -s $RURL/robots.txt; curl -s $RURL/sitemap.xml | head -50", category: "Web", services: ["http", "https", "http-proxy", "http-alt", "80", "443", "8080", "8443", "8000"]),

        // Services
        Snippet(title: "SMB: shares (anonymous)", command: "smbclient -L //$RHOST -N", category: "Services", services: ["smb", "microsoft-ds", "netbios-ssn", "445", "139"]),
        Snippet(title: "enum4linux", command: "enum4linux -a $RHOST", category: "Services", services: ["smb", "microsoft-ds", "netbios-ssn", "445", "139", "host"]),
        Snippet(title: "LDAP: naming contexts", command: "ldapsearch -x -H ldap://$RHOST -s base namingcontexts", category: "Services", services: ["ldap", "ldaps", "389", "636", "3268"]),
        Snippet(title: "SNMP walk (community public)", command: "snmpwalk -v2c -c public $RHOST", category: "Services", services: ["snmp", "161"]),
        Snippet(title: "SSH: algorithms and host key", command: "nmap -p$RPORT --script ssh2-enum-algos,ssh-hostkey $RHOST", category: "Services", services: ["ssh", "22"]),
        Snippet(title: "FTP: test anonymous login", command: "nmap -p$RPORT --script ftp-anon,ftp-syst $RHOST", category: "Services", services: ["ftp", "21"]),
        Snippet(title: "DNS: zone information", command: "dig any @$RHOST example.local; dig axfr @$RHOST example.local", category: "Services", services: ["dns", "domain", "53"]),
        Snippet(title: "Banner grab", command: "nc -nv $RHOST $RPORT", category: "Services", services: ["port"]),

        // Utilities
        Snippet(title: "Simple HTTP server (share files)", command: "python3 -m http.server 8000", category: "Utilities"),
        Snippet(title: "Fetch a file from your machine (run on the target)", command: "curl -O http://$LHOST:8000/file", category: "Utilities"),
        Snippet(title: "Netcat listener", command: "nc -lvnp $LPORT", category: "Utilities"),
        Snippet(title: "Receive a file with netcat", command: "nc -lvnp $LPORT > received.bin", category: "Utilities"),
        Snippet(title: "SSH: local port forward", command: "ssh -L 8080:127.0.0.1:80 user@$RHOST", category: "Utilities", services: ["ssh", "22"]),
        Snippet(title: "tcpdump to pcap", command: "sudo tcpdump -i en0 host $RHOST -w scans/capture.pcap", category: "Utilities", services: ["host"]),
        Snippet(title: "searchsploit", command: "searchsploit <service>", category: "Utilities"),
        Snippet(title: "Create engagement folders", command: "mkdir -p scans loot notes exploits && ls", category: "Utilities"),

        // Linux enumeration (on the target)
        Snippet(title: "Linux: system info", command: "id; uname -a; cat /etc/os-release", category: "Linux enumeration"),
        Snippet(title: "Linux: sudo rights", command: "sudo -l", category: "Linux enumeration"),
        Snippet(title: "Linux: SUID binaries", command: "find / -perm -4000 -type f 2>/dev/null", category: "Linux enumeration"),
        Snippet(title: "Linux: listening ports", command: "ss -tulpn 2>/dev/null || netstat -tulpn", category: "Linux enumeration"),
        Snippet(title: "Linux: cron jobs", command: "cat /etc/crontab; ls -la /etc/cron.*", category: "Linux enumeration"),
        Snippet(title: "Linux: writable directories", command: "find / -writable -type d 2>/dev/null | grep -v -e proc -e sys", category: "Linux enumeration"),

        // Windows enumeration (on the target)
        Snippet(title: "Windows: system info", command: "systeminfo; whoami /all", category: "Windows enumeration"),
        Snippet(title: "Windows: network and shares", command: "ipconfig /all; net share; netstat -ano", category: "Windows enumeration"),
        Snippet(title: "Windows: users and groups", command: "net user; net localgroup administrators", category: "Windows enumeration"),
    ]

    // MARK: - Legacy names (versions up to 0.7 shipped Dutch defaults)

    static let legacyTitles: [String: String] = [
        "Nmap: standaardscan (scripts + versies)": "Nmap: default scan (scripts + versions)",
        "Nmap: alle TCP-poorten": "Nmap: all TCP ports",
        "Nmap: gerichte scan op gevonden poorten": "Nmap: targeted scan of discovered ports",
        "Nmap: top UDP-poorten": "Nmap: top UDP ports",
        "Nmap: hostdiscovery in subnet": "Nmap: host discovery in a subnet",
        "Nmap: output als XML (voor import in Luik)": "Nmap: XML output (for importing into Luik)",
        "HTTP-headers": "HTTP headers",
        "WhatWeb (technologieën)": "WhatWeb (technologies)",
        "TLS-certificaat bekijken": "Inspect TLS certificate",
        "SMB: shares (anoniem)": "SMB: shares (anonymous)",
        "SSH: algoritmes en hostkey": "SSH: algorithms and host key",
        "FTP: anonieme login testen": "FTP: test anonymous login",
        "DNS: zone-informatie": "DNS: zone information",
        "Banner grabben": "Banner grab",
        "Simpele HTTP-server (bestanden delen)": "Simple HTTP server (share files)",
        "Bestand ophalen": "Fetch a file from your machine (run on the target)",
        "Fetch a file": "Fetch a file from your machine (run on the target)",
        "SSH: lokale port forward": "SSH: local port forward",
        "tcpdump naar pcap": "tcpdump to pcap",
        "Opdrachtmap aanmaken": "Create engagement folders",
        "Linux: systeeminfo": "Linux: system info",
        "Linux: sudo-rechten": "Linux: sudo rights",
        "Linux: SUID-binaries": "Linux: SUID binaries",
        "Linux: luisterende poorten": "Linux: listening ports",
        "Linux: cronjobs": "Linux: cron jobs",
        "Linux: beschrijfbare mappen": "Linux: writable directories",
        "Windows: systeeminfo": "Windows: system info",
        "Windows: netwerk en shares": "Windows: network and shares",
        "Windows: gebruikers en groepen": "Windows: users and groups",
    ]

    static let legacyCategories: [String: String] = [
        "Diensten": "Services",
        "Hulpmiddelen": "Utilities",
        "Linux-enumeratie": "Linux enumeration",
        "Windows-enumeratie": "Windows enumeration",
        "Algemeen": "General",
    ]
}
