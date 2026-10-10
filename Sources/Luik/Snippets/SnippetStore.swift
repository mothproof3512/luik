import AppKit
import Foundation
import Observation

struct Snippet: Identifiable, Codable, Equatable, Hashable {
    var id = UUID()
    var title: String
    var command: String
    var category: String
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
    @ObservationIgnored private var saver = Debouncer()

    init() {
        snippets = Storage.load([Snippet].self, from: SnippetStore.fileName) ?? SnippetStore.defaultSnippets
        let defaults = UserDefaults.standard
        target = defaults.string(forKey: SettingsKey.snippetTarget) ?? ""
        lhost = defaults.string(forKey: SettingsKey.snippetLHost) ?? ""
        lport = defaults.string(forKey: SettingsKey.snippetLPort) ?? ""
        if lhost.isEmpty, let suggested = LocalAddress.suggested() {
            lhost = suggested.address
        }
        migrateIfNeeded()
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

    func resolve(_ command: String) -> String {
        var result = command
        for (regex, raw) in [(SnippetStore.rhostRegex, target), (SnippetStore.lhostRegex, lhost), (SnippetStore.lportRegex, lport)] {
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            let range = NSRange(location: 0, length: (result as NSString).length)
            // Neutralise template escapes ($ and \) in the replacement value.
            let escaped = NSRegularExpression.escapedTemplate(for: value)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: escaped)
        }
        return result
    }

    /// Shell line that sets the variables, for the terminal: `export RHOST=10.10.10.5 LHOST=10.8.0.2 LPORT=4444`.
    var exportLine: String? {
        var parts: [String] = []
        for (name, raw) in [("RHOST", target), ("LHOST", lhost), ("LPORT", lport)] {
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
        Snippet(title: "Nmap: default scan (scripts + versions)", command: "nmap -sC -sV -oA scans/initial $RHOST", category: "Nmap"),
        Snippet(title: "Nmap: all TCP ports", command: "nmap -p- --min-rate 2000 -T4 -oA scans/allports $RHOST", category: "Nmap"),
        Snippet(title: "Nmap: targeted scan of discovered ports", command: "nmap -sC -sV -p 22,80,443 -oA scans/targeted $RHOST", category: "Nmap"),
        Snippet(title: "Nmap: top UDP ports", command: "sudo nmap -sU --top-ports 50 -oA scans/udp $RHOST", category: "Nmap"),
        Snippet(title: "Nmap: host discovery in a subnet", command: "nmap -sn 10.10.10.0/24 -oG scans/hosts.gnmap", category: "Nmap"),
        Snippet(title: "Nmap: XML output (for importing into Luik)", command: "nmap -sC -sV -oX scans/scan.xml $RHOST", category: "Nmap"),

        // Web
        Snippet(title: "HTTP headers", command: "curl -sI http://$RHOST", category: "Web"),
        Snippet(title: "WhatWeb (technologies)", command: "whatweb -a 3 http://$RHOST", category: "Web"),
        Snippet(title: "Gobuster: directories", command: "gobuster dir -u http://$RHOST -w /usr/share/wordlists/dirb/common.txt -x php,txt,html -o scans/gobuster.txt", category: "Web"),
        Snippet(title: "Nikto", command: "nikto -h http://$RHOST -o scans/nikto.txt", category: "Web"),
        Snippet(title: "Inspect TLS certificate", command: "openssl s_client -connect $RHOST:443 -servername $RHOST </dev/null 2>/dev/null | openssl x509 -noout -text", category: "Web"),
        Snippet(title: "robots.txt / sitemap", command: "curl -s http://$RHOST/robots.txt; curl -s http://$RHOST/sitemap.xml | head -50", category: "Web"),

        // Services
        Snippet(title: "SMB: shares (anonymous)", command: "smbclient -L //$RHOST -N", category: "Services"),
        Snippet(title: "enum4linux", command: "enum4linux -a $RHOST", category: "Services"),
        Snippet(title: "LDAP: naming contexts", command: "ldapsearch -x -H ldap://$RHOST -s base namingcontexts", category: "Services"),
        Snippet(title: "SNMP walk (community public)", command: "snmpwalk -v2c -c public $RHOST", category: "Services"),
        Snippet(title: "SSH: algorithms and host key", command: "nmap -p22 --script ssh2-enum-algos,ssh-hostkey $RHOST", category: "Services"),
        Snippet(title: "FTP: test anonymous login", command: "nmap -p21 --script ftp-anon,ftp-syst $RHOST", category: "Services"),
        Snippet(title: "DNS: zone information", command: "dig any @$RHOST example.local; dig axfr @$RHOST example.local", category: "Services"),
        Snippet(title: "Banner grab", command: "nc -nv $RHOST 80", category: "Services"),

        // Utilities
        Snippet(title: "Simple HTTP server (share files)", command: "python3 -m http.server 8000", category: "Utilities"),
        Snippet(title: "Fetch a file from your machine (run on the target)", command: "curl -O http://$LHOST:8000/file", category: "Utilities"),
        Snippet(title: "Netcat listener", command: "nc -lvnp $LPORT", category: "Utilities"),
        Snippet(title: "Receive a file with netcat", command: "nc -lvnp $LPORT > received.bin", category: "Utilities"),
        Snippet(title: "SSH: local port forward", command: "ssh -L 8080:127.0.0.1:80 user@$RHOST", category: "Utilities"),
        Snippet(title: "tcpdump to pcap", command: "sudo tcpdump -i en0 host $RHOST -w scans/capture.pcap", category: "Utilities"),
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
