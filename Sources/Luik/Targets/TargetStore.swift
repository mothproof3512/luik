import Foundation
import Observation

struct ScanImportOptions {
    var includeNonOpen = false
    /// Add a node under the port/host for every scanner finding at or above this severity (nil = none).
    var nodeSeverity: Severity? = .low
    /// Also create/merge entries in the Findings tab for scanner findings at or above this severity (nil = none).
    var findingSeverity: Severity? = nil
}

struct ImportResult {
    var format: ScanFormat = .nmap
    var newHosts = 0
    var updatedHosts = 0
    var newPorts = 0
    var newNodes = 0
    var newFindings = 0
    var updatedFindings = 0
    var outOfScope: [String] = []

    var summary: String {
        if newHosts == 0 && updatedHosts == 0 {
            switch format {
            case .nmap: return "No hosts found. For normal nmap output the line \"Nmap scan report for …\" must be included."
            default: return "No hosts found in this \(format.label) output."
            }
        }
        var parts = ["\(newHosts) new host(s), \(updatedHosts) updated, \(newPorts) new port(s)"]
        if newNodes > 0 { parts.append("\(newNodes) scanner node(s)") }
        if newFindings + updatedFindings > 0 { parts.append("\(newFindings) new finding(s), \(updatedFindings) updated") }
        var text = parts.joined(separator: ", ") + "."
        if !outOfScope.isEmpty {
            text += " ⚠︎ Outside the engagement scope: " + outOfScope.prefix(6).joined(separator: ", ") + (outOfScope.count > 6 ? " …" : "")
        }
        return text
    }
}

/// The targets tree (systems → ports → work-item nodes), stored in targets.json.
@Observable
final class TargetStore {
    static let shared = TargetStore()

    private static let fileName = "targets.json"

    var hosts: [TargetNode] = []
    var selectedID: UUID? = nil
    @ObservationIgnored private var saver = Debouncer()

    init() {
        hosts = Storage.load([TargetNode].self, at: EngagementStore.shared.fileURL(TargetStore.fileName)) ?? []
        migrateLegacyNamesIfNeeded()
    }

    /// Called when the engagement changes.
    func reload() {
        saver.flush()
        hosts = Storage.load([TargetNode].self, at: EngagementStore.shared.fileURL(TargetStore.fileName)) ?? []
        selectedID = nil
        migrateLegacyNamesIfNeeded()
    }

    /// Where the current engagement's targets live (for "Show in Finder").
    var fileURL: URL { EngagementStore.shared.fileURL(TargetStore.fileName) }

    /// Versions up to 0.7 created work-item nodes with Dutch names; rename them once.
    private func migrateLegacyNamesIfNeeded() {
        var changed = false
        func visit(_ node: TargetNode) {
            if node.kind == .task, let english = SettingsDefaults.legacyTemplateNames[node.title] {
                node.title = english
                changed = true
            }
            node.children.forEach(visit)
        }
        hosts.forEach(visit)
        if changed {
            scheduleSave()
        }
    }

    // MARK: - Tree lookup

    var selectedNode: TargetNode? {
        find(selectedID)
    }

    func find(_ id: UUID?) -> TargetNode? {
        guard let id else { return nil }
        return find(id, in: hosts)
    }

    private func find(_ id: UUID, in nodes: [TargetNode]) -> TargetNode? {
        for node in nodes {
            if node.id == id { return node }
            if let found = find(id, in: node.children) { return found }
        }
        return nil
    }

    func parent(of id: UUID) -> TargetNode? {
        parent(of: id, in: hosts)
    }

    private func parent(of id: UUID, in nodes: [TargetNode]) -> TargetNode? {
        for node in nodes {
            if node.children.contains(where: { $0.id == id }) { return node }
            if let found = parent(of: id, in: node.children) { return found }
        }
        return nil
    }

    /// The host a node belongs to (or the node itself if it is a host).
    func host(of node: TargetNode) -> TargetNode? {
        var current: TargetNode? = node
        while let candidate = current {
            if candidate.kind == .host { return candidate }
            current = parent(of: candidate.id)
        }
        return nil
    }

    // MARK: - Checklists (work-item nodes)

    /// The nmap service name of a port node: the part of the subtitle before " — ".
    static func serviceName(of node: TargetNode) -> String {
        node.subtitle.components(separatedBy: " — ").first?.trimmingCharacters(in: .whitespaces) ?? ""
    }

    /// The checklist items a node gets: the system list for hosts, the matching service list
    /// (or the generic port list) for ports.
    private func checklistItems(for node: TargetNode) -> [ChecklistItem] {
        let checklists = ChecklistStore.shared
        return node.kind == .port ? checklists.items(forService: TargetStore.serviceName(of: node), port: node.portNumber) : checklists.hostItems
    }

    /// A work-item node for a checklist item, with the hint (RHOST/RPORT filled in) as starting notes.
    private func taskNode(for item: ChecklistItem, under parent: TargetNode) -> TargetNode {
        let address = host(of: parent)?.address ?? parent.address
        let port = parent.kind == .port ? parent.portNumber : nil
        return TargetNode(kind: .task, title: item.title, notes: ChecklistStore.resolve(item.hint, address: address, port: port))
    }

    /// Adds the work-item nodes from the checklist that are still missing (matched by title).
    @discardableResult
    func applyTemplate(to node: TargetNode) -> Int {
        guard node.kind == .host || node.kind == .port else { return 0 }
        let existing = Set(node.children.map { $0.title })
        var added = 0
        for item in checklistItems(for: node) where !existing.contains(item.title) {
            node.children.append(taskNode(for: item, under: node))
            added += 1
        }
        if added > 0 { scheduleSave() }
        return added
    }

    /// Adds missing checklist nodes to every host and port of the engagement (after editing the
    /// checklists). Returns the number of nodes added.
    @discardableResult
    func applyChecklistsEverywhere() -> Int {
        var added = 0
        for hostNode in hosts {
            added += applyTemplate(to: hostNode)
            for port in hostNode.children where port.kind == .port {
                added += applyTemplate(to: port)
            }
        }
        if added > 0 {
            ActivityLog.shared.record(.action, "Checklists applied to all targets: \(added) node(s) added", source: "Targets")
        }
        return added
    }

    // MARK: - Mutations

    @discardableResult
    func addHost(address: String, hostname: String = "") -> TargetNode {
        let cleaned = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = hosts.first(where: { $0.address == cleaned }) {
            selectedID = existing.id
            return existing
        }
        let node = TargetNode(kind: .host, title: cleaned, subtitle: hostname, address: cleaned)
        for item in ChecklistStore.shared.hostItems {
            node.children.append(taskNode(for: item, under: node))
        }
        hosts.append(node)
        selectedID = node.id
        scheduleSave()
        return node
    }

    @discardableResult
    func addPort(to host: TargetNode, number: Int, proto: String, description: String = "") -> TargetNode {
        if let existing = host.children.first(where: { $0.kind == .port && $0.portNumber == number && $0.portProtocol == proto }) {
            if !description.isEmpty { existing.subtitle = description }
            scheduleSave()
            return existing
        }
        let node = TargetNode(kind: .port, title: "\(number)/\(proto)", subtitle: description,
                              portNumber: number, portProtocol: proto)
        insertPortSorted(node, into: host)
        for item in checklistItems(for: node) {
            node.children.append(taskNode(for: item, under: node))
        }
        scheduleSave()
        return node
    }

    /// Ports come first, sorted, followed by the host's work-item nodes.
    private func insertPortSorted(_ port: TargetNode, into host: TargetNode) {
        var ports = host.children.filter { $0.kind == .port }
        let others = host.children.filter { $0.kind != .port }
        ports.append(port)
        ports.sort {
            if $0.portNumber != $1.portNumber { return $0.portNumber < $1.portNumber }
            return $0.portProtocol < $1.portProtocol
        }
        host.children = ports + others
    }

    @discardableResult
    func addChild(to parent: TargetNode, title: String = "New node") -> TargetNode {
        let node = TargetNode(kind: .custom, title: title)
        parent.children.append(node)
        selectedID = node.id
        scheduleSave()
        return node
    }

    func delete(_ node: TargetNode) {
        if let parent = parent(of: node.id) {
            parent.children.removeAll { $0.id == node.id }
        } else {
            hosts.removeAll { $0.id == node.id }
        }
        if selectedID == node.id || find(selectedID) == nil {
            selectedID = nil
        }
        scheduleSave()
    }

    func deleteAll() {
        hosts.removeAll()
        selectedID = nil
        scheduleSave()
    }

    // MARK: - Scan import (nmap, Nessus, nuclei, masscan)

    /// Imports nmap output (normal, -oG or -oX). Existing hosts/ports are updated, not duplicated.
    @discardableResult
    func importNmap(_ text: String, includeNonOpen: Bool) -> ImportResult {
        importScan(text, options: ScanImportOptions(includeNonOpen: includeNonOpen))
    }

    /// Imports any supported scanner output; the format is detected from the text.
    @discardableResult
    func importScan(_ text: String, options: ScanImportOptions) -> ImportResult {
        let parsed = ScanImport.parse(text)
        var result = ImportResult(format: parsed.format)
        importHosts(parsed.hosts, includeNonOpen: options.includeNonOpen, result: &result)

        if let threshold = options.nodeSeverity {
            for item in parsed.findings where item.severity.order <= threshold.order {
                if addScannerNode(for: item) { result.newNodes += 1 }
            }
        }
        if let threshold = options.findingSeverity, parsed.format.hasFindings {
            mergeFindings(parsed.findings.filter { $0.severity.order <= threshold.order }, result: &result)
        }

        let engagement = EngagementStore.shared
        if engagement.hasScope {
            result.outOfScope = parsed.hosts.map { $0.address }.filter { engagement.scopeStatus(of: $0).isProblem }
        }

        if selectedID == nil, let first = hosts.first {
            selectedID = first.id
        }
        scheduleSave()
        if result.newHosts + result.updatedHosts > 0 {
            let addresses = parsed.hosts.map { $0.address }.prefix(8).joined(separator: ", ")
            let name = parsed.format == .nmap ? "nmap" : parsed.format.label.components(separatedBy: " ").first ?? "scan"
            ActivityLog.shared.record(.import, "\(name) import: \(result.summary) \(addresses)\(parsed.hosts.count > 8 ? " …" : "")", source: "Targets")
        }
        return result
    }

    private func importHosts(_ parsed: [ParsedHost], includeNonOpen: Bool, result: inout ImportResult) {
        for parsedHost in parsed {
            let hostNode: TargetNode
            if let existing = hosts.first(where: { $0.address == parsedHost.address }) {
                hostNode = existing
                result.updatedHosts += 1
            } else {
                hostNode = addHost(address: parsedHost.address, hostname: parsedHost.hostname)
                result.newHosts += 1
            }
            if hostNode.subtitle.isEmpty && !parsedHost.hostname.isEmpty {
                hostNode.subtitle = parsedHost.hostname
            }

            var info: [String] = []
            if !parsedHost.hostname.isEmpty { info.append("Hostname: \(parsedHost.hostname)") }
            if !parsedHost.os.isEmpty { info.append(parsedHost.os) }
            if !parsedHost.mac.isEmpty { info.append("MAC: \(parsedHost.mac)") }
            info.append(contentsOf: parsedHost.extra)
            hostNode.appendNmapInfo(info)

            for port in parsedHost.ports {
                let state = port.state.lowercased()
                guard state == "open" || (includeNonOpen && !state.hasPrefix("closed")) else { continue }

                var description = [port.service, port.version].filter { !$0.isEmpty }.joined(separator: " — ")
                if state != "open" {
                    description += description.isEmpty ? "[\(state)]" : "  [\(state)]"
                }

                let existedBefore = hostNode.children.contains {
                    $0.kind == .port && $0.portNumber == port.number && $0.portProtocol == port.proto
                }
                let portNode = addPort(to: hostNode, number: port.number, proto: port.proto, description: description)
                if !existedBefore { result.newPorts += 1 }
                portNode.appendNmapInfo(port.scripts)
            }
        }
    }

    /// Adds "[Nessus] Plugin name" / "[nuclei] Template name" under the port (or the host for
    /// port-less items). Returns false when the node was already there (its notes are kept).
    @discardableResult
    func addScannerNode(for item: ScanFinding) -> Bool {
        guard let hostNode = hosts.first(where: { $0.address == item.address }) else { return false }
        var parent: TargetNode = hostNode
        if item.port > 0 {
            parent = addPort(to: hostNode, number: item.port, proto: item.proto)
        }
        let title = "[\(item.scanner)] \(item.title)"
        if let existing = parent.children.first(where: { $0.title == title }) {
            if existing.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                existing.notes = item.notesText
            }
            return false
        }
        let node = TargetNode(kind: .custom, title: title, subtitle: item.severity.label, notes: item.notesText)
        // Scanner nodes go after the ports/work items of the parent, in severity order.
        let index = parent.children.firstIndex { $0.kind == .custom && $0.title.hasPrefix("[") && severityOrder($0.subtitle) > item.severity.order } ?? parent.children.count
        parent.children.insert(node, at: index)
        return true
    }

    private func severityOrder(_ label: String) -> Int {
        Severity.parse(label)?.order ?? 99
    }

    /// One Findings entry per plugin/template, with every affected host:port; existing entries
    /// (same source id) get the new addresses added.
    private func mergeFindings(_ items: [ScanFinding], result: inout ImportResult) {
        let store = FindingsStore.shared
        var groups: [String: [ScanFinding]] = [:]
        var order: [String] = []
        for item in items {
            if groups[item.sourceID] == nil { order.append(item.sourceID) }
            groups[item.sourceID, default: []].append(item)
        }
        for key in order {
            guard let group = groups[key], let first = group.first else { continue }
            let affected = group.map { $0.affectedLabel }
            if let existing = store.finding(withSource: key) {
                let before = existing.affected.count
                store.addAffected(affected, to: existing.id)
                if (store.findings.first { $0.id == existing.id }?.affected.count ?? before) > before { result.updatedFindings += 1 }
                continue
            }
            var finding = Finding(title: first.title, severity: group.map { $0.severity }.min() ?? first.severity)
            finding.source = key
            var seen: Set<String> = []
            finding.affected = affected.filter { seen.insert($0).inserted }
            if CVSS31.parse(first.cvssVector) != nil {
                finding.cvssVector = first.cvssVector.replacingOccurrences(of: "CVSS:3.0", with: "CVSS:3.1")
            }
            var description = first.synopsis
            if !first.description.isEmpty { description += (description.isEmpty ? "" : "\n\n") + first.description }
            finding.description = description
            finding.recommendation = first.solution
            var references = first.references
            references.append(contentsOf: first.cves.map { "https://nvd.nist.gov/vuln/detail/\($0)" })
            finding.references = references.joined(separator: "\n")
            let evidence = group.compactMap { item -> String? in
                let output = item.output.trimmingCharacters(in: .whitespacesAndNewlines)
                let location = item.matchedAt.isEmpty ? item.affectedLabel : item.matchedAt
                return output.isEmpty ? (item.matchedAt.isEmpty ? nil : location) : "\(location):\n\(output.prefix(1500))"
            }
            finding.evidence = evidence.prefix(20).joined(separator: "\n\n")
            store.add(finding, select: false)
            result.newFindings += 1
        }
        if result.newFindings + result.updatedFindings > 0 {
            ActivityLog.shared.record(.import, "\(result.newFindings) finding(s) created and \(result.updatedFindings) updated from \(result.format.label)", source: "Findings")
        }
    }

    // MARK: - Export

    func markdown() -> String {
        var out = "# Targets\n\n"
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        out += "_Exported from Luik on \(formatter.string(from: Date()))_\n\n"
        for host in hosts {
            render(host, level: 2, into: &out)
        }
        return out
    }

    private func render(_ node: TargetNode, level: Int, into out: inout String) {
        let heading = String(repeating: "#", count: min(level, 6))
        var title = node.title
        if !node.subtitle.isEmpty { title += " — \(node.subtitle)" }
        out += "\(heading) \(title)\n\n"
        var meta = "Status: \(node.status.label)"
        if node.kind == .host || node.kind == .port {
            let p = node.progress
            if p.total > 0 { meta += " · Progress: \(p.done)/\(p.total)" }
        }
        out += meta + "\n\n"
        let notes = node.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty {
            out += notes + "\n\n"
        }
        for child in node.children {
            render(child, level: level + 1, into: &out)
        }
    }

    // MARK: - Saving

    func scheduleSave() {
        let url = EngagementStore.shared.fileURL(TargetStore.fileName)
        saver.call { [weak self] in
            guard let self else { return }
            Storage.save(self.hosts, at: url)
        }
    }

    func flush() {
        saver.flush()
    }
}
