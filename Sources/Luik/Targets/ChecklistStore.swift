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
    /// Where to read more: a library page (its path or a topic name) or a URL. Empty = Luik looks
    /// for a page with the service's name.
    var link = ""

    init(id: UUID = UUID(), title: String, hint: String = "", link: String = "") {
        self.id = id
        self.title = title
        self.hint = hint
        self.link = link
    }

    private enum CodingKeys: String, CodingKey { case id, title, hint, link }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decode(String.self, forKey: .title)
        hint = try c.decodeIfPresent(String.self, forKey: .hint) ?? ""
        link = try c.decodeIfPresent(String.self, forKey: .link) ?? ""
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
            repairSplitItemsIfNeeded()
        } else {
            lists = ChecklistStore.migratedFromSettings() ?? ChecklistStore.defaults
            Storage.save(lists, to: ChecklistStore.fileName)
        }
    }

    /// 0.15.0–0.15.3 split items on every comma, so "Input testing (injection, XSS, IDOR, upload)"
    /// became four items. Glue such runs back together once.
    private func repairSplitItemsIfNeeded() {
        func repaired(_ list: Checklist) -> Checklist {
            var copy = list
            copy.items = SettingsDefaults.mergingSplitParentheses(list.items, title: { $0.title }) { run -> ChecklistItem? in
                ChecklistItem(id: run[0].id,
                              title: run.map { $0.title }.joined(separator: ", "),
                              hint: run.map { $0.hint }.filter { !$0.isEmpty }.joined(separator: "\n"))
            }
            return copy
        }
        let fixed = ChecklistSet(host: repaired(lists.host), port: repaired(lists.port), services: lists.services.map(repaired))
        if fixed != lists {
            lists = fixed
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

    /// What an import file turned out to contain.
    enum ImportPayload {
        case set(ChecklistSet)        // a full export: system list, port list and service lists
        case lists([Checklist])       // one or more individual checklists
    }

    enum ImportMode {
        case replaceAll   // the file becomes the whole set
        case merge        // generic lists replaced, same-named service lists replaced, new ones appended
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    /// Everything, as the JSON Luik reads back with "Import".
    func exportJSON() -> Data? {
        try? ChecklistStore.encoder.encode(lists)
    }

    /// One or more checklists (a single list is written as an object, several as an array).
    func exportJSON(checklists: [Checklist]) -> Data? {
        if checklists.count == 1, let only = checklists.first {
            return try? ChecklistStore.encoder.encode(only)
        }
        return try? ChecklistStore.encoder.encode(checklists)
    }

    /// Reads a file written by "Export": a full set, a single checklist or an array of checklists,
    /// as JSON or as the Markdown export.
    static func decodeImport(_ data: Data) throws -> ImportPayload {
        let decoder = JSONDecoder()
        if let set = try? decoder.decode(ChecklistSet.self, from: data) { return .set(set) }
        if let list = try? decoder.decode(Checklist.self, from: data) { return .lists([list]) }
        if let lists = try? decoder.decode([Checklist].self, from: data) { return .lists(lists) }
        if let text = String(data: data, encoding: .utf8), let set = parseMarkdown(text) { return .set(set) }
        throw NSError(domain: "Luik", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not a checklist file exported by Luik (JSON or Markdown)."])
    }

    /// Imported lists get fresh ids, so they never collide with the ones already here.
    private static func freshIDs(_ checklist: Checklist) -> Checklist {
        var copy = checklist
        copy.id = UUID()
        copy.items = copy.items.map { item in
            var fresh = item
            fresh.id = UUID()
            return fresh
        }
        return copy
    }

    func importSet(_ imported: ChecklistSet, mode: ImportMode) {
        let host = ChecklistStore.freshIDs(imported.host)
        let port = ChecklistStore.freshIDs(imported.port)
        switch mode {
        case .replaceAll:
            lists = ChecklistSet(host: host, port: port, services: imported.services.map(ChecklistStore.freshIDs))
        case .merge:
            var services = lists.services
            for list in imported.services.map(ChecklistStore.freshIDs) {
                if let index = services.firstIndex(where: { $0.name.lowercased() == list.name.lowercased() }) {
                    services[index] = list
                } else {
                    services.append(list)
                }
            }
            lists = ChecklistSet(host: host, port: port, services: services)
        }
        scheduleSave()
        ActivityLog.shared.record(.action, "Checklists imported (\(imported.services.count) service list(s), \(mode == .replaceAll ? "replaced everything" : "merged"))", source: "Checklists")
    }

    /// Adds individual checklists: a list whose name matches the system or port list replaces
    /// that one; a same-named service list is replaced; anything else is appended.
    func importLists(_ imported: [Checklist]) {
        for list in imported.map(ChecklistStore.freshIDs) {
            let name = list.name.lowercased()
            if name == lists.host.name.lowercased() || name == "every system" {
                lists.host = Checklist(id: lists.host.id, name: lists.host.name, items: list.items)
            } else if name == lists.port.name.lowercased() || name == "every port" || name == "every port (fallback)" {
                lists.port = Checklist(id: lists.port.id, name: lists.port.name, items: list.items)
            } else if let index = lists.services.firstIndex(where: { $0.name.lowercased() == name }) {
                lists.services[index] = list
            } else {
                lists.services.append(list)
            }
        }
        scheduleSave()
        ActivityLog.shared.record(.action, "\(imported.count) checklist(s) imported", source: "Checklists")
    }

    // MARK: Markdown

    /// All checklists as Markdown — readable in a wiki or a repository, and importable again.
    func markdown() -> String {
        var out = "# Luik checklists\n\n"
        func render(_ list: Checklist, fixed: Bool) {
            out += "## \(list.name)\(list.enabled ? "" : " (disabled)")\n"
            if !fixed {
                out += "Applies to: \(list.keys.isEmpty ? "—" : list.keysText)\n"
            }
            out += "\n"
            for item in list.items {
                out += "- \(item.title)\n"
                let hint = item.hint.trimmingCharacters(in: .whitespacesAndNewlines)
                if !hint.isEmpty {
                    for line in hint.components(separatedBy: .newlines) {
                        out += "  > \(line)\n"
                    }
                }
            }
            out += "\n"
        }
        render(lists.host, fixed: true)
        render(lists.port, fixed: true)
        for list in lists.services { render(list, fixed: false) }
        return out
    }

    /// Reads the Markdown written by `markdown()`: "## Name", an optional "Applies to:" line,
    /// "- item" lines and "> hint" lines under an item. Lists named like the system/port lists
    /// become those; the rest are service lists. Nil when no "## " heading is found.
    static func parseMarkdown(_ text: String) -> ChecklistSet? {
        var host: Checklist? = nil
        var port: Checklist? = nil
        var services: [Checklist] = []
        var current: Checklist? = nil

        func finish() {
            guard var list = current else { return }
            list.items = list.items.map { item in
                var cleaned = item
                cleaned.hint = cleaned.hint.trimmingCharacters(in: .whitespacesAndNewlines)
                return cleaned
            }
            let name = list.name.lowercased()
            if host == nil, name == "every system" || name.hasPrefix("every system") {
                host = list
            } else if port == nil, name.hasPrefix("every port") {
                port = list
            } else {
                services.append(list)
            }
            current = nil
        }

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("## ") {
                finish()
                var name = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var enabled = true
                if name.lowercased().hasSuffix("(disabled)") {
                    enabled = false
                    name = String(name.dropLast("(disabled)".count)).trimmingCharacters(in: .whitespaces)
                }
                current = Checklist(name: name, items: [], enabled: enabled)
            } else if current != nil, line.lowercased().hasPrefix("applies to:") {
                let keys = String(line.dropFirst("applies to:".count))
                current?.keys = keys.trimmingCharacters(in: .whitespaces) == "—" ? [] : Checklist.parseKeys(keys)
            } else if current != nil, line.hasPrefix("- ") || line.hasPrefix("* ") {
                current?.items.append(ChecklistItem(title: String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)))
            } else if var list = current, line.hasPrefix(">"), let last = list.items.indices.last {
                let hintLine = String(line.dropFirst(1)).trimmingCharacters(in: .whitespaces)
                let existingHint = list.items[last].hint
                list.items[last].hint = existingHint.isEmpty ? hintLine : existingHint + "\n" + hintLine
                current = list
            }
        }
        finish()
        guard host != nil || port != nil || !services.isEmpty else { return nil }
        // Lists the file does not mention are kept as they are now.
        let existing = ChecklistStore.shared.lists
        return ChecklistSet(host: host ?? existing.host, port: port ?? existing.port,
                            services: services.isEmpty ? existing.services : services)
    }

    // MARK: - Hints

    /// The checklist item a task node was made from (matched by title, in the list of its service).
    func item(titled title: String, service: String?, port: Int?) -> ChecklistItem? {
        let needle = title.trimmingCharacters(in: .whitespaces).lowercased()
        let pool: [ChecklistItem]
        if let service, let port {
            pool = items(forService: service, port: port)
        } else {
            pool = hostItems
        }
        if let found = pool.first(where: { $0.title.trimmingCharacters(in: .whitespaces).lowercased() == needle }) { return found }
        for list in lists.services + [lists.port, lists.host] {
            if let found = list.items.first(where: { $0.title.trimmingCharacters(in: .whitespaces).lowercased() == needle }) { return found }
        }
        return nil
    }

    /// Items (with their list) whose link points at a library document.
    func items(linkedTo document: LibraryDocument) -> [(list: Checklist, item: ChecklistItem)] {
        var result: [(Checklist, ChecklistItem)] = []
        for list in [lists.host, lists.port] + lists.services {
            for item in list.items where !item.link.isEmpty && LibraryLink.resolve(item.link)?.id == document.id {
                result.append((list, item))
            }
        }
        return result
    }

    /// Fills $RHOST / $RPORT / $RURL (and $LHOST / $LPORT when set in One-liners) in a hint.
    static func resolve(_ hint: String, address: String, port: Int?, service: String? = nil) -> String {
        guard !hint.isEmpty else { return "" }
        // Same placeholders as the one-liners: $RHOST, $RPORT, $RURL, $LHOST, $LPORT.
        return SnippetStore.shared.resolve(hint, rhost: address, rport: port, service: service)
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
