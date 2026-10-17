import AppKit
import Foundation
import Observation
import SwiftUI

/// What a box in the diagram stands for: drives its icon, colour and the abbreviation used in SVG.
enum DiagramNodeKind: String, Codable, CaseIterable, Identifiable {
    case internet
    case cloud
    case attacker
    case firewall
    case vpn
    case router
    case switchDevice = "switch"
    case loadBalancer
    case accessPoint
    case server
    case webServer
    case database
    case domainController
    case mailServer
    case workstation
    case laptop
    case mobile
    case printer
    case iot
    // Web application
    case user
    case cdn
    case waf
    case reverseProxy
    case webApp
    case api
    case microservice
    case messageQueue
    case cache
    case objectStorage
    case container
    case serverless
    case thirdParty
    // Identity and authentication
    case identityProvider
    case authorizationServer
    case mfa
    case directory
    case sessionStore
    case secretsVault
    case certificateAuthority
    case generic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .internet: return "Internet"
        case .cloud: return "Cloud"
        case .attacker: return "Attacker"
        case .firewall: return "Firewall"
        case .vpn: return "VPN gateway"
        case .router: return "Router"
        case .switchDevice: return "Switch"
        case .loadBalancer: return "Load balancer"
        case .accessPoint: return "Wi-Fi access point"
        case .server: return "Server"
        case .webServer: return "Web server"
        case .database: return "Database"
        case .domainController: return "Domain controller"
        case .mailServer: return "Mail server"
        case .workstation: return "Workstation"
        case .laptop: return "Laptop"
        case .mobile: return "Mobile"
        case .printer: return "Printer"
        case .iot: return "IoT / OT device"
        case .user: return "User / browser"
        case .cdn: return "CDN"
        case .waf: return "WAF"
        case .reverseProxy: return "Reverse proxy"
        case .webApp: return "Web application"
        case .api: return "API"
        case .microservice: return "Service"
        case .messageQueue: return "Message queue"
        case .cache: return "Cache"
        case .objectStorage: return "Object storage"
        case .container: return "Container / cluster"
        case .serverless: return "Function (serverless)"
        case .thirdParty: return "Third-party API"
        case .identityProvider: return "Identity provider (SSO)"
        case .authorizationServer: return "Authorization server (OAuth / OIDC)"
        case .mfa: return "MFA"
        case .directory: return "Directory (LDAP)"
        case .sessionStore: return "Session / token store"
        case .secretsVault: return "Secrets vault"
        case .certificateAuthority: return "Certificate authority"
        case .generic: return "Other"
        }
    }

    var symbol: String {
        switch self {
        case .internet: return "globe"
        case .cloud: return "cloud.fill"
        case .attacker: return "person.fill.viewfinder"
        case .firewall: return "flame.fill"
        case .vpn: return "lock.shield.fill"
        case .router: return "arrow.triangle.branch"
        case .switchDevice: return "rectangle.connected.to.line.below"
        case .loadBalancer: return "arrow.left.arrow.right"
        case .accessPoint: return "wifi"
        case .server: return "server.rack"
        case .webServer: return "network"
        case .database: return "cylinder.split.1x2.fill"
        case .domainController: return "person.badge.key.fill"
        case .mailServer: return "envelope.fill"
        case .workstation: return "desktopcomputer"
        case .laptop: return "laptopcomputer"
        case .mobile: return "iphone"
        case .printer: return "printer.fill"
        case .iot: return "sensor.fill"
        case .user: return "person.crop.circle"
        case .cdn: return "globe.badge.chevron.backward"
        case .waf: return "shield.lefthalf.filled"
        case .reverseProxy: return "arrow.triangle.swap"
        case .webApp: return "macwindow"
        case .api: return "curlybraces"
        case .microservice: return "gearshape.2.fill"
        case .messageQueue: return "tray.full.fill"
        case .cache: return "bolt.fill"
        case .objectStorage: return "archivebox.fill"
        case .container: return "shippingbox.fill"
        case .serverless: return "function"
        case .thirdParty: return "link.circle.fill"
        case .identityProvider: return "person.badge.shield.checkmark.fill"
        case .authorizationServer: return "key.fill"
        case .mfa: return "lock.rotation"
        case .directory: return "person.3.fill"
        case .sessionStore: return "ticket.fill"
        case .secretsVault: return "lock.square.stack.fill"
        case .certificateAuthority: return "checkmark.seal.fill"
        case .generic: return "square.dashed"
        }
    }

    /// Short label for exports that cannot draw the icon (SVG).
    var abbreviation: String {
        switch self {
        case .internet: return "WAN"
        case .cloud: return "CLD"
        case .attacker: return "ATK"
        case .firewall: return "FW"
        case .vpn: return "VPN"
        case .router: return "RT"
        case .switchDevice: return "SW"
        case .loadBalancer: return "LB"
        case .accessPoint: return "AP"
        case .server: return "SRV"
        case .webServer: return "WEB"
        case .database: return "DB"
        case .domainController: return "DC"
        case .mailServer: return "MX"
        case .workstation: return "PC"
        case .laptop: return "LT"
        case .mobile: return "MOB"
        case .printer: return "PRN"
        case .iot: return "IoT"
        case .user: return "USR"
        case .cdn: return "CDN"
        case .waf: return "WAF"
        case .reverseProxy: return "RP"
        case .webApp: return "APP"
        case .api: return "API"
        case .microservice: return "SVC"
        case .messageQueue: return "MQ"
        case .cache: return "$"
        case .objectStorage: return "S3"
        case .container: return "K8S"
        case .serverless: return "FN"
        case .thirdParty: return "3RD"
        case .identityProvider: return "IdP"
        case .authorizationServer: return "AS"
        case .mfa: return "MFA"
        case .directory: return "DIR"
        case .sessionStore: return "SES"
        case .secretsVault: return "KV"
        case .certificateAuthority: return "CA"
        case .generic: return "•"
        }
    }

    /// Group in the Add menu.
    var group: String {
        switch self {
        case .internet, .cloud, .attacker: return "Outside"
        case .firewall, .vpn: return "Perimeter"
        case .router, .switchDevice, .loadBalancer, .accessPoint: return "Network"
        case .server, .webServer, .database, .domainController, .mailServer: return "Servers"
        case .user, .cdn, .waf, .reverseProxy, .webApp, .api, .microservice, .messageQueue, .cache, .objectStorage, .container, .serverless, .thirdParty: return "Web application"
        case .identityProvider, .authorizationServer, .mfa, .directory, .sessionStore, .secretsVault, .certificateAuthority: return "Identity & auth"
        case .workstation, .laptop, .mobile, .printer, .iot: return "Clients"
        case .generic: return "Other"
        }
    }

    static let groups = ["Outside", "Perimeter", "Network", "Servers", "Web application", "Identity & auth", "Clients", "Other"]

    /// Colour of the icon disc (hex, also used in SVG and draw.io).
    var hex: String {
        switch group {
        case "Outside": return self == .attacker ? "#E5484D" : "#3E9BE8"
        case "Perimeter": return "#F2994A"
        case "Network": return "#2F80ED"
        case "Servers": return self == .database ? "#27AE60" : (self == .domainController ? "#BB6BD9" : "#8E7CF0")
        case "Web application":
            switch self {
            case .user: return "#22B5A6"
            case .waf, .cdn, .reverseProxy: return "#F2994A"
            case .cache, .messageQueue, .objectStorage, .sessionStore: return "#27AE60"
            case .thirdParty: return "#3E9BE8"
            default: return "#E07A5F"
            }
        case "Identity & auth": return self == .secretsVault || self == .certificateAuthority ? "#8E7CF0" : "#BB6BD9"
        case "Clients": return "#22B5A6"
        default: return "#8A8F98"
        }
    }

    var color: Color { Color(nsColor: NSColor(hex: hex)) }

    /// A kind from free text (a draw.io style, a Mermaid label, a service list).
    static func guess(from text: String) -> DiagramNodeKind {
        let lower = text.lowercased()
        let rules: [(DiagramNodeKind, [String])] = [
            (.attacker, ["attacker", "kali", "pentest", "aanvaller"]),
            (.waf, ["waf", "cloudflare waf", "akamai", "imperva", "modsecurity"]),
            (.cdn, ["cdn", "cloudfront", "fastly", "front door"]),
            (.identityProvider, ["identity provider", "idp", "sso", "entra", "azure ad", "okta", "keycloak", "adfs", "saml", "ping identity", "auth0"]),
            (.authorizationServer, ["authorization server", "oauth", "oidc", "openid", "token service", "sts"]),
            (.mfa, ["mfa", "2fa", "totp", "authenticator", "duo"]),
            (.directory, ["ldap", "directory", "freeipa"]),
            (.secretsVault, ["vault", "secrets", "key vault", "kms", "hsm"]),
            (.certificateAuthority, ["certificate authority", "pki", "ca"]),
            (.sessionStore, ["session", "token store", "jwt"]),
            (.reverseProxy, ["reverse proxy", "traefik", "envoy", "api gateway", "ingress", "kong"]),
            (.api, ["api", "rest", "graphql", "grpc", "backend"]),
            (.messageQueue, ["queue", "kafka", "rabbitmq", "mq", "pubsub", "sqs", "bus"]),
            (.cache, ["cache", "redis", "memcached"]),
            (.objectStorage, ["bucket", "s3", "blob", "object storage", "minio"]),
            (.container, ["kubernetes", "k8s", "docker", "container", "cluster", "pod", "aks", "eks"]),
            (.serverless, ["lambda", "function", "serverless", "faas"]),
            (.microservice, ["microservice", "service", "worker"]),
            (.thirdParty, ["third party", "third-party", "payment", "psp", "external api", "partner"]),
            (.webApp, ["web app", "webapp", "frontend", "spa", "react", "angular", "portal", "application"]),
            (.user, ["browser", "end user", "customer", "visitor"]),
            (.firewall, ["firewall", "fortigate", "palo alto", "pfsense", "opnsense", "asa", "checkpoint", "fw"]),
            (.vpn, ["vpn", "ipsec", "wireguard", "openvpn", "anyconnect"]),
            (.loadBalancer, ["load balancer", "loadbalancer", "f5", "haproxy", "big-ip", "lb"]),
            (.router, ["router", "gateway", "edge", "rtr"]),
            (.switchDevice, ["switch", "core", "vlan"]),
            (.accessPoint, ["access point", "wifi", "wi-fi", "wireless", "wlan", "ap"]),
            (.domainController, ["domain controller", "active directory", "dc0", "dc1", "kerberos", "ldap", "dc"]),
            (.database, ["database", "mssql", "mysql", "postgres", "oracle", "mongodb", "sql", "db", "cylinder"]),
            (.mailServer, ["mail", "exchange", "smtp", "mx"]),
            (.webServer, ["web", "http", "nginx", "apache", "iis", "proxy"]),
            (.cloud, ["cloud", "azure", "aws", "gcp", "saas"]),
            (.internet, ["internet", "wan", "isp"]),
            (.printer, ["printer", "print"]),
            (.mobile, ["mobile", "phone", "iphone", "android"]),
            (.laptop, ["laptop", "notebook"]),
            (.workstation, ["workstation", "desktop", "client", "pc", "user"]),
            (.iot, ["iot", "ot", "scada", "plc", "camera", "sensor"]),
            (.server, ["server", "srv", "host", "vm", "linux", "windows"]),
        ]
        let words = Set(lower.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "-" }).map(String.init))
        for (kind, keys) in rules {
            for key in keys {
                // Short keys must be whole words ("ap" is not "apache"); longer ones may be part of a word.
                if key.count <= 3 ? words.contains(key) : lower.contains(key) { return kind }
            }
        }
        return .generic
    }
}

enum DiagramLinkStyle: String, Codable, CaseIterable, Identifiable {
    case solid
    case dashed
    case dotted

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var dash: [CGFloat] {
        switch self {
        case .solid: return []
        case .dashed: return [8, 5]
        case .dotted: return [2, 4]
        }
    }
}

struct DiagramNode: Identifiable, Codable, Hashable {
    var id = UUID()
    var kind: DiagramNodeKind
    var label: String
    /// IP address, range or hostname shown under the label.
    var address: String = ""
    var notes: String = ""
    /// Centre, in diagram units.
    var x: Double
    var y: Double
}

struct DiagramLink: Identifiable, Codable, Hashable {
    var id = UUID()
    var from: UUID
    var to: UUID
    var label: String = ""
    var style: DiagramLinkStyle = .solid
    var directed: Bool = false
}

/// A network segment drawn behind its nodes (DMZ, LAN, VLAN 20, Azure VNet, …).
struct DiagramZone: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var colorHex: String = "#2F80ED"

    var color: Color { Color(nsColor: NSColor(hex: colorHex)) }

    func contains(x px: Double, y py: Double) -> Bool {
        px >= x && px <= x + width && py >= y && py <= y + height
    }

    static let palette = ["#2F80ED", "#27AE60", "#F2994A", "#E5484D", "#BB6BD9", "#22B5A6", "#8A8F98"]
}

struct Diagram: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var nodes: [DiagramNode] = []
    var links: [DiagramLink] = []
    var zones: [DiagramZone] = []
    var updatedAt = Date()

    func node(_ id: UUID) -> DiagramNode? { nodes.first { $0.id == id } }

    /// Bounding box of everything, in diagram units.
    var bounds: CGRect {
        var rect: CGRect? = nil
        for node in nodes {
            let r = CGRect(x: CGFloat(node.x) - DiagramMetrics.nodeWidth / 2, y: CGFloat(node.y) - DiagramMetrics.nodeHeight / 2,
                           width: DiagramMetrics.nodeWidth, height: DiagramMetrics.nodeHeight)
            rect = rect.map { $0.union(r) } ?? r
        }
        for zone in zones {
            let r = CGRect(x: zone.x, y: zone.y, width: zone.width, height: zone.height)
            rect = rect.map { $0.union(r) } ?? r
        }
        return rect ?? CGRect(x: 0, y: 0, width: 400, height: 300)
    }

    /// The smallest zone whose rectangle holds the node's centre.
    func zone(of node: DiagramNode) -> DiagramZone? {
        zones.filter { $0.contains(x: node.x, y: node.y) }.min { $0.width * $0.height < $1.width * $1.height }
    }
}

enum DiagramMetrics {
    static let nodeWidth: CGFloat = 156
    static let nodeHeight: CGFloat = 54
    static let grid: Double = 20
    static let zoneHeaderHeight: CGFloat = 26

    static func snap(_ value: Double) -> Double {
        (value / grid).rounded() * grid
    }
}

/// What is selected on the canvas.
enum DiagramSelection: Hashable {
    case node(UUID)
    case link(UUID)
    case zone(UUID)
}

/// The diagrams of the engagement, in diagrams.json in its folder.
@Observable
final class DiagramStore {
    static let shared = DiagramStore()

    private static let fileName = "diagrams.json"
    private static let maxUndo = 60

    var diagrams: [Diagram] = []
    var currentID: UUID?
    var selection: DiagramSelection?
    var connectMode = false
    /// First node clicked in connect mode.
    var connectFrom: UUID?
    var zoom: Double = 1.0
    /// Changes whenever the undo stack does (so the Undo button follows).
    var undoDepth = 0
    /// Where the last click on the canvas was (diagram units): new nodes go there.
    var insertPoint: CGPoint?
    /// Size of the visible canvas, for Fit.
    @ObservationIgnored var viewportSize: CGSize = .zero

    @ObservationIgnored private var saver = Debouncer()
    @ObservationIgnored private var undoStack: [Diagram] = []

    init() {
        load()
    }

    func reload() {
        saver.flush()
        load()
    }

    private func load() {
        diagrams = Storage.load([Diagram].self, at: EngagementStore.shared.fileURL(DiagramStore.fileName)) ?? []
        currentID = diagrams.first?.id
        selection = nil
        connectFrom = nil
        insertPoint = nil
        undoStack = []
        undoDepth = 0
    }

    /// Zoom so everything fits in the visible canvas (between 40 % and 200 %).
    func fitToViewport() {
        guard let current, viewportSize.width > 50, viewportSize.height > 50 else { return }
        let bounds = current.bounds
        let scale = min(viewportSize.width / (bounds.maxX + 60), viewportSize.height / (bounds.maxY + 60))
        zoom = min(2.0, max(0.4, (Double(scale) * 20).rounded(.down) / 20))
    }

    var current: Diagram? {
        diagrams.first { $0.id == currentID }
    }

    private var currentIndex: Int? {
        diagrams.firstIndex { $0.id == currentID }
    }

    // MARK: - Diagrams

    @discardableResult
    func newDiagram(name: String = "Network", sample: Bool = false, webApp: Bool = false) -> Diagram {
        var diagram = Diagram(name: uniqueName(name))
        if webApp {
            diagram = DiagramStore.sampleWebApp(named: diagram.name)
        } else if sample {
            diagram = DiagramStore.sampleDiagram(named: diagram.name)
        }
        diagrams.append(diagram)
        select(diagram.id)
        scheduleSave()
        return diagram
    }

    /// A new diagram from one of the built-in templates (web application set-ups, authentication
    /// flows, network layouts).
    @discardableResult
    func newDiagram(from template: DiagramTemplate) -> Diagram {
        let diagram = template.build(uniqueName(template.name))
        diagrams.append(diagram)
        select(diagram.id)
        scheduleSave()
        ActivityLog.shared.record(.action, "Diagram created from template: \(template.name)", source: "Diagram")
        return diagram
    }

    func add(_ diagram: Diagram) {
        var copy = diagram
        copy.name = uniqueName(diagram.name)
        diagrams.append(copy)
        select(copy.id)
        scheduleSave()
    }

    func select(_ id: UUID) {
        currentID = id
        selection = nil
        connectFrom = nil
        insertPoint = nil
        undoStack = []
        undoDepth = 0
    }

    func rename(_ id: UUID, to name: String) {
        guard let index = diagrams.firstIndex(where: { $0.id == id }) else { return }
        diagrams[index].name = name
        scheduleSave()
    }

    func duplicateCurrent() {
        guard let current else { return }
        var copy = current
        copy.id = UUID()
        copy.name = uniqueName(current.name + " copy")
        // Fresh ids, links remapped.
        var map: [UUID: UUID] = [:]
        copy.nodes = copy.nodes.map { node in
            var n = node
            n.id = UUID()
            map[node.id] = n.id
            return n
        }
        copy.links = copy.links.compactMap { link in
            guard let from = map[link.from], let to = map[link.to] else { return nil }
            var l = link
            l.id = UUID()
            l.from = from
            l.to = to
            return l
        }
        copy.zones = copy.zones.map { zone in
            var z = zone
            z.id = UUID()
            return z
        }
        diagrams.append(copy)
        select(copy.id)
        scheduleSave()
    }

    func deleteCurrent() {
        guard let index = currentIndex else { return }
        diagrams.remove(at: index)
        currentID = diagrams.first?.id
        selection = nil
        undoStack = []
        undoDepth = 0
        scheduleSave()
    }

    private func uniqueName(_ base: String) -> String {
        let names = Set(diagrams.map { $0.name })
        guard names.contains(base) else { return base }
        var counter = 2
        while names.contains("\(base) \(counter)") { counter += 1 }
        return "\(base) \(counter)"
    }

    // MARK: - Editing

    /// Applies a change to the current diagram and saves it (debounced).
    func update(_ change: (inout Diagram) -> Void) {
        guard let index = currentIndex else { return }
        change(&diagrams[index])
        diagrams[index].updatedAt = Date()
        scheduleSave()
    }

    /// Remember the current state, so Undo can return to it. Call before a change.
    func checkpoint() {
        guard let current else { return }
        undoStack.append(current)
        if undoStack.count > DiagramStore.maxUndo { undoStack.removeFirst() }
        undoDepth = undoStack.count
    }

    func undo() {
        guard let previous = undoStack.popLast(), let index = diagrams.firstIndex(where: { $0.id == previous.id }) else { return }
        diagrams[index] = previous
        undoDepth = undoStack.count
        if let selection, !exists(selection) { self.selection = nil }
        scheduleSave()
    }

    private func exists(_ selection: DiagramSelection) -> Bool {
        guard let current else { return false }
        switch selection {
        case .node(let id): return current.nodes.contains { $0.id == id }
        case .link(let id): return current.links.contains { $0.id == id }
        case .zone(let id): return current.zones.contains { $0.id == id }
        }
    }

    /// A free spot near the given point (or the centre of the visible area).
    private func freeSpot(near point: CGPoint) -> CGPoint {
        guard let current else { return point }
        var cx = DiagramMetrics.snap(Double(point.x))
        var cy = DiagramMetrics.snap(Double(point.y))
        let width = Double(DiagramMetrics.nodeWidth)
        let height = Double(DiagramMetrics.nodeHeight) + 10
        var attempts = 0
        while attempts < 40, current.nodes.contains(where: { abs($0.x - cx) < width && abs($0.y - cy) < height }) {
            cy += 80
            if attempts % 6 == 5 {
                cx += 200
                cy = DiagramMetrics.snap(Double(point.y))
            }
            attempts += 1
        }
        return CGPoint(x: cx, y: cy)
    }

    @discardableResult
    func addNode(_ kind: DiagramNodeKind, near point: CGPoint, label: String? = nil, address: String = "") -> UUID? {
        guard current != nil else { return nil }
        checkpoint()
        let spot = freeSpot(near: point)
        let node = DiagramNode(kind: kind, label: label ?? kind.title, address: address, x: Double(spot.x), y: Double(spot.y))
        update { $0.nodes.append(node) }
        selection = .node(node.id)
        return node.id
    }

    func addZone(near point: CGPoint) {
        guard let current else { return }
        checkpoint()
        let color = DiagramZone.palette[current.zones.count % DiagramZone.palette.count]
        let zone = DiagramZone(name: "Zone \(current.zones.count + 1)", x: DiagramMetrics.snap(Double(point.x) - 200), y: DiagramMetrics.snap(Double(point.y) - 120),
                               width: 400, height: 240, colorHex: color)
        update { $0.zones.append(zone) }
        selection = .zone(zone.id)
    }

    func connect(_ from: UUID, _ to: UUID) {
        guard from != to, let current else { return }
        // One link per pair is enough.
        if current.links.contains(where: { ($0.from == from && $0.to == to) || ($0.from == to && $0.to == from) }) { return }
        checkpoint()
        let link = DiagramLink(from: from, to: to)
        update { $0.links.append(link) }
        selection = .link(link.id)
    }

    /// Connect mode: the first click picks the start, the second one draws the link.
    func connectModeTap(_ id: UUID) {
        if let start = connectFrom, start != id {
            connect(start, id)
            connectFrom = nil
        } else {
            connectFrom = id
            selection = .node(id)
        }
    }

    func moveNode(_ id: UUID, to point: CGPoint) {
        update { diagram in
            guard let index = diagram.nodes.firstIndex(where: { $0.id == id }) else { return }
            diagram.nodes[index].x = max(Double(point.x), Double(DiagramMetrics.nodeWidth) / 2 + 10)
            diagram.nodes[index].y = max(Double(point.y), Double(DiagramMetrics.nodeHeight) / 2 + 10)
        }
    }

    func snapNode(_ id: UUID) {
        update { diagram in
            guard let index = diagram.nodes.firstIndex(where: { $0.id == id }) else { return }
            diagram.nodes[index].x = DiagramMetrics.snap(diagram.nodes[index].x)
            diagram.nodes[index].y = DiagramMetrics.snap(diagram.nodes[index].y)
        }
    }

    /// Moves a zone and the nodes that were inside it when the drag started.
    func moveZone(_ id: UUID, to origin: CGPoint, carrying nodeStarts: [UUID: CGPoint], zoneStart: CGPoint) {
        let dx = Double(origin.x - zoneStart.x)
        let dy = Double(origin.y - zoneStart.y)
        update { diagram in
            guard let index = diagram.zones.firstIndex(where: { $0.id == id }) else { return }
            diagram.zones[index].x = max(Double(zoneStart.x) + dx, 0)
            diagram.zones[index].y = max(Double(zoneStart.y) + dy, 0)
            for (nodeID, start) in nodeStarts {
                if let n = diagram.nodes.firstIndex(where: { $0.id == nodeID }) {
                    diagram.nodes[n].x = Double(start.x) + dx
                    diagram.nodes[n].y = Double(start.y) + dy
                }
            }
        }
    }

    func resizeZone(_ id: UUID, width: Double, height: Double) {
        update { diagram in
            guard let index = diagram.zones.firstIndex(where: { $0.id == id }) else { return }
            diagram.zones[index].width = max(160, width)
            diagram.zones[index].height = max(100, height)
        }
    }

    func snapZone(_ id: UUID) {
        update { diagram in
            guard let index = diagram.zones.firstIndex(where: { $0.id == id }) else { return }
            diagram.zones[index].x = DiagramMetrics.snap(diagram.zones[index].x)
            diagram.zones[index].y = DiagramMetrics.snap(diagram.zones[index].y)
            diagram.zones[index].width = DiagramMetrics.snap(diagram.zones[index].width)
            diagram.zones[index].height = DiagramMetrics.snap(diagram.zones[index].height)
        }
    }

    func deleteSelection() {
        guard let selection else { return }
        checkpoint()
        update { diagram in
            switch selection {
            case .node(let id):
                diagram.nodes.removeAll { $0.id == id }
                diagram.links.removeAll { $0.from == id || $0.to == id }
            case .link(let id):
                diagram.links.removeAll { $0.id == id }
            case .zone(let id):
                diagram.zones.removeAll { $0.id == id }
            }
        }
        self.selection = nil
        connectFrom = nil
    }

    func duplicateSelectedNode() {
        guard case .node(let id) = selection, let node = current?.node(id) else { return }
        checkpoint()
        var copy = node
        copy.id = UUID()
        let spot = freeSpot(near: CGPoint(x: node.x + 40, y: node.y + 80))
        copy.x = Double(spot.x)
        copy.y = Double(spot.y)
        update { $0.nodes.append(copy) }
        selection = .node(copy.id)
    }

    func bringZoneToBack(_ id: UUID) {
        checkpoint()
        update { diagram in
            guard let index = diagram.zones.firstIndex(where: { $0.id == id }) else { return }
            let zone = diagram.zones.remove(at: index)
            diagram.zones.insert(zone, at: 0)
        }
    }

    // MARK: - From Targets

    /// One node per Targets host that is not in the diagram yet (matched on address), with a
    /// kind guessed from its open ports, laid out in a grid below what is there.
    @discardableResult
    func addHostsFromTargets() -> Int {
        guard let current else { return 0 }
        let existing = Set(current.nodes.map { $0.address.lowercased() }.filter { !$0.isEmpty })
        let hosts = TargetStore.shared.hosts.filter { $0.kind == .host && !existing.contains($0.address.lowercased()) }
        guard !hosts.isEmpty else { return 0 }
        checkpoint()
        let top = current.nodes.isEmpty && current.zones.isEmpty ? 80 : Double(current.bounds.maxY) + 100
        let columns = max(3, Int(Double(hosts.count).squareRoot().rounded(.up)))
        var nodes: [DiagramNode] = []
        for (index, host) in hosts.enumerated() {
            let ports = host.children.filter { $0.kind == .port }
            let kind = DiagramStore.kind(forPorts: ports.map { $0.portNumber }, services: ports.map { TargetStore.serviceName(of: $0) }, name: host.title + " " + host.subtitle)
            let name = host.subtitle.trimmingCharacters(in: .whitespaces)
            let label = name.isEmpty || name == host.address ? kind.title : name
            nodes.append(DiagramNode(kind: kind, label: label, address: host.address,
                                     notes: ports.isEmpty ? "" : "Open: " + ports.map { "\($0.portNumber)/\($0.portProtocol) \(TargetStore.serviceName(of: $0))" }.joined(separator: ", "),
                                     x: 120 + Double(index % columns) * 200, y: top + Double(index / columns) * 100))
        }
        update { $0.nodes.append(contentsOf: nodes) }
        return nodes.count
    }

    /// Builds a whole network map from Targets as a new diagram: one zone per /24 (hostnames and
    /// IPv6 in "Other hosts"), a gateway node per zone (the .1 host when it is in Targets, else a
    /// router placeholder), an attacker node ($LHOST) linked to every gateway, and the hosts in a
    /// grid inside their zone with the kind guessed from their open ports. Returns the number of
    /// hosts placed, or 0 when Targets is empty.
    @discardableResult
    func buildNetworkMap(name: String = "Network map") -> Int {
        let hosts = TargetStore.shared.hosts.filter { $0.kind == .host && !$0.address.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !hosts.isEmpty else { return 0 }

        // Group by subnet, keep first-seen order of the subnets.
        var groups: [(subnet: String, hosts: [TargetNode])] = []
        for host in hosts {
            let subnet = DiagramStore.subnet(of: host.address)
            if let index = groups.firstIndex(where: { $0.subnet == subnet }) {
                groups[index].hosts.append(host)
            } else {
                groups.append((subnet, [host]))
            }
        }
        groups.sort { a, b in
            if a.subnet == "Other hosts" { return false }
            if b.subnet == "Other hosts" { return true }
            return a.subnet.compare(b.subnet, options: .numeric) == .orderedAscending
        }

        var diagram = Diagram(name: uniqueName(name))
        let columns = 3
        let cellWidth = 200.0, cellHeight = 100.0
        let zoneGap = 60.0
        let zoneTop = 260.0
        var zoneX = 60.0
        var gateways: [UUID] = []

        for (zoneIndex, group) in groups.enumerated() {
            let sorted = group.hosts.sorted { DiagramStore.addressSortKey($0.address).lexicographicallyPrecedes(DiagramStore.addressSortKey($1.address)) }
            let gatewayAddress = group.subnet.hasSuffix(".0/24") ? String(group.subnet.dropLast(4)) + "1" : ""
            var members = sorted
            var gatewayHost: TargetNode? = nil
            if !gatewayAddress.isEmpty, let index = members.firstIndex(where: { $0.address == gatewayAddress }) {
                gatewayHost = members.remove(at: index)
            }
            let rows = max(1, Int((Double(members.count) / Double(columns)).rounded(.up)))
            let usedColumns = min(columns, max(members.count, 1))
            let width = Double(usedColumns) * cellWidth + 40
            let height = Double(DiagramMetrics.zoneHeaderHeight) + 120 + Double(rows) * cellHeight
            let zone = DiagramZone(name: group.subnet, x: zoneX, y: zoneTop, width: width, height: height,
                                   colorHex: DiagramZone.palette[zoneIndex % DiagramZone.palette.count])
            diagram.zones.append(zone)

            // Gateway at the top of the zone.
            let gatewayPoint = CGPoint(x: zoneX + width / 2, y: zoneTop + Double(DiagramMetrics.zoneHeaderHeight) + 50)
            let gateway: DiagramNode
            if let host = gatewayHost {
                gateway = DiagramStore.node(for: host, kind: .router, at: gatewayPoint)
            } else {
                gateway = DiagramNode(kind: .router, label: group.subnet == "Other hosts" ? "Uplink" : "Gateway", address: gatewayAddress,
                                      notes: "Placeholder — not seen in Targets", x: gatewayPoint.x, y: gatewayPoint.y)
            }
            diagram.nodes.append(gateway)
            gateways.append(gateway.id)

            for (index, host) in members.enumerated() {
                let column = index % columns
                let row = index / columns
                let point = CGPoint(x: zoneX + 20 + cellWidth / 2 + Double(column) * cellWidth,
                                    y: zoneTop + Double(DiagramMetrics.zoneHeaderHeight) + 150 + Double(row) * cellHeight)
                diagram.nodes.append(DiagramStore.node(for: host, kind: nil, at: point))
            }
            zoneX += width + zoneGap
        }

        // Attacker above the middle, linked to every gateway.
        let totalWidth = zoneX - zoneGap - 60
        let attacker = DiagramNode(kind: .attacker, label: "Attacker", address: SnippetStore.shared.lhost,
                                   notes: "Your machine ($LHOST)", x: DiagramMetrics.snap(60 + totalWidth / 2), y: 80)
        diagram.nodes.append(attacker)
        for gateway in gateways {
            diagram.links.append(DiagramLink(from: attacker.id, to: gateway, style: .dashed))
        }
        for index in diagram.nodes.indices {
            diagram.nodes[index].x = DiagramMetrics.snap(diagram.nodes[index].x)
            diagram.nodes[index].y = DiagramMetrics.snap(diagram.nodes[index].y)
        }
        diagrams.append(diagram)
        select(diagram.id)
        scheduleSave()
        ActivityLog.shared.record(.action, "Network map built from Targets: \(hosts.count) host(s) in \(groups.count) segment(s)", source: "Diagram")
        return hosts.count
    }

    /// A diagram node for a Targets host; the kind is guessed from the open ports unless given.
    static func node(for host: TargetNode, kind forced: DiagramNodeKind?, at point: CGPoint) -> DiagramNode {
        let ports = host.children.filter { $0.kind == .port }
        let kind = forced ?? DiagramStore.kind(forPorts: ports.map { $0.portNumber }, services: ports.map { TargetStore.serviceName(of: $0) }, name: host.title + " " + host.subtitle)
        let name = host.subtitle.trimmingCharacters(in: .whitespaces)
        let label = name.isEmpty || name == host.address ? kind.title : name
        var notes = ports.isEmpty ? "" : "Open: " + ports.map { "\($0.portNumber)/\($0.portProtocol) \(TargetStore.serviceName(of: $0))" }.joined(separator: ", ")
        if host.status == .done { notes = (notes.isEmpty ? "" : notes + "\n") + "Status in Targets: done" }
        return DiagramNode(kind: kind, label: label, address: host.address, notes: notes, x: point.x, y: point.y)
    }

    /// "10.10.10.0/24" for an IPv4 address, "Other hosts" for names and IPv6.
    static func subnet(of address: String) -> String {
        let parts = address.trimmingCharacters(in: .whitespaces).split(separator: ".")
        guard parts.count == 4, parts.allSatisfy({ Int($0).map { (0...255).contains($0) } ?? false }) else { return "Other hosts" }
        return parts.prefix(3).joined(separator: ".") + ".0/24"
    }

    static func addressSortKey(_ address: String) -> [Int] {
        let parts = address.split(separator: ".").compactMap { Int($0) }
        return parts.count == 4 ? parts : [Int.max] + Array(address.unicodeScalars.map { Int($0.value) })
    }

    static func kind(forPorts ports: [Int], services: [String], name: String) -> DiagramNodeKind {
        let set = Set(ports)
        let joined = services.joined(separator: " ").lowercased()
        if set.contains(88) && (set.contains(389) || set.contains(636)) { return .domainController }
        if !set.isDisjoint(with: [1433, 1521, 3306, 5432, 27017, 6379, 9200]) { return .database }
        if !set.isDisjoint(with: [25, 465, 587, 993, 995]) || joined.contains("smtp") { return .mailServer }
        if !set.isDisjoint(with: [9100, 515, 631]) { return .printer }
        if !set.isDisjoint(with: [500, 4500, 1194, 51820]) { return .vpn }
        if !set.isDisjoint(with: [80, 443, 8080, 8443, 8000]) || joined.contains("http") { return .webServer }
        if set.contains(3389) && set.count <= 3 { return .workstation }
        let guessed = DiagramNodeKind.guess(from: name)
        if guessed != .generic { return guessed }
        return set.isEmpty ? .generic : .server
    }

    // MARK: - Sample

    /// Example for a web application assessment: user → CDN/WAF → app → API → data, with the
    /// identity side (IdP, authorization server, MFA, directory) drawn as its own zone.
    static func sampleWebApp(named name: String) -> Diagram {
        var diagram = Diagram(name: name)
        let user = DiagramNode(kind: .user, label: "User", address: "browser / mobile app", x: 100, y: 300)
        let attacker = DiagramNode(kind: .attacker, label: "Attacker", x: 100, y: 440)
        let cdn = DiagramNode(kind: .cdn, label: "CDN", address: "static assets", x: 340, y: 240)
        let waf = DiagramNode(kind: .waf, label: "WAF", address: "www.example.com", x: 340, y: 380)
        let proxy = DiagramNode(kind: .reverseProxy, label: "API gateway", address: "ingress", x: 580, y: 380)
        let app = DiagramNode(kind: .webApp, label: "Frontend (SPA)", address: "app.example.com", x: 580, y: 240)
        let api = DiagramNode(kind: .api, label: "Backend API", address: "api.example.com", x: 820, y: 300)
        let worker = DiagramNode(kind: .microservice, label: "Worker", address: "jobs", x: 820, y: 440)
        let queue = DiagramNode(kind: .messageQueue, label: "Queue", x: 1060, y: 440)
        let db = DiagramNode(kind: .database, label: "Database", address: "PostgreSQL", x: 1060, y: 240)
        let cache = DiagramNode(kind: .cache, label: "Cache", address: "Redis", x: 1060, y: 320)
        let storage = DiagramNode(kind: .objectStorage, label: "Uploads", address: "S3 bucket", x: 1060, y: 560)
        let idp = DiagramNode(kind: .identityProvider, label: "IdP (SSO)", address: "login.example.com", x: 580, y: 640)
        let authz = DiagramNode(kind: .authorizationServer, label: "Authorization server", address: "OAuth 2.0 / OIDC", x: 820, y: 640)
        let mfa = DiagramNode(kind: .mfa, label: "MFA", address: "TOTP / push", x: 340, y: 640)
        let directory = DiagramNode(kind: .directory, label: "Directory", address: "LDAP / AD", x: 1060, y: 640)
        let psp = DiagramNode(kind: .thirdParty, label: "Payment provider", address: "external", x: 820, y: 120)
        diagram.nodes = [user, attacker, cdn, waf, proxy, app, api, worker, queue, db, cache, storage, idp, authz, mfa, directory, psp]
        diagram.links = [
            DiagramLink(from: user.id, to: cdn.id, label: "443"),
            DiagramLink(from: user.id, to: waf.id, label: "443"),
            DiagramLink(from: attacker.id, to: waf.id, style: .dashed),
            DiagramLink(from: cdn.id, to: app.id),
            DiagramLink(from: waf.id, to: proxy.id),
            DiagramLink(from: proxy.id, to: api.id, label: "bearer token", directed: true),
            DiagramLink(from: app.id, to: api.id),
            DiagramLink(from: api.id, to: db.id),
            DiagramLink(from: api.id, to: cache.id),
            DiagramLink(from: api.id, to: queue.id),
            DiagramLink(from: queue.id, to: worker.id, directed: true),
            DiagramLink(from: worker.id, to: storage.id),
            DiagramLink(from: api.id, to: psp.id, label: "webhooks", style: .dashed),
            DiagramLink(from: user.id, to: idp.id, label: "login (redirect)", style: .dotted, directed: true),
            DiagramLink(from: idp.id, to: mfa.id),
            DiagramLink(from: idp.id, to: authz.id, label: "code → token", directed: true),
            DiagramLink(from: authz.id, to: directory.id),
            DiagramLink(from: authz.id, to: api.id, label: "JWKS / introspection", style: .dotted),
        ]
        diagram.zones = [
            DiagramZone(name: "Edge", x: 260, y: 160, width: 180, height: 300, colorHex: "#F2994A"),
            DiagramZone(name: "Application", x: 500, y: 160, width: 420, height: 360, colorHex: "#E07A5F"),
            DiagramZone(name: "Data", x: 980, y: 160, width: 180, height: 460, colorHex: "#27AE60"),
            DiagramZone(name: "Identity", x: 260, y: 580, width: 900, height: 120, colorHex: "#BB6BD9"),
        ]
        return diagram
    }

    static func sampleDiagram(named name: String) -> Diagram {
        var diagram = Diagram(name: name)
        let internet = DiagramNode(kind: .internet, label: "Internet", x: 120, y: 260)
        let firewall = DiagramNode(kind: .firewall, label: "Edge firewall", address: "203.0.113.1", x: 360, y: 260)
        let web = DiagramNode(kind: .webServer, label: "Web server", address: "172.16.10.10", x: 620, y: 140)
        let mail = DiagramNode(kind: .mailServer, label: "Mail relay", address: "172.16.10.20", x: 620, y: 220)
        let core = DiagramNode(kind: .switchDevice, label: "Core switch", address: "10.0.0.1", x: 620, y: 420)
        let dc = DiagramNode(kind: .domainController, label: "DC01", address: "10.0.0.10", x: 880, y: 360)
        let db = DiagramNode(kind: .database, label: "SQL01", address: "10.0.0.20", x: 880, y: 440)
        let client = DiagramNode(kind: .workstation, label: "Clients", address: "10.0.20.0/24", x: 880, y: 520)
        diagram.nodes = [internet, firewall, web, mail, core, dc, db, client]
        diagram.links = [
            DiagramLink(from: internet.id, to: firewall.id),
            DiagramLink(from: firewall.id, to: web.id, label: "443"),
            DiagramLink(from: firewall.id, to: mail.id, label: "25"),
            DiagramLink(from: firewall.id, to: core.id),
            DiagramLink(from: core.id, to: dc.id),
            DiagramLink(from: core.id, to: db.id),
            DiagramLink(from: core.id, to: client.id),
        ]
        diagram.zones = [
            DiagramZone(name: "DMZ — 172.16.10.0/24", x: 500, y: 80, width: 260, height: 200, colorHex: "#F2994A"),
            DiagramZone(name: "Internal — 10.0.0.0/16", x: 500, y: 320, width: 520, height: 260, colorHex: "#2F80ED"),
        ]
        return diagram
    }

    // MARK: - Saving

    func scheduleSave() {
        let url = EngagementStore.shared.fileURL(DiagramStore.fileName)
        saver.call { [weak self] in
            guard let self else { return }
            Storage.save(self.diagrams, at: url)
        }
    }

    func flush() {
        saver.flush()
    }
}
