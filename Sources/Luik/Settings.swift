import Foundation

/// Version and repository, used by the settings footer, the update check and build.sh.
enum AppInfo {
    static let version = "0.15.2"
    static let repository = "mothproof3512/Luik"
}

/// UserDefaults keys. The settings UI uses @AppStorage with the same keys.
enum SettingsKey {
    static let hotKey = "hotKey"
    static let heightFraction = "heightFraction"
    static let widthFraction = "widthFraction"
    /// Corner radius of the panel, in points (0 = square).
    static let cornerRadius = "cornerRadius"
    /// Round the top corners too (default: bottom corners only, like Guake).
    static let roundTopCorners = "roundTopCorners"
    /// Duration of the slide animation in seconds (0 = instant).
    static let animationDuration = "animationDuration"
    static let hideOnFocusLoss = "hideOnFocusLoss"
    static let fontSize = "terminalFontSize"
    /// Opacity of the background of the whole panel (0 = see-through, 1 = solid).
    static let panelOpacity = "panelOpacity"
    /// Blur whatever is behind the panel.
    static let panelBlur = "panelBlur"
    /// Extra dark layer under the terminal text, on top of the panel background.
    static let terminalExtraOpacity = "terminalExtraOpacity"
    static let shellPath = "shellPath"
    static let hostTemplate = "hostTemplate"
    static let portTemplate = "portTemplate"
    /// Service-specific work items (see SettingsDefaults.serviceTemplates for the format).
    static let serviceTemplates = "serviceTemplates"
    static let showOnLaunch = "showOnLaunch"
    static let snippetTarget = "snippetTarget"
    static let snippetLHost = "snippetLHost"
    static let snippetLPort = "snippetLPort"
    /// Apps (name or bundle id, comma-separated) in which the global hotkey is paused,
    /// so that e.g. F12 goes straight to a remote desktop or VM.
    static let hotKeyPauseApps = "hotKeyPauseApps"
    /// Record lines typed in Luik's terminal tabs in the activity log.
    static let logTypedCommands = "logTypedCommands"
    /// Folder for evidence screenshots ("" = ~/Documents/Luik Evidence).
    static let evidenceFolder = "evidenceFolder"
    /// Hide the panel while selecting the screenshot area.
    static let hideWhileCapturing = "hideWhileCapturing"
    /// Check GitHub for a newer release at launch (once a day).
    static let checkForUpdates = "checkForUpdates"
    static let lastUpdateCheck = "lastUpdateCheck"
    /// Id of the colour scheme (LuikTheme.id): "default" or one of the Sanzo Wada combinations.
    static let colorScheme = "colorScheme"
}

enum SettingsDefaults {
    /// Work-item nodes created under every new system (host).
    static let hostTemplate = "Recon & enumeration, Vulnerabilities, Initial access, Privilege escalation, Post-exploitation & loot"
    /// Work-item nodes created under every new port whose service has no entry in `serviceTemplates`.
    static let portTemplate = "Enumeration, Versions & CVEs, Misconfigurations, Credentials, Exploitation, Notes"

    /// Service-specific work items. One line per service: the keys (nmap service names and/or
    /// port numbers, comma-separated) before the colon, the work items after it.
    static let serviceTemplates = """
    http, https, http-proxy, http-alt, ssl/http, 80, 443, 8080, 8443, 8000, 8888: Technology fingerprint (headers, whatweb), Directory & file discovery, Virtual hosts & subdomains, Default & admin pages, Authentication & session handling, Input testing (injection, XSS, IDOR, upload), Known CVEs for product/version, TLS configuration
    ssh, 22: Banner & version, Supported algorithms & auth methods, Default/weak credentials (within RoE), Known CVEs
    ftp, ftps, 21: Anonymous login, Banner & version, Directory listing & writable directories, Known CVEs, Credential reuse
    smb, microsoft-ds, netbios-ssn, 445, 139: Null session & anonymous shares, Share enumeration & permissions, SMB version & signing, User/group enumeration (RID cycling), Known CVEs (MS17-010 etc.), Credential testing (within RoE)
    rdp, ms-wbt-server, 3389: NLA & encryption settings, Certificate & hostname info, Credential testing (within RoE), Known CVEs (BlueKeep etc.)
    dns, domain, 53: Zone transfer (AXFR), Reverse lookups / PTR sweep, Subdomain discovery, Recursion & cache snooping, DNSSEC
    ldap, ldaps, 389, 636, 3268, 3269: Anonymous bind & naming contexts, User/group/computer enumeration, Password policy, Interesting attributes (descriptions, LAPS, gMSA), ACL misconfigurations
    kerberos, kerberos-sec, 88: User enumeration, AS-REP roasting, Kerberoasting (with credentials), Clock skew & realm
    mssql, ms-sql-s, 1433: Default/weak credentials, Instance & version info, xp_cmdshell & linked servers, Impersonation & roles, Known CVEs
    mysql, 3306: Default/weak credentials, Remote root access, File read/write privileges & UDF, Known CVEs
    postgresql, 5432: Default/weak credentials, COPY TO/FROM PROGRAM, Extensions & file access, Known CVEs
    smtp, submission, smtps, 25, 465, 587: User enumeration (VRFY/EXPN/RCPT), Open relay test, STARTTLS & auth methods, Banner & version
    pop3, pop3s, imap, imaps, 110, 995, 143, 993: Banner & capabilities, Plaintext auth & TLS, Credential reuse
    snmp, 161: Community strings (public/private/brute), Full walk (users, processes, software, interfaces), Write access (RW community)
    telnet, 23: Banner, Default credentials, Plaintext credential capture
    vnc, 5900, 5901: Authentication required?, Version & known weaknesses, Credential testing (within RoE)
    nfs, 2049: Exported shares (showmount), Mount & permission review, no_root_squash / UID mapping
    rpcbind, 111: rpcinfo enumeration, NFS & other RPC services
    msrpc, 135: RPC enumeration (rpcclient), DCOM/WMI exposure
    winrm, wsman, 5985, 5986: Authentication methods, Credential testing (evil-winrm, within RoE)
    redis, 6379: Unauthenticated access, CONFIG & file write, Known CVEs
    mongodb, 27017: Unauthenticated access, Database enumeration
    elasticsearch, 9200: Unauthenticated access, Index enumeration, Known CVEs
    docker, 2375, 2376: Unauthenticated API, Container & image enumeration
    """

    static var all: [String: Any] {
        [
            SettingsKey.hotKey: "cmd+escape",
            SettingsKey.heightFraction: 0.55,
            SettingsKey.widthFraction: 1.0,
            SettingsKey.cornerRadius: 14.0,
            SettingsKey.roundTopCorners: false,
            SettingsKey.animationDuration: 0.18,
            SettingsKey.hideOnFocusLoss: true,
            SettingsKey.fontSize: 13.0,
            SettingsKey.panelOpacity: 0.75,
            SettingsKey.panelBlur: true,
            SettingsKey.terminalExtraOpacity: 0.0,
            SettingsKey.shellPath: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh",
            SettingsKey.hostTemplate: hostTemplate,
            SettingsKey.portTemplate: portTemplate,
            SettingsKey.serviceTemplates: serviceTemplates,
            SettingsKey.showOnLaunch: true,
            SettingsKey.snippetTarget: "",
            SettingsKey.snippetLHost: "",
            SettingsKey.snippetLPort: "4444",
            SettingsKey.hotKeyPauseApps: "",
            SettingsKey.logTypedCommands: true,
            SettingsKey.evidenceFolder: "",
            SettingsKey.hideWhileCapturing: true,
            SettingsKey.checkForUpdates: true,
            SettingsKey.colorScheme: "default",
        ]
    }

    /// Parses the service template text into (keys, items) rules.
    static func serviceTemplateRules(_ raw: String) -> [(keys: [String], items: [String])] {
        raw.components(separatedBy: .newlines).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), let colon = trimmed.firstIndex(of: ":") else { return nil }
            let keys = templateItems(String(trimmed[..<colon])).map { $0.lowercased() }
            let items = templateItems(String(trimmed[trimmed.index(after: colon)...]))
            guard !keys.isEmpty, !items.isEmpty else { return nil }
            return (keys, items)
        }
    }

    /// Work items for a port: by nmap service name first ("http", "microsoft-ds"), then by port number.
    static func templateItems(forService service: String, port: Int, rules: [(keys: [String], items: [String])], fallback: [String]) -> [String] {
        let name = service.lowercased().trimmingCharacters(in: .whitespaces)
        if !name.isEmpty {
            // Exact service name, then "ssl/http"-style names reduced to their last part.
            let candidates = [name, name.split(separator: "/").last.map(String.init) ?? name]
            for candidate in candidates {
                if let rule = rules.first(where: { $0.keys.contains(candidate) }) { return rule.items }
            }
        }
        if let rule = rules.first(where: { $0.keys.contains(String(port)) }) { return rule.items }
        return fallback
    }

    /// "A, B, C" -> ["A", "B", "C"]
    static func templateItems(_ raw: String) -> [String] {
        raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Names used by versions up to 0.7 (Dutch) and their English replacements.
    /// Used to migrate stored templates and existing target nodes.
    static let legacyTemplateNames: [String: String] = [
        "Recon & enumeratie": "Recon & enumeration",
        "Kwetsbaarheden": "Vulnerabilities",
        "Enumeratie": "Enumeration",
        "Versies & CVE's": "Versions & CVEs",
        "Misconfiguraties": "Misconfigurations",
        "Exploitatie": "Exploitation",
        "Notities": "Notes",
    ]
}
