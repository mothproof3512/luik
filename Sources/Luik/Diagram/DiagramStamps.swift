import Foundation

/// Small ready-made groups of nodes placed as one: an AD set, a web-app set, an identity set, a
/// cloud landing zone. Offsets are relative to the insert point, in diagram units.
struct DiagramStamp: Identifiable {
    struct Member {
        var key: String
        var kind: DiagramNodeKind
        var label: String
        var address: String = ""
        var dx: Double
        var dy: Double
    }

    struct Link {
        var from: String
        var to: String
        var label: String = ""
        var style: DiagramLinkStyle = .solid
        var directed = false
    }

    let id: String
    let name: String
    let summary: String
    let members: [Member]
    let links: [Link]
    /// Zone drawn around the members (nil = none).
    let zone: (name: String, color: String)?

    static let all: [DiagramStamp] = [
        DiagramStamp(id: "ad", name: "Active Directory set", summary: "Two domain controllers, AD CS, a file server and a workstation.",
                     members: [
                        Member(key: "dc1", kind: .domainController, label: "DC01", dx: 0, dy: 0),
                        Member(key: "dc2", kind: .domainController, label: "DC02", dx: 240, dy: 0),
                        Member(key: "ca", kind: .certificateAuthority, label: "AD CS", dx: 480, dy: 0),
                        Member(key: "fs", kind: .server, label: "File server", dx: 120, dy: 120),
                        Member(key: "ws", kind: .workstation, label: "Workstations", dx: 360, dy: 120),
                     ],
                     links: [Link(from: "dc1", to: "dc2", label: "replication", style: .dashed), Link(from: "dc1", to: "ca"),
                             Link(from: "ws", to: "dc1", label: "Kerberos", style: .dotted), Link(from: "ws", to: "fs")],
                     zone: ("Active Directory", "#BB6BD9")),
        DiagramStamp(id: "webapp", name: "Web application set", summary: "WAF, web application, API and database.",
                     members: [
                        Member(key: "waf", kind: .waf, label: "WAF", dx: 0, dy: 0),
                        Member(key: "app", kind: .webApp, label: "Web application", dx: 240, dy: 0),
                        Member(key: "api", kind: .api, label: "API", dx: 480, dy: 0),
                        Member(key: "db", kind: .database, label: "Database", dx: 720, dy: 0),
                     ],
                     links: [Link(from: "waf", to: "app", label: "443"), Link(from: "app", to: "api"), Link(from: "api", to: "db")],
                     zone: ("Application", "#E07A5F")),
        DiagramStamp(id: "identity", name: "Identity set", summary: "Identity provider with MFA, authorization server and directory.",
                     members: [
                        Member(key: "idp", kind: .identityProvider, label: "IdP (SSO)", dx: 0, dy: 0),
                        Member(key: "mfa", kind: .mfa, label: "MFA", dx: 0, dy: 120),
                        Member(key: "as", kind: .authorizationServer, label: "Authorization server", dx: 260, dy: 0),
                        Member(key: "dir", kind: .directory, label: "Directory", dx: 260, dy: 120),
                     ],
                     links: [Link(from: "idp", to: "mfa"), Link(from: "idp", to: "as", label: "code → token", directed: true), Link(from: "as", to: "dir")],
                     zone: ("Identity", "#BB6BD9")),
        DiagramStamp(id: "cloud", name: "Cloud landing zone", summary: "Hub firewall with VPN, a spoke with VMs and a cluster, managed database and storage.",
                     members: [
                        Member(key: "vpn", kind: .vpn, label: "VPN gateway", dx: 0, dy: 60),
                        Member(key: "fw", kind: .firewall, label: "Hub firewall", dx: 240, dy: 60),
                        Member(key: "vm", kind: .server, label: "VMs", dx: 480, dy: 0),
                        Member(key: "k8s", kind: .container, label: "Cluster", dx: 480, dy: 120),
                        Member(key: "db", kind: .database, label: "Managed DB", dx: 720, dy: 0),
                        Member(key: "st", kind: .objectStorage, label: "Storage", dx: 720, dy: 120),
                     ],
                     links: [Link(from: "vpn", to: "fw"), Link(from: "fw", to: "vm"), Link(from: "fw", to: "k8s"), Link(from: "k8s", to: "db"), Link(from: "k8s", to: "st")],
                     zone: ("Cloud", "#3E9BE8")),
        DiagramStamp(id: "dmz", name: "DMZ set", summary: "External firewall, reverse proxy and mail relay in a DMZ, internal firewall.",
                     members: [
                        Member(key: "fw1", kind: .firewall, label: "External firewall", dx: 0, dy: 60),
                        Member(key: "proxy", kind: .reverseProxy, label: "Reverse proxy", dx: 240, dy: 0),
                        Member(key: "mail", kind: .mailServer, label: "Mail relay", dx: 240, dy: 120),
                        Member(key: "fw2", kind: .firewall, label: "Internal firewall", dx: 480, dy: 60),
                     ],
                     links: [Link(from: "fw1", to: "proxy", label: "443"), Link(from: "fw1", to: "mail", label: "25"), Link(from: "proxy", to: "fw2"), Link(from: "mail", to: "fw2")],
                     zone: ("DMZ", "#F2994A")),
    ]
}

extension DiagramStore {
    /// Places a stamp with its top-left member at `point` (snapped), as one undo step.
    func addStamp(_ stamp: DiagramStamp, near point: CGPoint) {
        guard current != nil else { return }
        checkpoint()
        let originX = DiagramMetrics.snap(Double(point.x))
        let originY = DiagramMetrics.snap(Double(point.y))
        var ids: [String: UUID] = [:]
        var nodes: [DiagramNode] = []
        for member in stamp.members {
            let node = DiagramNode(kind: member.kind, label: member.label, address: member.address, x: originX + member.dx, y: originY + member.dy)
            ids[member.key] = node.id
            nodes.append(node)
        }
        let links = stamp.links.compactMap { link -> DiagramLink? in
            guard let a = ids[link.from], let b = ids[link.to] else { return nil }
            return DiagramLink(from: a, to: b, label: link.label, style: link.style, directed: link.directed)
        }
        var zone: DiagramZone?
        if let spec = stamp.zone {
            let minX = nodes.map { $0.x - $0.width / 2 }.min() ?? originX
            let maxX = nodes.map { $0.x + $0.width / 2 }.max() ?? originX
            let minY = nodes.map { $0.y }.min() ?? originY
            let maxY = nodes.map { $0.y }.max() ?? originY
            let half = Double(DiagramMetrics.nodeHeight) / 2
            zone = DiagramZone(name: spec.name, x: minX - 20, y: minY - half - Double(DiagramMetrics.zoneHeaderHeight) - 12,
                               width: maxX - minX + 40, height: maxY - minY + Double(DiagramMetrics.nodeHeight) + Double(DiagramMetrics.zoneHeaderHeight) + 24,
                               colorHex: spec.color)
        }
        update { diagram in
            if let zone { diagram.zones.append(zone) }
            diagram.nodes.append(contentsOf: nodes)
            diagram.links.append(contentsOf: links)
        }
        if let first = nodes.first { selection = .node(first.id) }
        ActivityLog.shared.record(.action, "Stamp added to diagram: \(stamp.name)", source: "Diagram")
    }
}
