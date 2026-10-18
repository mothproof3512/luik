import Foundation

/// A filled-in example engagement, so a new Mac shows how the tabs hang together: a few hosts
/// with ports and checklists, two findings with evidence, a note, a plan, a diagram and some log
/// lines. All addresses are documentation ranges; nothing in it is real.
enum DemoEngagement {
    static let name = "Demo — Example Corp"

    static var exists: Bool {
        EngagementStore.shared.engagements.contains { $0.name == name }
    }

    /// Creates the demo engagement and switches to it. Returns false when it exists already.
    @discardableResult
    static func create() -> Bool {
        let engagements = EngagementStore.shared
        if let existing = engagements.engagements.first(where: { $0.name == name }) {
            engagements.switchTo(existing.id)
            return false
        }
        var engagement = engagements.create(name: name, switchToIt: true)
        engagement.client = "Example Corp (fictional)"
        engagement.reference = "DEMO-2026-001"
        engagement.period = "this week"
        engagement.scope = ["203.0.113.0/24", "198.51.100.10", "app.example.com"]
        engagement.exclusions = ["203.0.113.250"]
        engagement.notes = "Fictional engagement to show how Luik's tabs work together. Delete it from Manage engagements when you are done looking."
        engagements.update(engagement)

        // Targets: three hosts with ports and checklists.
        let targets = TargetStore.shared
        let web = targets.addHost(address: "203.0.113.10", hostname: "www.example.com")
        _ = targets.addPort(to: web, number: 22, proto: "tcp", description: "ssh — OpenSSH 8.9p1")
        _ = targets.addPort(to: web, number: 80, proto: "tcp", description: "http — nginx 1.18.0")
        let https = targets.addPort(to: web, number: 443, proto: "tcp", description: "https — nginx 1.18.0")
        https.notes = "TLS 1.2 and 1.3; certificate for www.example.com and app.example.com.\nSecurity headers missing: CSP, X-Frame-Options.\n"
        let dc = targets.addHost(address: "203.0.113.20", hostname: "dc01.corp.example")
        _ = targets.addPort(to: dc, number: 88, proto: "tcp", description: "kerberos-sec — Microsoft Windows Kerberos")
        _ = targets.addPort(to: dc, number: 389, proto: "tcp", description: "ldap — Microsoft Windows Active Directory LDAP")
        let smb = targets.addPort(to: dc, number: 445, proto: "tcp", description: "microsoft-ds — Windows Server 2019")
        smb.notes = "SMB signing: required.\nNull session: not allowed.\n"
        let legacy = targets.addHost(address: "198.51.100.10", hostname: "legacy-ftp.example.com")
        let ftp = targets.addPort(to: legacy, number: 21, proto: "tcp", description: "ftp — vsftpd 2.3.4")
        ftp.notes = "Anonymous login allowed; directory listing shows backup-2024.zip.\n"
        ftp.status = .inProgress
        for host in [web, dc, legacy] {
            _ = targets.applyTemplate(to: host)
            for port in host.children where port.kind == .port { _ = targets.applyTemplate(to: port) }
        }
        if let item = ftp.children.first(where: { $0.title.lowercased().contains("anonymous") }) { item.status = .done }
        targets.selectedID = web.id
        targets.scheduleSave()

        // Findings.
        let findings = FindingsStore.shared
        var f1 = Finding(title: "Anonymous FTP access exposes backup archive", severity: .high)
        f1.cvssVector = "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:N/A:N"
        f1.affected = ["198.51.100.10:21/tcp"]
        f1.description = "The FTP service on the legacy host allows anonymous logins. The anonymous directory contains a file named backup-2024.zip."
        f1.impact = "Anyone on the internet can download the archive; depending on its contents this may expose configuration, credentials or personal data."
        f1.evidence = "**2026-10-18 10:12:03** · Terminal: 198.51.100.10\n\n```\n$ ftp 198.51.100.10\n(anonymous login accepted — listing shows backup-2024.zip)\n```\n"
        f1.recommendation = "Disable anonymous FTP, remove the archive from the service, and migrate file transfers to SFTP with named accounts."
        f1.references = "https://cwe.mitre.org/data/definitions/284.html"
        f1.status = .confirmed
        f1.source = "manual"
        _ = findings.add(f1, select: false)
        var f2 = Finding(title: "Missing security headers on www.example.com", severity: .low)
        f2.affected = ["203.0.113.10:443/tcp"]
        f2.description = "The web server does not send a Content-Security-Policy or X-Frame-Options header."
        f2.impact = "Reduced protection against cross-site scripting and clickjacking; no direct exploit on its own."
        f2.recommendation = "Add a Content-Security-Policy, X-Frame-Options (or frame-ancestors) and the other standard security headers in the nginx configuration."
        f2.status = .open
        f2.source = "nuclei http-missing-security-headers"
        _ = findings.add(f2, select: true)

        // A note, a plan, a diagram.
        let notes = NotesStore.shared
        notes.notes.insert(Note(title: "Day 1", body: "# Day 1\n\n- Kick-off with the client contact; scope confirmed (see Engagement).\n- External scan of 203.0.113.0/24 imported into Targets.\n- Legacy FTP host looks interesting → finding written.\n\n## Tomorrow\n\n- Web application testing on app.example.com\n- Kerberos user enumeration on dc01 (within RoE)\n"), at: 0)
        notes.scheduleSave()
        let plans = PlanStore.shared
        if let template = plans.templates.first(where: { $0.name == "External network penetration test" }) {
            var plan = plans.createPlan(from: template, name: "External test — Example Corp")
            for phaseIndex in plan.phases.indices.prefix(2) {
                for itemIndex in plan.phases[phaseIndex].items.indices { plan.phases[phaseIndex].items[itemIndex].status = .done }
            }
            if let index = plans.plans.firstIndex(where: { $0.id == plan.id }) { plans.plans[index] = plan }
            plans.scheduleSave()
        }
        let diagrams = DiagramStore.shared
        _ = diagrams.newDiagram(name: "Example network", sample: true)

        // Log lines that show the kinds of entries.
        let log = ActivityLog.shared
        log.record(.import, "nmap import: 3 hosts, 7 ports 203.0.113.10, 203.0.113.20, 198.51.100.10", source: "Targets")
        log.record(.typed, "nmap -sC -sV -oA scans/external 203.0.113.0/24", source: "Terminal: Shell", host: "203.0.113.10")
        log.record(.evidence, "Output of “ftp 198.51.100.10” pinned to finding “Anonymous FTP access exposes backup archive”", source: "Terminal")
        log.record(.action, "Demo engagement created — fictional data, documentation address ranges", source: "Engagements")
        return true
    }
}
