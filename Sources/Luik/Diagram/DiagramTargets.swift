import AppKit
import Foundation

/// Diagram nodes and Targets hosts are matched on address; this is the glue in both directions.
enum DiagramTargets {
    /// The Targets host a diagram node stands for (address, or the host's name as the label).
    static func host(for node: DiagramNode) -> TargetNode? {
        let address = node.address.trimmingCharacters(in: .whitespaces)
        let hosts = TargetStore.shared.hosts
        if !address.isEmpty, let host = hosts.first(where: { $0.address == address }) { return host }
        if !address.isEmpty, let host = hosts.first(where: { !$0.subtitle.isEmpty && $0.subtitle.caseInsensitiveCompare(address) == .orderedSame }) { return host }
        let label = node.label.trimmingCharacters(in: .whitespaces)
        if !label.isEmpty, let host = hosts.first(where: { $0.address == label || (!$0.subtitle.isEmpty && $0.subtitle.caseInsensitiveCompare(label) == .orderedSame) }) { return host }
        return nil
    }

    /// Ports and findings of the host, as badges for the card.
    static func badges(for node: DiagramNode) -> [DiagramBadge] {
        guard let host = host(for: node) else { return [] }
        var badges: [DiagramBadge] = []
        let ports = host.children.filter { $0.kind == .port }.count
        if ports > 0 { badges.append(DiagramBadge(text: "\(ports) port\(ports == 1 ? "" : "s")")) }
        let findings = FindingsStore.shared.findings.filter { finding in
            finding.status != .falsePositive && finding.affected.contains { $0 == host.address || $0.hasPrefix(host.address + ":") }
        }
        if !findings.isEmpty {
            let worst = findings.map { $0.severity }.min() ?? .info
            badges.append(DiagramBadge(text: "\(findings.count) finding\(findings.count == 1 ? "" : "s")", warning: worst <= .high))
        }
        return badges
    }

    static func isCurrentTarget(_ node: DiagramNode) -> Bool {
        let target = SnippetStore.shared.target.trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty else { return false }
        return node.address.trimmingCharacters(in: .whitespaces) == target || host(for: node)?.address == target
    }

    /// Selects the host in Targets and opens the tab.
    static func openInTargets(_ node: DiagramNode) {
        guard let host = host(for: node) else { return }
        TargetStore.shared.selectedID = host.id
        UIState.shared.open(.targets)
    }

    /// The diagram (and node) that shows a Targets host, if any.
    static func diagramNode(for host: TargetNode) -> (diagram: Diagram, node: DiagramNode)? {
        let address = host.address.trimmingCharacters(in: .whitespaces)
        let store = DiagramStore.shared
        let ordered = ([store.current].compactMap { $0 }) + store.diagrams.filter { $0.id != store.currentID }
        for diagram in ordered {
            if let node = diagram.nodes.first(where: { $0.address.trimmingCharacters(in: .whitespaces) == address && !address.isEmpty }) {
                return (diagram, node)
            }
        }
        return nil
    }

    /// Shows the host's node in the Diagram tab; adds it to the current diagram when no diagram has it.
    static func showInDiagram(_ host: TargetNode) {
        let store = DiagramStore.shared
        if let found = diagramNode(for: host) {
            if store.currentID != found.diagram.id { store.select(found.diagram.id) }
            store.selection = .node(found.node.id)
            store.insertPoint = CGPoint(x: found.node.x, y: found.node.y)
        } else {
            if store.current == nil { _ = store.newDiagram(name: "Network") }
            _ = store.addHostsFromTargets()
            if let found = diagramNode(for: host) { store.selection = .node(found.node.id) }
        }
        UIState.shared.open(.diagram)
    }
}
