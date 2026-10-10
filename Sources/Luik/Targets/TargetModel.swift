import Foundation
import Observation
import SwiftUI

enum NodeKind: String, Codable {
    case host      // a system (IP)
    case port      // a port on a system
    case task      // work-item node from the template
    case custom    // manually added node

    var symbol: String {
        switch self {
        case .host: return "desktopcomputer"
        case .port: return "network"
        case .task: return "checklist"
        case .custom: return "note.text"
        }
    }
}

enum NodeStatus: String, Codable, CaseIterable {
    case todo
    case inProgress
    case done
    case notApplicable

    var label: String {
        switch self {
        case .todo: return "To do"
        case .inProgress: return "In progress"
        case .done: return "Done"
        case .notApplicable: return "N/A"
        }
    }

    var symbol: String {
        switch self {
        case .todo: return "circle"
        case .inProgress: return "circle.lefthalf.filled"
        case .done: return "checkmark.circle.fill"
        case .notApplicable: return "minus.circle"
        }
    }

    var color: Color {
        switch self {
        case .todo: return .secondary
        case .inProgress: return .orange
        case .done: return .green
        case .notApplicable: return .gray
        }
    }

    var next: NodeStatus {
        switch self {
        case .todo: return .inProgress
        case .inProgress: return .done
        case .done: return .notApplicable
        case .notApplicable: return .todo
        }
    }

    /// Counts as "handled" in the progress figure.
    var isFinished: Bool {
        self == .done || self == .notApplicable
    }
}

/// One node in the targets tree: system → port → work-item nodes (→ custom sub-nodes).
@Observable
final class TargetNode: Identifiable, Codable {
    let id: UUID
    var kind: NodeKind
    var title: String
    var subtitle: String
    var status: NodeStatus
    var notes: String
    var children: [TargetNode]
    var address: String        // hosts only
    var portNumber: Int        // ports only
    var portProtocol: String   // ports only ("tcp"/"udp")

    init(id: UUID = UUID(),
         kind: NodeKind,
         title: String,
         subtitle: String = "",
         status: NodeStatus = .todo,
         notes: String = "",
         children: [TargetNode] = [],
         address: String = "",
         portNumber: Int = 0,
         portProtocol: String = "") {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.status = status
        self.notes = notes
        self.children = children
        self.address = address
        self.portNumber = portNumber
        self.portProtocol = portProtocol
    }

    // MARK: Codable (by hand, because @Observable rewrites the property storage)

    private enum CodingKeys: String, CodingKey {
        case id, kind, title, subtitle, status, notes, children, address, portNumber, portProtocol
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(NodeKind.self, forKey: .kind)
        title = try container.decode(String.self, forKey: .title)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle) ?? ""
        status = try container.decodeIfPresent(NodeStatus.self, forKey: .status) ?? .todo
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        children = try container.decodeIfPresent([TargetNode].self, forKey: .children) ?? []
        address = try container.decodeIfPresent(String.self, forKey: .address) ?? ""
        portNumber = try container.decodeIfPresent(Int.self, forKey: .portNumber) ?? 0
        portProtocol = try container.decodeIfPresent(String.self, forKey: .portProtocol) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(title, forKey: .title)
        try container.encode(subtitle, forKey: .subtitle)
        try container.encode(status, forKey: .status)
        try container.encode(notes, forKey: .notes)
        try container.encode(children, forKey: .children)
        try container.encode(address, forKey: .address)
        try container.encode(portNumber, forKey: .portNumber)
        try container.encode(portProtocol, forKey: .portProtocol)
    }

    // MARK: Helpers

    /// For SwiftUI's hierarchical List: nil means "no disclosure triangle".
    var outlineChildren: [TargetNode]? {
        children.isEmpty ? nil : children
    }

    /// (handled, total) over all work-item nodes under this node.
    var progress: (done: Int, total: Int) {
        var done = 0
        var total = 0
        collectProgress(in: self, done: &done, total: &total)
        return (done, total)
    }

    private func collectProgress(in node: TargetNode, done: inout Int, total: inout Int) {
        for child in node.children {
            if child.kind == .task || child.kind == .custom {
                total += 1
                if child.status.isFinished {
                    done += 1
                }
            }
            collectProgress(in: child, done: &done, total: &total)
        }
    }

    var progressText: String {
        let p = progress
        return p.total == 0 ? "" : "\(p.done)/\(p.total)"
    }

    /// Appends lines from nmap to the notes, skipping duplicates.
    func appendNmapInfo(_ lines: [String]) {
        let fresh = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !notes.contains($0) }
        guard !fresh.isEmpty else { return }
        if !notes.isEmpty && !notes.hasSuffix("\n") {
            notes += "\n"
        }
        if !notes.contains("## nmap") {
            notes += "## nmap\n"
        }
        notes += fresh.joined(separator: "\n") + "\n"
    }
}
