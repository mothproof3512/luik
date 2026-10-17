import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Export to PNG, SVG, draw.io, Mermaid and Luik JSON; import from draw.io (compressed or not),
/// Mermaid flowcharts and Luik JSON.
enum DiagramTransfer {
    enum ExportFormat: String, CaseIterable, Identifiable {
        case pngDark, pngLight, svg, drawio, mermaid, json

        var id: String { rawValue }

        var title: String {
            switch self {
            case .pngDark: return "PNG image (dark)"
            case .pngLight: return "PNG image (light, for reports)"
            case .svg: return "SVG (vector, light)"
            case .drawio: return "draw.io / diagrams.net (.drawio)"
            case .mermaid: return "Mermaid flowchart (.mmd)"
            case .json: return "Luik diagram (.json)"
            }
        }

        var fileExtension: String {
            switch self {
            case .pngDark, .pngLight: return "png"
            case .svg: return "svg"
            case .drawio: return "drawio"
            case .mermaid: return "mmd"
            case .json: return "json"
            }
        }
    }

    // MARK: - Export

    @MainActor
    static func export(_ diagram: Diagram, as format: ExportFormat, accent: Color) -> String? {
        let data: Data?
        switch format {
        case .pngDark: data = png(diagram, palette: .dark(accent: accent))
        case .pngLight: data = png(diagram, palette: .light(accent: accent))
        case .svg: data = Data(svg(diagram).utf8)
        case .drawio: data = Data(drawio(diagram).utf8)
        case .mermaid: data = Data(mermaid(diagram).utf8)
        case .json: data = json(diagram)
        }
        guard let data else { return "Could not render the diagram." }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = safeFileName(diagram.name) + "." + format.fileExtension
        if let type = UTType(filenameExtension: format.fileExtension) {
            panel.allowedContentTypes = [type]
        }
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            try data.write(to: url)
            ActivityLog.shared.record(.action, "Diagram “\(diagram.name)” exported to \(url.path)", source: "Diagram")
            return "Exported to \(url.lastPathComponent)."
        } catch {
            return "Export failed: \(error.localizedDescription)"
        }
    }

    /// The light PNG on the clipboard, for pasting into a report or chat.
    @MainActor
    static func copyImage(_ diagram: Diagram, accent: Color, light: Bool) -> Bool {
        guard let data = png(diagram, palette: light ? .light(accent: accent) : .dark(accent: accent)),
              let image = NSImage(data: data) else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.writeObjects([image])
    }

    static func safeFileName(_ name: String) -> String {
        let cleaned = name.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == " " ? $0 : "-" }
        let result = String(cleaned).trimmingCharacters(in: .whitespaces)
        return result.isEmpty ? "diagram" : result
    }

    @MainActor
    static func png(_ diagram: Diagram, palette: DiagramPalette) -> Data? {
        let renderer = ImageRenderer(content: DiagramStaticDrawing(diagram: diagram, palette: palette)
            .environment(\.colorScheme, palette.isLight ? .light : .dark))
        renderer.scale = 2
        guard let image = renderer.cgImage else { return nil }
        let bitmap = NSBitmapImageRep(cgImage: image)
        return bitmap.representation(using: .png, properties: [:])
    }

    struct JSONEnvelope: Codable {
        var format = "luik-diagram"
        var version = 1
        var diagram: Diagram
    }

    static func json(_ diagram: Diagram) -> Data? {
        try? JSONEncoder.iso.encode(JSONEnvelope(diagram: diagram))
    }

    static func xmlEscape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    /// Vector drawing in the light style: zones, links, cards with a coloured disc and abbreviation.
    static func svg(_ diagram: Diagram) -> String {
        let pad = 40.0
        let b = diagram.bounds
        let ox = Double(b.minX) - pad
        let oy = Double(b.minY) - pad
        let width = Double(b.width) + 2 * pad
        let height = Double(b.height) + 2 * pad
        let w = Double(DiagramMetrics.nodeWidth)
        let h = Double(DiagramMetrics.nodeHeight)
        var out = """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(number(width))" height="\(number(height))" viewBox="0 0 \(number(width)) \(number(height))" font-family="-apple-system, 'Segoe UI', Helvetica, Arial, sans-serif">
          <defs>
            <marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="8" markerHeight="8" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="#737373"/></marker>
            <filter id="shadow" x="-10%" y="-20%" width="120%" height="150%"><feDropShadow dx="0" dy="2" stdDeviation="3" flood-opacity="0.18"/></filter>
          </defs>
          <rect width="100%" height="100%" fill="#ffffff"/>

        """
        for zone in diagram.zones {
            let x = zone.x - ox, y = zone.y - oy
            out += """
              <g>
                <rect x="\(number(x))" y="\(number(y))" width="\(number(zone.width))" height="\(number(zone.height))" rx="16" fill="\(zone.colorHex)" fill-opacity="0.08" stroke="\(zone.colorHex)" stroke-opacity="0.6" stroke-dasharray="6 4"/>
                <text x="\(number(x + 14))" y="\(number(y + 22))" font-size="11" font-weight="600" fill="\(zone.colorHex)">\(xmlEscape(zone.name))</text>
              </g>

            """
        }
        let geometry = DiagramGeometry(zoom: 1, origin: CGPoint(x: ox, y: oy))
        for link in diagram.links {
            guard let a = diagram.node(link.from), let c = diagram.node(link.to) else { continue }
            let ca = geometry.point(a.x, a.y), cb = geometry.point(c.x, c.y)
            let p1 = geometry.edgePoint(from: ca, toward: cb), p2 = geometry.edgePoint(from: cb, toward: ca)
            let dash = link.style == .solid ? "" : " stroke-dasharray=\"\(link.style.dash.map { number(Double($0)) }.joined(separator: " "))\""
            let marker = link.directed ? " marker-end=\"url(#arrow)\"" : ""
            out += "  <line x1=\"\(number(Double(p1.x)))\" y1=\"\(number(Double(p1.y)))\" x2=\"\(number(Double(p2.x)))\" y2=\"\(number(Double(p2.y)))\" stroke=\"#737373\" stroke-width=\"1.8\" stroke-linecap=\"round\"\(dash)\(marker)/>\n"
            if !link.label.isEmpty {
                let mx = Double(p1.x + p2.x) / 2, my = Double(p1.y + p2.y) / 2
                let lw = Double(link.label.count) * 6 + 14
                out += "  <rect x=\"\(number(mx - lw / 2))\" y=\"\(number(my - 9))\" width=\"\(number(lw))\" height=\"18\" rx=\"9\" fill=\"#ffffff\" stroke=\"#bdbdbd\"/>\n"
                out += "  <text x=\"\(number(mx))\" y=\"\(number(my + 3.5))\" font-size=\"10\" text-anchor=\"middle\" fill=\"#1a1a1a\">\(xmlEscape(link.label))</text>\n"
            }
        }
        for node in diagram.nodes {
            let x = node.x - ox - w / 2, y = node.y - oy - h / 2
            let label = node.label.isEmpty ? node.kind.title : node.label
            let sub = node.address.isEmpty ? node.kind.title : node.address
            out += """
              <g filter="url(#shadow)">
                <rect x="\(number(x))" y="\(number(y))" width="\(number(w))" height="\(number(h))" rx="12" fill="#ffffff" stroke="#e0e0e0"/>
                <rect x="\(number(x))" y="\(number(y + 6))" width="4" height="\(number(h - 12))" rx="2" fill="\(node.kind.hex)"/>
                <circle cx="\(number(x + 27))" cy="\(number(y + h / 2))" r="17" fill="\(node.kind.hex)"/>
                <text x="\(number(x + 27))" y="\(number(y + h / 2 + 3.5))" font-size="\(node.kind.abbreviation.count > 2 ? "9" : "11")" font-weight="700" text-anchor="middle" fill="#ffffff">\(xmlEscape(node.kind.abbreviation))</text>
                <text x="\(number(x + 53))" y="\(number(y + h / 2 - 3))" font-size="12" font-weight="600" fill="#1a1a1a">\(xmlEscape(label))</text>
                <text x="\(number(x + 53))" y="\(number(y + h / 2 + 12))" font-size="10" fill="#666666"\(node.address.isEmpty ? "" : " font-family=\"Menlo, Consolas, monospace\"")>\(xmlEscape(sub))</text>
              </g>

            """
        }
        out += "</svg>\n"
        return out
    }

    /// An uncompressed .drawio file: zones as dashed containers, nodes as cards, links as edges.
    static func drawio(_ diagram: Diagram) -> String {
        let w = Double(DiagramMetrics.nodeWidth), h = Double(DiagramMetrics.nodeHeight)
        var cells: [String] = ["<mxCell id=\"0\"/>", "<mxCell id=\"1\" parent=\"0\"/>"]
        var index = 2
        var ids: [UUID: String] = [:]
        for zone in diagram.zones {
            let id = "z\(index)"; index += 1
            let style = "rounded=1;arcSize=6;dashed=1;fillColor=\(zone.colorHex);opacity=100;fillOpacity=10;strokeColor=\(zone.colorHex);fontColor=\(zone.colorHex);fontStyle=1;verticalAlign=top;align=left;spacingLeft=10;spacingTop=4;whiteSpace=wrap;html=1;"
            cells.append("<mxCell id=\"\(id)\" value=\"\(xmlEscape(zone.name))\" style=\"\(style)\" vertex=\"1\" parent=\"1\"><mxGeometry x=\"\(number(zone.x))\" y=\"\(number(zone.y))\" width=\"\(number(zone.width))\" height=\"\(number(zone.height))\" as=\"geometry\"/></mxCell>")
        }
        for node in diagram.nodes {
            let id = "n\(index)"; index += 1
            ids[node.id] = id
            let label = node.label.isEmpty ? node.kind.title : node.label
            var html = "<b>\(xmlEscape(label))</b>"
            if !node.address.isEmpty { html += "<br>\(xmlEscape(node.address))" }
            html += "<br><font color=\"#888888\" style=\"font-size:9px\">\(xmlEscape(node.kind.title))</font>"
            let style = "rounded=1;arcSize=20;whiteSpace=wrap;html=1;fillColor=#ffffff;strokeColor=\(node.kind.hex);strokeWidth=2;shadow=1;align=center;fontSize=11;luikKind=\(node.kind.rawValue);"
            let value = xmlEscape(html)
            cells.append("<mxCell id=\"\(id)\" value=\"\(value)\" style=\"\(style)\" vertex=\"1\" parent=\"1\"><mxGeometry x=\"\(number(node.x - w / 2))\" y=\"\(number(node.y - h / 2))\" width=\"\(number(w))\" height=\"\(number(h))\" as=\"geometry\"/></mxCell>")
        }
        for link in diagram.links {
            guard let source = ids[link.from], let target = ids[link.to] else { continue }
            let id = "e\(index)"; index += 1
            var style = "edgeStyle=none;html=1;rounded=0;strokeColor=#737373;strokeWidth=2;fontSize=10;labelBackgroundColor=#ffffff;"
            style += link.directed ? "endArrow=block;endFill=1;" : "endArrow=none;"
            if link.style == .dashed { style += "dashed=1;" }
            if link.style == .dotted { style += "dashed=1;dashPattern=1 4;" }
            cells.append("<mxCell id=\"\(id)\" value=\"\(xmlEscape(link.label))\" style=\"\(style)\" edge=\"1\" parent=\"1\" source=\"\(source)\" target=\"\(target)\"><mxGeometry relative=\"1\" as=\"geometry\"/></mxCell>")
        }
        return """
        <mxfile host="Luik" type="device">
          <diagram name="\(xmlEscape(diagram.name))" id="\(diagram.id.uuidString)">
            <mxGraphModel grid="1" gridSize="10" guides="1" connect="1" arrows="1" page="0" math="0" shadow="0">
              <root>
                \(cells.joined(separator: "\n        "))
              </root>
            </mxGraphModel>
          </diagram>
        </mxfile>

        """
    }

    /// A Mermaid flowchart: zones as subgraphs, kinds as shapes, IPs on a second line.
    static func mermaid(_ diagram: Diagram) -> String {
        var ids: [UUID: String] = [:]
        for (index, node) in diagram.nodes.enumerated() { ids[node.id] = "n\(index + 1)" }
        func escape(_ text: String) -> String {
            text.replacingOccurrences(of: "\"", with: "#quot;")
        }
        func definition(_ node: DiagramNode) -> String {
            let id = ids[node.id] ?? "n"
            var text = node.label.isEmpty ? node.kind.title : node.label
            if !node.address.isEmpty { text += "<br/>" + node.address }
            let label = "\"\(escape(text))\""
            switch node.kind {
            case .database: return "\(id)[(\(label))]"
            case .internet, .cloud: return "\(id)((\(label)))"
            case .firewall, .vpn: return "\(id){{\(label)}}"
            case .router, .switchDevice, .loadBalancer: return "\(id)([\(label)])"
            default: return "\(id)[\(label)]"
            }
        }
        var lines = ["%% \(diagram.name) — exported from Luik", "flowchart LR"]
        var placed: Set<UUID> = []
        for (index, zone) in diagram.zones.enumerated() {
            let members = diagram.nodes.filter { diagram.zone(of: $0)?.id == zone.id }
            guard !members.isEmpty else { continue }
            lines.append("  subgraph z\(index + 1)[\"\(escape(zone.name))\"]")
            for node in members {
                lines.append("    " + definition(node))
                placed.insert(node.id)
            }
            lines.append("  end")
        }
        for node in diagram.nodes where !placed.contains(node.id) {
            lines.append("  " + definition(node))
        }
        for link in diagram.links {
            guard let a = ids[link.from], let b = ids[link.to] else { continue }
            let arrow: String
            switch (link.style, link.directed) {
            case (.solid, false): arrow = "---"
            case (.solid, true): arrow = "-->"
            case (_, false): arrow = "-.-"
            case (_, true): arrow = "-.->"
            }
            let label = link.label.isEmpty ? "" : "|\"\(escape(link.label))\"|"
            lines.append("  \(a) \(arrow)\(label) \(b)")
        }
        for (index, zone) in diagram.zones.enumerated() where diagram.nodes.contains(where: { diagram.zone(of: $0)?.id == zone.id }) {
            lines.append("  style z\(index + 1) fill:\(zone.colorHex)14,stroke:\(zone.colorHex),stroke-dasharray: 5 4")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Import

    enum ImportError: LocalizedError {
        case unknownFormat
        case empty
        case unreadable(String)

        var errorDescription: String? {
            switch self {
            case .unknownFormat: return "Not a Luik diagram, draw.io file or Mermaid flowchart."
            case .empty: return "The file contains no nodes."
            case .unreadable(let detail): return detail
            }
        }
    }

    /// Recognises the format from the content.
    static func parse(_ text: String, name: String) throws -> Diagram {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var diagram: Diagram
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            diagram = try parseJSON(Data(trimmed.utf8))
        } else if trimmed.contains("<mxfile") || trimmed.contains("<mxGraphModel") {
            diagram = try DrawioImport.parse(trimmed)
            diagram.name = name
        } else if MermaidImport.looksLikeMermaid(trimmed) {
            diagram = MermaidImport.parse(trimmed)
            if diagram.name.isEmpty { diagram.name = name }
        } else {
            throw ImportError.unknownFormat
        }
        guard !diagram.nodes.isEmpty else { throw ImportError.empty }
        return diagram
    }

    static func parseJSON(_ data: Data) throws -> Diagram {
        let decoder = JSONDecoder.iso
        if let envelope = try? decoder.decode(JSONEnvelope.self, from: data) { return fresh(envelope.diagram) }
        if let diagram = try? decoder.decode(Diagram.self, from: data) { return fresh(diagram) }
        if let list = try? decoder.decode([Diagram].self, from: data), let first = list.first { return fresh(first) }
        throw ImportError.unknownFormat
    }

    /// New ids, so importing the same file twice gives two independent diagrams.
    static func fresh(_ diagram: Diagram) -> Diagram {
        var copy = diagram
        copy.id = UUID()
        var map: [UUID: UUID] = [:]
        copy.nodes = diagram.nodes.map { node in
            var n = node
            n.id = UUID()
            map[node.id] = n.id
            return n
        }
        copy.links = diagram.links.compactMap { link in
            guard let from = map[link.from], let to = map[link.to] else { return nil }
            var l = link
            l.id = UUID()
            l.from = from
            l.to = to
            return l
        }
        copy.zones = diagram.zones.map { zone in
            var z = zone
            z.id = UUID()
            return z
        }
        return copy
    }

    /// Open panel; the imported diagram is added to the engagement. Returns a status line.
    static func importWithPanel(into store: DiagramStore) -> String? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        var types: [UTType] = [.json, .xml, .plainText]
        for ext in ["drawio", "mmd", "mermaid", "md"] {
            if let type = UTType(filenameExtension: ext) { types.append(type) }
        }
        panel.allowedContentTypes = types
        panel.message = "Choose a draw.io file (.drawio / .xml), a Mermaid flowchart (.mmd / .md) or a Luik diagram (.json)"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            let data = try Data(contentsOf: url)
            let text = String(decoding: data, as: UTF8.self)
            let diagram = try parse(text, name: url.deletingPathExtension().lastPathComponent)
            store.add(diagram)
            ActivityLog.shared.record(.import, "Diagram imported from \(url.lastPathComponent) (\(diagram.nodes.count) nodes)", source: "Diagram")
            return "Imported \(url.lastPathComponent): \(diagram.nodes.count) nodes, \(diagram.links.count) links, \(diagram.zones.count) zones."
        } catch {
            return "Import failed: \(error.localizedDescription)"
        }
    }

    /// Mermaid or draw.io XML from the clipboard (e.g. copied from a wiki or diagrams.net).
    static func importFromClipboard(into store: DiagramStore) -> String {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            return "The clipboard holds no text."
        }
        do {
            let diagram = try parse(text, name: "Pasted diagram")
            store.add(diagram)
            return "Pasted: \(diagram.nodes.count) nodes, \(diagram.links.count) links, \(diagram.zones.count) zones."
        } catch {
            return "Paste failed: \(error.localizedDescription)"
        }
    }

    /// Layered placement for imports without coordinates: breadth-first from the nodes nothing
    /// points at; LR = layers left to right, TD = top to bottom. Zones are fitted around members.
    static func autoLayout(_ diagram: inout Diagram, horizontal: Bool, zoneMembers: [UUID: [UUID]] = [:]) {
        let ids = diagram.nodes.map { $0.id }
        var neighbours: [UUID: [UUID]] = [:]
        var incoming: [UUID: Int] = [:]
        for link in diagram.links {
            neighbours[link.from, default: []].append(link.to)
            if !link.directed { neighbours[link.to, default: []].append(link.from) }
            incoming[link.to, default: 0] += 1
        }
        var layer: [UUID: Int] = [:]
        let roots = ids.filter { (incoming[$0] ?? 0) == 0 }
        for start in (roots.isEmpty ? Array(ids.prefix(1)) : roots) + ids where layer[start] == nil {
            layer[start] = 0
            var queue = [start]
            while !queue.isEmpty {
                let current = queue.removeFirst()
                for next in neighbours[current] ?? [] where layer[next] == nil {
                    layer[next] = (layer[current] ?? 0) + 1
                    queue.append(next)
                }
            }
        }
        var rowInLayer: [Int: Int] = [:]
        for index in diagram.nodes.indices {
            let l = layer[diagram.nodes[index].id] ?? 0
            let row = rowInLayer[l, default: 0]
            rowInLayer[l] = row + 1
            if horizontal {
                diagram.nodes[index].x = 140 + Double(l) * 240
                diagram.nodes[index].y = 100 + Double(row) * 100
            } else {
                diagram.nodes[index].x = 140 + Double(row) * 200
                diagram.nodes[index].y = 100 + Double(l) * 130
            }
        }
        fitZones(&diagram, members: zoneMembers)
    }

    /// Sets each zone's rectangle around its member nodes.
    static func fitZones(_ diagram: inout Diagram, members: [UUID: [UUID]]) {
        for index in diagram.zones.indices {
            let memberIDs = Set(members[diagram.zones[index].id] ?? [])
            let nodes = diagram.nodes.filter { memberIDs.contains($0.id) }
            guard !nodes.isEmpty else { continue }
            let minX = nodes.map { $0.x }.min()! - Double(DiagramMetrics.nodeWidth) / 2 - 24
            let maxX = nodes.map { $0.x }.max()! + Double(DiagramMetrics.nodeWidth) / 2 + 24
            let minY = nodes.map { $0.y }.min()! - Double(DiagramMetrics.nodeHeight) / 2 - 44
            let maxY = nodes.map { $0.y }.max()! + Double(DiagramMetrics.nodeHeight) / 2 + 24
            diagram.zones[index].x = minX
            diagram.zones[index].y = minY
            diagram.zones[index].width = maxX - minX
            diagram.zones[index].height = maxY - minY
        }
    }

    /// Label lines → (label, address): a line that looks like an IP, range or CIDR becomes the address.
    static func splitLabel(_ text: String) -> (label: String, address: String) {
        let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var label: [String] = []
        var address = ""
        for line in lines {
            if address.isEmpty, line.range(of: #"^\d{1,3}(\.\d{1,3}){3}([/\-]\d{1,3}(\.\d{1,3}){0,3})?$"#, options: .regularExpression) != nil
                || line.range(of: #"^[0-9a-fA-F:]+:[0-9a-fA-F:]*(/\d{1,3})?$"#, options: .regularExpression) != nil && line.contains("::") {
                address = line
            } else {
                label.append(line)
            }
        }
        return (label.joined(separator: " "), address)
    }
}

// MARK: - Mermaid

enum MermaidImport {
    static func looksLikeMermaid(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.range(of: #"(^|\n)\s*(flowchart|graph)\s+(lr|rl|td|tb|bt)\b"#, options: .regularExpression) != nil
            || lower.range(of: #"(^|\n)\s*(flowchart|graph)\s*($|\n)"#, options: .regularExpression) != nil
            || text.contains("-->") || text.contains("---")
    }

    private static let nodeRegex = try! NSRegularExpression(pattern:
        #"^\s*([A-Za-z0-9_]+)(\[\[[^\]]*\]\]|\[\([^\)]*\)\]|\(\([^\)]*\)\)|\(\[[^\]]*\]\)|\{\{[^\}]*\}\}|\[[^\]]*\]|\([^\)]*\)|\{[^\}]*\}|>[^\]]*\])?(:::[A-Za-z0-9_\-]+)?\s*"#)
    private static let textEdgeRegex = try! NSRegularExpression(pattern:
        #"^\s*(--|==|-\.)\s+([^\-=\.|][^|]*?)\s+(-{2,}>|-{3,}|={2,}>|={3,}|\.-+>|\.-+)\s*"#)
    private static let edgeRegex = try! NSRegularExpression(pattern:
        #"^\s*(<)?(-{2,}|={2,}|-\.+-)(>|o|x)?\s*(?:\|([^|]*)\|)?\s*"#)
    private static let ampersandRegex = try! NSRegularExpression(pattern: #"^\s*&\s*"#)

    private struct Shape {
        var label: String
        var kind: DiagramNodeKind?
    }

    static func parse(_ text: String) -> Diagram {
        var diagram = Diagram(name: "")
        var nodeIDs: [String: UUID] = [:]
        var zoneStack: [UUID] = []
        var zoneMembers: [UUID: [UUID]] = [:]
        var horizontal = false

        func node(for id: String, shape: Shape?) -> UUID {
            if let existing = nodeIDs[id] {
                if let shape, let index = diagram.nodes.firstIndex(where: { $0.id == existing }) {
                    let parts = DiagramTransfer.splitLabel(shape.label)
                    diagram.nodes[index].label = parts.label.isEmpty ? id : parts.label
                    if !parts.address.isEmpty { diagram.nodes[index].address = parts.address }
                    diagram.nodes[index].kind = shape.kind ?? DiagramNodeKind.guess(from: shape.label)
                }
                for zone in zoneStack where !(zoneMembers[zone] ?? []).contains(existing) {
                    zoneMembers[zone, default: []].append(existing)
                }
                return existing
            }
            let labelText = shape?.label ?? id
            let parts = DiagramTransfer.splitLabel(labelText)
            let kind = shape?.kind ?? DiagramNodeKind.guess(from: labelText)
            let created = DiagramNode(kind: kind, label: parts.label.isEmpty ? id : parts.label, address: parts.address, x: 0, y: 0)
            diagram.nodes.append(created)
            nodeIDs[id] = created.id
            for zone in zoneStack { zoneMembers[zone, default: []].append(created.id) }
            return created.id
        }

        for rawLine in text.components(separatedBy: .newlines) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            if let comment = line.range(of: "%%") { line = String(line[..<comment.lowerBound]).trimmingCharacters(in: .whitespaces) }
            if line.hasSuffix(";") { line.removeLast() }
            guard !line.isEmpty else { continue }
            let lower = line.lowercased()
            if lower.hasPrefix("flowchart") || lower.hasPrefix("graph") {
                horizontal = lower.contains(" lr") || lower.contains(" rl")
                continue
            }
            if lower.hasPrefix("subgraph") {
                var title = line.dropFirst("subgraph".count).trimmingCharacters(in: .whitespaces)
                if let open = title.firstIndex(of: "["), title.hasSuffix("]") {
                    title = String(title[title.index(after: open)..<title.index(before: title.endIndex)])
                }
                title = cleanLabel(title)
                let color = DiagramZone.palette[diagram.zones.count % DiagramZone.palette.count]
                let zone = DiagramZone(name: title.isEmpty ? "Zone" : title, x: 0, y: 0, width: 200, height: 120, colorHex: color)
                diagram.zones.append(zone)
                zoneStack.append(zone.id)
                continue
            }
            if lower == "end" {
                if !zoneStack.isEmpty { zoneStack.removeLast() }
                continue
            }
            if ["classdef", "class ", "style", "linkstyle", "click", "direction", "accTitle", "accDescr"].contains(where: { lower.hasPrefix($0.lowercased()) }) {
                continue
            }
            let statement = parseStatement(line)
            let groups = statement.groups.map { group in group.map { node(for: $0.id, shape: $0.shape) } }
            for (index, edge) in statement.edges.enumerated() where index + 1 < groups.count {
                for a in groups[index] {
                    for b in groups[index + 1] where a != b {
                        diagram.links.append(DiagramLink(from: a, to: b, label: edge.label, style: edge.dashed ? .dashed : .solid, directed: edge.directed))
                    }
                }
            }
        }
        // Zones that ended up empty are dropped.
        diagram.zones.removeAll { (zoneMembers[$0.id] ?? []).isEmpty }
        DiagramTransfer.autoLayout(&diagram, horizontal: horizontal, zoneMembers: zoneMembers)
        return diagram
    }

    private struct EdgeSpec {
        var directed: Bool
        var dashed: Bool
        var label: String
    }

    /// `A[x] & B --> C -->|label| D` → node groups and the edges between consecutive groups.
    private struct Statement {
        var groups: [[(id: String, shape: Shape?)]] = []
        var edges: [EdgeSpec] = []
    }

    private static func parseStatement(_ line: String) -> Statement {
        let ns = line as NSString
        var position = 0
        var statement = Statement()

        func match(_ regex: NSRegularExpression) -> NSTextCheckingResult? {
            guard position < ns.length else { return nil }
            return regex.firstMatch(in: line, options: [.anchored], range: NSRange(location: position, length: ns.length - position))
        }
        func capture(_ result: NSTextCheckingResult, _ index: Int) -> String? {
            let range = result.range(at: index)
            return range.location == NSNotFound ? nil : ns.substring(with: range)
        }

        while position < ns.length {
            var group: [(id: String, shape: Shape?)] = []
            while let result = match(nodeRegex), result.range.length > 0 {
                let id = capture(result, 1) ?? ""
                let shape = capture(result, 2).map { parseShape($0) }
                group.append((id, shape))
                position = result.range.location + result.range.length
                if let amp = match(ampersandRegex) {
                    position = amp.range.location + amp.range.length
                } else {
                    break
                }
            }
            guard !group.isEmpty else { break }
            statement.groups.append(group)
            if let result = match(textEdgeRegex) {
                let open = capture(result, 1) ?? "--"
                let close = capture(result, 3) ?? "---"
                statement.edges.append(EdgeSpec(directed: close.hasSuffix(">"), dashed: open.contains(".") || close.contains("."),
                                                label: cleanLabel(capture(result, 2) ?? "")))
                position = result.range.location + result.range.length
            } else if let result = match(edgeRegex) {
                let body = capture(result, 2) ?? "--"
                let head = capture(result, 3) ?? ""
                statement.edges.append(EdgeSpec(directed: head == ">" || capture(result, 1) != nil, dashed: body.contains("."),
                                                label: cleanLabel(capture(result, 4) ?? "")))
                position = result.range.location + result.range.length
            } else {
                break
            }
        }
        // A trailing edge without a target is dropped.
        if statement.edges.count >= statement.groups.count {
            statement.edges = Array(statement.edges.prefix(max(statement.groups.count - 1, 0)))
        }
        return statement
    }

    private static func parseShape(_ raw: String) -> Shape {
        let pairs: [(String, String, DiagramNodeKind?)] = [
            ("[(", ")]", .database), ("((", "))", nil), ("{{", "}}", nil), ("[[", "]]", nil), ("([", "])", nil),
            ("[", "]", nil), ("(", ")", nil), ("{", "}", nil), (">", "]", nil),
        ]
        for (open, close, kind) in pairs where raw.hasPrefix(open) && raw.hasSuffix(close) && raw.count >= open.count + close.count {
            let inner = String(raw.dropFirst(open.count).dropLast(close.count))
            let label = cleanLabel(inner)
            var guessed = kind
            if guessed == nil {
                let fromText = DiagramNodeKind.guess(from: label)
                if fromText != .generic {
                    guessed = fromText
                } else if open == "((" {
                    guessed = .cloud
                } else if open == "{{" {
                    guessed = .firewall
                }
            }
            return Shape(label: label, kind: guessed)
        }
        return Shape(label: cleanLabel(raw), kind: nil)
    }

    /// Quotes, `<br>` (→ new line), HTML tags and Mermaid entity codes.
    static func cleanLabel(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("\""), text.hasSuffix("\""), text.count >= 2 { text = String(text.dropFirst().dropLast()) }
        if text.hasPrefix("`"), text.hasSuffix("`"), text.count >= 2 { text = String(text.dropFirst().dropLast()) }
        text = text.replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "#quot;", with: "\"").replacingOccurrences(of: "#amp;", with: "&")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - draw.io

enum DrawioImport {
    private struct Cell {
        var id: String
        var value: String
        var style: String
        var vertex: Bool
        var edge: Bool
        var parent: String
        var source: String
        var target: String
        var x: Double = 0
        var y: Double = 0
        var width: Double = 0
        var height: Double = 0
    }

    private final class Collector: NSObject, XMLParserDelegate {
        var cells: [Cell] = []
        var diagramText = ""
        var sawModel = false
        private var inDiagram = false
        /// Only the first page of a multi-page file is read.
        private var firstPageDone = false
        private var current: Cell?
        private var objectID: String?
        private var objectLabel: String?

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String] = [:]) {
            if firstPageDone { return }
            switch elementName {
            case "diagram":
                inDiagram = true
            case "mxGraphModel":
                sawModel = true
            case "UserObject", "object":
                objectID = attributes["id"]
                objectLabel = attributes["label"]
            case "mxCell":
                current = Cell(id: attributes["id"] ?? objectID ?? UUID().uuidString,
                               value: attributes["value"] ?? objectLabel ?? "",
                               style: attributes["style"] ?? "",
                               vertex: attributes["vertex"] == "1",
                               edge: attributes["edge"] == "1",
                               parent: attributes["parent"] ?? "",
                               source: attributes["source"] ?? "",
                               target: attributes["target"] ?? "")
            case "mxGeometry":
                guard current != nil, attributes["as"] == nil || attributes["as"] == "geometry" else { return }
                current?.x = Double(attributes["x"] ?? "") ?? 0
                current?.y = Double(attributes["y"] ?? "") ?? 0
                current?.width = Double(attributes["width"] ?? "") ?? 0
                current?.height = Double(attributes["height"] ?? "") ?? 0
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if inDiagram && !sawModel && !firstPageDone { diagramText += string }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            if firstPageDone { return }
            switch elementName {
            case "mxCell":
                if let current { cells.append(current) }
                current = nil
            case "UserObject", "object":
                objectID = nil
                objectLabel = nil
            case "diagram":
                inDiagram = false
                firstPageDone = true
            default:
                break
            }
        }
    }

    static func parse(_ xml: String) throws -> Diagram {
        let collector = Collector()
        let parser = XMLParser(data: Data(xml.utf8))
        parser.delegate = collector
        guard parser.parse() || !collector.cells.isEmpty || !collector.diagramText.isEmpty else {
            throw DiagramTransfer.ImportError.unreadable("The draw.io file could not be read: \(parser.parserError?.localizedDescription ?? "invalid XML").")
        }
        var cells = collector.cells
        if cells.isEmpty {
            // Compressed page: base64 → raw deflate → URL-encoded XML.
            let text = collector.diagramText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, let inflated = inflate(text) else {
                throw DiagramTransfer.ImportError.unreadable("The draw.io page could not be decompressed.")
            }
            let inner = Collector()
            let innerParser = XMLParser(data: Data(inflated.utf8))
            innerParser.delegate = inner
            innerParser.parse()
            cells = inner.cells
        }
        return build(from: cells)
    }

    static func inflate(_ base64: String) -> String? {
        guard let compressed = Data(base64Encoded: base64, options: .ignoreUnknownCharacters),
              let raw = try? (compressed as NSData).decompressed(using: .zlib) else { return nil }
        let text = String(decoding: raw as Data, as: UTF8.self)
        return text.removingPercentEncoding ?? text
    }

    private static func build(from cells: [Cell]) -> Diagram {
        var diagram = Diagram(name: "")
        let byID = Dictionary(cells.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let vertexIDs = Set(cells.filter { $0.vertex }.map { $0.id })
        let parentsWithChildren = Set(cells.filter { $0.vertex && vertexIDs.contains($0.parent) }.map { $0.parent })

        func absolute(_ cell: Cell) -> (Double, Double) {
            var x = cell.x, y = cell.y
            var parentID = cell.parent
            var guardCount = 0
            while let parent = byID[parentID], parent.vertex, guardCount < 20 {
                x += parent.x
                y += parent.y
                parentID = parent.parent
                guardCount += 1
            }
            return (x, y)
        }

        var nodeIDs: [String: UUID] = [:]
        for cell in cells where cell.vertex {
            let style = cell.style.lowercased()
            if style.hasPrefix("text;") || style.contains("edgelabel") { continue }
            let (x, y) = absolute(cell)
            let text = plainText(cell.value)
            let isContainer = parentsWithChildren.contains(cell.id) || style.contains("swimlane") || style.contains("container=1")
                || style.hasPrefix("group") || (cell.width >= 300 && cell.height >= 200 && style.contains("dashed=1"))
            if isContainer {
                let color = hexColor(in: cell.style, key: "strokecolor") ?? hexColor(in: cell.style, key: "fillcolor")
                    ?? DiagramZone.palette[diagram.zones.count % DiagramZone.palette.count]
                diagram.zones.append(DiagramZone(name: text.isEmpty ? "Zone" : text.replacingOccurrences(of: "\n", with: " "),
                                                 x: x, y: y, width: max(cell.width, 160), height: max(cell.height, 100), colorHex: color))
                continue
            }
            let parts = DiagramTransfer.splitLabel(text)
            let kindHint = (cell.style.range(of: #"luikKind=([A-Za-z]+)"#, options: .regularExpression).map { String(cell.style[$0].dropFirst("luikKind=".count)) })
            let kind = kindHint.flatMap { DiagramNodeKind(rawValue: $0) } ?? DiagramNodeKind.guess(from: cell.style + " " + text)
            var label = parts.label
            // The kind name added by Luik's own export is not part of the label.
            if label.hasSuffix(" " + kind.title) { label = String(label.dropLast(kind.title.count + 1)) }
            let node = DiagramNode(kind: kind, label: label.isEmpty ? kind.title : label, address: parts.address,
                                   x: x + cell.width / 2, y: y + cell.height / 2)
            diagram.nodes.append(node)
            nodeIDs[cell.id] = node.id
        }
        for cell in cells where cell.edge {
            guard let from = nodeIDs[cell.source], let to = nodeIDs[cell.target] else { continue }
            let style = cell.style.lowercased()
            let dotted = style.contains("dashpattern=1 ")
            let dashed = style.contains("dashed=1")
            let directed = !style.contains("endarrow=none")
            diagram.links.append(DiagramLink(from: from, to: to, label: plainText(cell.value).replacingOccurrences(of: "\n", with: " "),
                                             style: dotted ? .dotted : (dashed ? .dashed : .solid), directed: directed))
        }
        // Keep everything on the canvas.
        let minX = min(diagram.nodes.map { $0.x - Double(DiagramMetrics.nodeWidth) / 2 }.min() ?? 0, diagram.zones.map { $0.x }.min() ?? 0)
        let minY = min(diagram.nodes.map { $0.y - Double(DiagramMetrics.nodeHeight) / 2 }.min() ?? 0, diagram.zones.map { $0.y }.min() ?? 0)
        let dx = 40 - minX, dy = 40 - minY
        for index in diagram.nodes.indices {
            diagram.nodes[index].x += dx
            diagram.nodes[index].y += dy
        }
        for index in diagram.zones.indices {
            diagram.zones[index].x += dx
            diagram.zones[index].y += dy
        }
        return diagram
    }

    /// HTML labels → plain text with line breaks.
    static func plainText(_ html: String) -> String {
        var text = html
        text = text.replacingOccurrences(of: #"<br\s*/?>|</div>|</p>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        for (entity, character) in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&amp;", "&")] {
            text = text.replacingOccurrences(of: entity, with: character)
        }
        return text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private static func hexColor(in style: String, key: String) -> String? {
        guard let range = style.range(of: key + #"=#[0-9A-Fa-f]{6}"#, options: [.regularExpression, .caseInsensitive]) else { return nil }
        return String(style[range].suffix(7))
    }
}
