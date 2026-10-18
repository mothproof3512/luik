import AppKit
import SwiftUI

/// Colours of a drawing: dark for the panel, light for reports.
struct DiagramPalette {
    let background: Color
    let card: Color
    let cardBorder: Color
    let text: Color
    let secondaryText: Color
    let link: Color
    let grid: Color
    let accent: Color
    var isLight = false

    static func dark(accent: Color) -> DiagramPalette {
        DiagramPalette(background: Color(white: 0.09), card: Color(white: 0.17), cardBorder: Color.white.opacity(0.10),
                       text: .white, secondaryText: Color.white.opacity(0.6), link: Color.white.opacity(0.45),
                       grid: Color.white.opacity(0.07), accent: accent)
    }

    static func light(accent: Color) -> DiagramPalette {
        DiagramPalette(background: .white, card: .white, cardBorder: Color.black.opacity(0.12),
                       text: Color(white: 0.1), secondaryText: Color(white: 0.4), link: Color(white: 0.45),
                       grid: Color.black.opacity(0.06), accent: accent, isLight: true)
    }
}

/// Maps diagram units to view points: zoom, plus an origin (for exports that start at the bounds).
struct DiagramGeometry {
    var zoom: CGFloat
    var origin: CGPoint = .zero

    func point(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: (CGFloat(x) - origin.x) * zoom, y: (CGFloat(y) - origin.y) * zoom)
    }

    func toDiagram(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x / zoom + origin.x, y: p.y / zoom + origin.y)
    }

    /// Where the line from `center` towards `toward` leaves the node's card (plus a small gap).
    /// `width` is the card's width in diagram units (`node.width`).
    func edgePoint(from center: CGPoint, toward other: CGPoint, width: Double = Double(DiagramMetrics.nodeWidth)) -> CGPoint {
        let dx = other.x - center.x
        let dy = other.y - center.y
        guard abs(dx) > 0.001 || abs(dy) > 0.001 else { return center }
        let halfW = CGFloat(width) * zoom / 2 + 4 * zoom
        let halfH = DiagramMetrics.nodeHeight * zoom / 2 + 4 * zoom
        let tx = abs(dx) > 0.001 ? halfW / abs(dx) : .greatestFiniteMagnitude
        let ty = abs(dy) > 0.001 ? halfH / abs(dy) : .greatestFiniteMagnitude
        let t = min(tx, ty, 1)
        return CGPoint(x: center.x + dx * t, y: center.y + dy * t)
    }
}

/// One device: an icon disc in the kind's colour, the label and the address.
struct DiagramNodeView: View {
    let node: DiagramNode
    let zoom: CGFloat
    let palette: DiagramPalette
    var selected = false
    var highlighted = false

    var body: some View {
        let kind = node.kind
        HStack(spacing: 9 * zoom) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [kind.color.opacity(0.95), kind.color.opacity(0.7)], startPoint: .top, endPoint: .bottom))
                Image(systemName: kind.symbol)
                    .font(.system(size: 15 * zoom, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 34 * zoom, height: 34 * zoom)
            VStack(alignment: .leading, spacing: 1 * zoom) {
                Text(node.label.isEmpty ? kind.title : node.label)
                    .font(.system(size: 12 * zoom, weight: .semibold))
                    .foregroundStyle(palette.text)
                    .lineLimit(1)
                Text(node.detailText)
                    .font(.system(size: 10 * zoom, design: node.detailIsAddress ? .monospaced : .default))
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10 * zoom)
        .frame(width: CGFloat(node.width) * zoom, height: DiagramMetrics.nodeHeight * zoom)
        .background(
            // Shadow on the shape only: shadowing the whole card (text included) renders the view
            // offscreen and blurs it on every move, which is what made dragging stutter.
            RoundedRectangle(cornerRadius: 12 * zoom, style: .continuous)
                .fill(palette.card)
                .shadow(color: .black.opacity(0.3), radius: 5 * zoom, y: 2 * zoom)
        )
        .overlay(alignment: .leading) {
            // A thin bar in the kind's colour on the left edge.
            Rectangle()
                .fill(kind.color)
                .frame(width: 4 * zoom)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12 * zoom, style: .continuous)
                .strokeBorder(selected || highlighted ? palette.accent : palette.cardBorder, lineWidth: selected ? 2 : (highlighted ? 2 : 1))
        )
        .clipShape(RoundedRectangle(cornerRadius: 12 * zoom, style: .continuous))
    }
}

/// A network segment: tinted, rounded, with its name in a tab at the top left.
struct DiagramZoneView: View {
    let zone: DiagramZone
    let zoom: CGFloat
    let palette: DiagramPalette
    var selected = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 16 * zoom, style: .continuous)
                .fill(zone.color.opacity(0.08))
            RoundedRectangle(cornerRadius: 16 * zoom, style: .continuous)
                .strokeBorder(zone.color.opacity(selected ? 0.9 : 0.45),
                              style: StrokeStyle(lineWidth: selected ? 2 : 1.2, dash: [6 * zoom, 4 * zoom]))
            Text(zone.name)
                .font(.system(size: 11 * zoom, weight: .semibold))
                .foregroundStyle(zone.color)
                .lineLimit(1)
                .padding(.horizontal, 8 * zoom)
                .padding(.vertical, 3 * zoom)
                .background(zone.color.opacity(0.16), in: Capsule())
                .padding(8 * zoom)
        }
        .frame(width: CGFloat(zone.width) * zoom, height: CGFloat(zone.height) * zoom)
    }
}

/// A straight line between two points.
struct DiagramLineShape: Shape {
    let from: CGPoint
    let to: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        return path
    }
}

/// A filled arrowhead at `tip`, pointing away from `from`.
struct DiagramArrowShape: Shape {
    let from: CGPoint
    let tip: CGPoint
    let size: CGFloat

    func path(in rect: CGRect) -> Path {
        let angle = atan2(tip.y - from.y, tip.x - from.x)
        let spread: CGFloat = .pi / 7
        var path = Path()
        path.move(to: tip)
        path.addLine(to: CGPoint(x: tip.x - size * cos(angle - spread), y: tip.y - size * sin(angle - spread)))
        path.addLine(to: CGPoint(x: tip.x - size * cos(angle + spread), y: tip.y - size * sin(angle + spread)))
        path.closeSubpath()
        return path
    }
}

/// A link with its optional arrow and label.
struct DiagramLinkView: View {
    let from: CGPoint
    let to: CGPoint
    let link: DiagramLink
    let zoom: CGFloat
    let palette: DiagramPalette
    var selected = false

    var body: some View {
        let color = selected ? palette.accent : palette.link
        ZStack {
            DiagramLineShape(from: from, to: to)
                .stroke(color, style: StrokeStyle(lineWidth: (selected ? 2.5 : 1.8) * zoom, lineCap: .round,
                                                  dash: link.style.dash.map { $0 * zoom }))
            if link.directed {
                DiagramArrowShape(from: from, tip: to, size: 9 * zoom)
                    .fill(color)
            }
            if !link.label.isEmpty {
                Text(link.label)
                    .font(.system(size: 10 * zoom, weight: .medium))
                    .foregroundStyle(palette.text)
                    .lineLimit(1)
                    .padding(.horizontal, 6 * zoom)
                    .padding(.vertical, 2 * zoom)
                    .background(palette.background.opacity(0.95), in: Capsule())
                    .overlay(Capsule().strokeBorder(color.opacity(0.6), lineWidth: 1))
                    .position(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
            }
        }
    }
}

/// Dots every grid step, behind everything.
struct DiagramGridView: View {
    let zoom: CGFloat
    let color: Color

    var body: some View {
        Canvas { context, size in
            let step = CGFloat(DiagramMetrics.grid) * zoom * 2
            guard step > 4 else { return }
            var y: CGFloat = step
            while y < size.height {
                var x: CGFloat = step
                while x < size.width {
                    context.fill(Path(ellipseIn: CGRect(x: x - 1, y: y - 1, width: 2, height: 2)), with: .color(color))
                    x += step
                }
                y += step
            }
        }
    }
}

/// The whole diagram without any interaction — used for PNG export and the clipboard.
struct DiagramStaticDrawing: View {
    let diagram: Diagram
    let palette: DiagramPalette
    var padding: CGFloat = 40
    var showGrid = false

    var body: some View {
        let bounds = diagram.bounds
        let geometry = DiagramGeometry(zoom: 1, origin: CGPoint(x: bounds.minX - padding, y: bounds.minY - padding))
        let size = CGSize(width: bounds.width + 2 * padding, height: bounds.height + 2 * padding)
        ZStack(alignment: .topLeading) {
            palette.background
            if showGrid {
                DiagramGridView(zoom: 1, color: palette.grid)
            }
            ForEach(diagram.zones) { zone in
                DiagramZoneView(zone: zone, zoom: 1, palette: palette)
                    .position(x: geometry.point(zone.x + zone.width / 2, zone.y + zone.height / 2).x,
                              y: geometry.point(zone.x + zone.width / 2, zone.y + zone.height / 2).y)
            }
            ForEach(diagram.links) { link in
                if let a = diagram.node(link.from), let b = diagram.node(link.to) {
                    let ca = geometry.point(a.x, a.y)
                    let cb = geometry.point(b.x, b.y)
                    DiagramLinkView(from: geometry.edgePoint(from: ca, toward: cb, width: a.width), to: geometry.edgePoint(from: cb, toward: ca, width: b.width),
                                    link: link, zoom: 1, palette: palette)
                }
            }
            ForEach(diagram.nodes) { node in
                DiagramNodeView(node: node, zoom: 1, palette: palette)
                    .position(geometry.point(node.x, node.y))
            }
        }
        .frame(width: size.width, height: size.height)
    }
}
