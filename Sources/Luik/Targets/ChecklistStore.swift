import AppKit
import Foundation
import Observation

/// One work item of a checklist: becomes a node with a status under a host or port. The optional
/// hint is placed in the node's notes (with $RHOST / $RPORT filled in), so a checklist can carry
/// your own workflow: what to check, which command to run, what counts as a finding.
struct ChecklistItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var hint = ""

    init(id: UUID = UUID(), title: String, hint: String = "") {
        self.id = id
        self.title = title
        self.hint = hint
    }

    private enum CodingKeys: String, CodingKey { case id, title, hint }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decode(String.self, forKey: .title)
        hint = try c.decodeIfPresent(String.self, forKey: .hint) ?? ""
    }
}

/// A checklist: the work items for every system, for every port without a specific list, or for
/// the ports whose service name / port number matches one of its keys.
struct Checklist: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    /// nmap/Nessus service names ("http", "microsoft-ds") and/or port numbers ("445"), lower-cased.
    var keys: [String] = []
    var items: [ChecklistItem]
    var enabled = true

    init(id: UUID = UUID(), name: String, keys: [String] = [], items: [ChecklistItem], enabled: Bool = true) {
        self.id = id
        self.name = name
        self.keys = keys
        self.items = items
        self.enabled = enabled
    }

    private enum CodingKeys: String, CodingKey { case id, name, keys, items, enabled }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Checklist"
        keys = try c.decodeIfPresent([String].self, forKey: .keys) ?? []
        items = try c.decodeIfPresent([ChecklistItem].self, forKey: .items) ?? []
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }

    var keysText: String { keys.joined(separator: ", ") }

    static func parseKeys(_ text: String) -> [String] {
        text.split(whereSeparator: { $0 == "," || $0 == ";" || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
    }

    func matches(service: String, port: Int) -> Bool {
        guard enabled else { return false }
        let name = service.lowercased().trimmingCharacters(in: .whitespaces)
        if !name.isEmpty {
            let short = name.split(separator: "/").last.map(String.init) ?? name
            if keys.contains(name) || keys.contains(short) { return true }
        }
        return port > 0 && keys.contains(String(port))
    }
}

struct ChecklistSet: Codable, Equatable {
    var host: Checklist
    var port: Checklist
    var services: [Checklist]
}

/// The checklists (checklists.json in the data folder, shared by all engagements) and the lookup
/// the Targets tree uses when it creates hosts and ports.
@Observable
final class ChecklistStore {
    static let shared = ChecklistStore()

    private static let fileName = "checklists.json"

    var lists: ChecklistSet
    /// The editor sheet.
    var showEditor = false
    @ObservationIgnored private var saver = Debouncer()

    init() {
        if let stored = Storage.load(ChecklistSet.self, from: ChecklistStore.fileName) {
            lists = stored
        } else {
            lists = ChecklistStore.migratedFromSettings() ?? ChecklistStore.defaults
            Storage.save(lists, to: ChecklistStore.fileName)
        }
    }

    // MARK: - Lookup

    var hostItems: [ChecklistItem] { lists.host.items }

    /// The checklist a port gets: the first enabled service list whose keys match the service name
    /// (as nmap/Nessus report it) or the port number, otherwise the generic port list.
    func checklist(forService service: String, port: Int) -> Checklist {
        lists.services.first { $0.matches(service: service, port: port) } ?? lists.port
    }

    func items(forService service: String, port: Int) -> [ChecklistItem] {
        checklist(forService: service, port: port).items
    }

    var allLists: [Checklist] { [lists.host, lists.port] + lists.services }

    func checklist(id: UUID) -> Checklist? {
        allLists.first { $0.id == id }
    }

    // MARK: - Editing

    func update(_ checklist: Checklist) {
        if checklist.id == lists.host.id {
            lists.host = checklist
        } else if checklist.id == lists.port.id {
            lists.port = checklist
        } else if let index = lists.services.firstIndex(where: { $0.id == checklist.id }) {
            lists.services[index] = checklist
        }
        scheduleSave()
    }

    @discardableResult
    func addService(name: String = "New service", keys: [String] = []) -> Checklist {
        let checklist = Checklist(name: name, keys: keys, items: [ChecklistItem(title: "Enumeration")])
        lists.services.append(checklist)
        scheduleSave()
        return checklist
    }

    func deleteService(_ id: UUID) {
        lists.services.removeAll { $0.id == id }
        scheduleSave()
    }

    func moveService(from source: IndexSet, to destination: Int) {
        lists.services.move(fromOffsets: source, toOffset: destination)
        scheduleSave()
    }

    func moveService(_ id: UUID, up: Bool) {
        guard let index = lists.services.firstIndex(where: { $0.id == id }) else { return }
        let target = up ? index - 1 : index + 1
        guard target >= 0, target < lists.services.count else { return }
        lists.services.swapAt(index, target)
        scheduleSave()
    }

    func resetToDefaults() {
        lists = ChecklistStore.defaults
        scheduleSave()
        ActivityLog.shared.record(.action, "Checklists reset to the defaults", source: "Checklists")
    }

    // MARK: - Export / import

    func exportJSON() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(lists)
    }

    /// Replaces or merges the checklists from an exported file.
    func importJSON(_ data: Data, merge: Bool) throws {
        let imported = try JSONDecoder().decode(ChecklistSet.self, from: data)
        if merge {
            // Same-named service lists are replaced, new ones appended; the generic lists are replaced.
            var services = lists.services
            for list in imported.services {
                if let index = services.firstIndex(where: { $0.name.lowercased() == list.name.lowercased() }) {
                    services[index] = list
                } else {
                    services.append(list)
                }
            }
            lists = ChecklistSet(host: imported.host, port: imported.port, services: services)
        } else {
            lists = imported
        }
        scheduleSave()
        ActivityLog.shared.record(.action, "Checklists imported (\(imported.services.count) service lists)", source: "Checklists")
    }

    // MARK: - Hints

    /// Fills $RHOST / $RPORT (and $LHOST / $LPORT when set in One-liners) in a hint.
    static func resolve(_ hint: String, address: String, port: Int?) -> String {
        guard !hint.isEmpty else { return "" }
        var text = hint
        for token in ["${RHOST}", "$RHOST"] { text = text.replacingOccurrences(of: token, with: address) }
        if let port {
            for token in ["${RPORT}", "$RPORT"] { text = text.replacingOccurrences(of: token, with: String(port)) }
        }
        let snippets = SnippetStore.shared
        if !snippets.lhost.isEmpty {
            for token in ["${LHOST}", "$LHOST"] { text = text.replacingOccurrences(of: token, with: snippets.lhost) }
        }
        if !snippets.lport.isEmpty {
            for token in ["${LPORT}", "$LPORT"] { text = text.replacingOccurrences(of: token, with: snippets.lport) }
        }
        return text
    }

    // MARK: - Saving

    func scheduleSave() {
        saver.call { [weak self] in
            guard let self else { return }
            Storage.save(self.lists, to: ChecklistStore.fileName)
        }
    }

    func flush() {
        saver.flush()
    }

    // MARK: - Defaults and migration

    /// The built-in checklists, built from the text templates in SettingsDefaults.
    static var defaults: ChecklistSet {
        let host = Checklist(name: "Every system", items: SettingsDefaults.templateItems(SettingsDefaults.hostTemplate).map { ChecklistItem(title: $0) })
        let port = Checklist(name: "Every port (fallback)", items: SettingsDefaults.templateItems(SettingsDefaults.portTemplate).map { ChecklistItem(title: $0) })
        let services = SettingsDefaults.serviceTemplateRules(SettingsDefaults.serviceTemplates).map { rule in
            Checklist(name: defaultName(forKeys: rule.keys), keys: rule.keys, items: rule.items.map { ChecklistItem(title: $0) })
        }
        return ChecklistSet(host: host, port: port, services: services)
    }

    /// Versions up to 0.14 kept the templates as comma-separated text in the settings; when the
    /// user changed them, carry those changes over once.
    private static func migratedFromSettings() -> ChecklistSet? {
        let defaults = UserDefaults.standard
        let hostText = defaults.string(forKey: SettingsKey.hostTemplate) ?? SettingsDefaults.hostTemplate
        let portText = defaults.string(forKey: SettingsKey.portTemplate) ?? SettingsDefaults.portTemplate
        let serviceText = defaults.string(forKey: SettingsKey.serviceTemplates) ?? SettingsDefaults.serviceTemplates
        guard hostText != SettingsDefaults.hostTemplate || portText != SettingsDefaults.portTemplate || serviceText != SettingsDefaults.serviceTemplates else {
            return nil
        }
        let host = Checklist(name: "Every system", items: SettingsDefaults.templateItems(hostText).map { ChecklistItem(title: $0) })
        let port = Checklist(name: "Every port (fallback)", items: SettingsDefaults.templateItems(portText).map { ChecklistItem(title: $0) })
        let services = SettingsDefaults.serviceTemplateRules(serviceText).map { rule in
            Checklist(name: defaultName(forKeys: rule.keys), keys: rule.keys, items: rule.items.map { ChecklistItem(title: $0) })
        }
        return ChecklistSet(host: host, port: port, services: services)
    }

    /// "http, https, 80, 443" → "HTTP"; "microsoft-ds" → "SMB"; "ms-wbt-server" → "RDP".
    static func defaultName(forKeys keys: [String]) -> String {
        let names: [String: String] = [
            "http": "HTTP / web", "ssh": "SSH", "ftp": "FTP", "smb": "SMB", "microsoft-ds": "SMB", "rdp": "RDP", "ms-wbt-server": "RDP",
            "dns": "DNS", "domain": "DNS", "ldap": "LDAP", "kerberos": "Kerberos", "kerberos-sec": "Kerberos", "mssql": "MSSQL", "ms-sql-s": "MSSQL",
            "mysql": "MySQL", "postgresql": "PostgreSQL", "smtp": "SMTP", "pop3": "POP3 / IMAP", "imap": "POP3 / IMAP", "snmp": "SNMP",
            "telnet": "Telnet", "vnc": "VNC", "nfs": "NFS", "rpcbind": "RPC (portmapper)", "msrpc": "MSRPC", "winrm": "WinRM",
            "redis": "Redis", "mongodb": "MongoDB", "elasticsearch": "Elasticsearch", "docker": "Docker",
        ]
        for key in keys {
            if let name = names[key] { return name }
        }
        let first = keys.first { Int($0) == nil } ?? keys.first ?? "Service"
        return first.uppercased()
    }
}
