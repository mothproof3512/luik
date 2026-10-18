import AppKit
import SwiftUI

/// A short opening effect when the panel drops down, one per "Screens and consoles" scheme:
/// drawn procedurally in a Canvas (lines, glyphs, bars — no artwork), about a second long, then
/// it fades and the panel is just the panel. Settings › Colours switches it off.
struct ThemeIntroView: View {
    let theme: LuikTheme
    let token: Int
    let onFinished: () -> Void

    @State private var start = Date()

    static let duration: Double = 1.1

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = min(max(timeline.date.timeIntervalSince(start) / ThemeIntroView.duration, 0), 1)
            Canvas(rendersAsynchronously: false) { context, size in
                ThemeIntro.draw(theme: theme, progress: t, context: &context, size: size)
            }
            .opacity(t < 0.75 ? 1 : max(0, 1 - (t - 0.75) / 0.25))
            .onChange(of: t >= 1) { _, done in
                if done { onFinished() }
            }
        }
        .allowsHitTesting(false)
        .onAppear { start = Date() }
        .id(token)
    }
}

enum ThemeIntro {
    /// Schemes that have an effect.
    static func hasEffect(_ theme: LuikTheme) -> Bool {
        theme.id.hasPrefix("screen-")
    }

    static func draw(theme: LuikTheme, progress t: Double, context: inout GraphicsContext, size: CGSize) {
        let accent = theme.accentColor
        let fg = theme.foregroundColor
        var rng = SeededRandom(seed: 7)
        switch theme.id {
        case "screen-bridge":
            // Rounded bars sweeping in from the left, in the panel colours.
            let colors: [Color] = [accent, Color(hex: "#cc99cc"), Color(hex: "#ffcc66"), accent, Color(hex: "#99ccff")]
            let rows = 6
            for row in 0..<rows {
                let delay = Double(row) * 0.08
                let p = min(max((t - delay) / 0.45, 0), 1)
                let eased = 1 - pow(1 - p, 3)
                let height = size.height / Double(rows) * 0.55
                let y = size.height / Double(rows) * Double(row) + height * 0.4
                let width = size.width * (0.25 + 0.5 * Double((row * 37) % 10) / 10) * eased
                let rect = CGRect(x: -20, y: y, width: width + 20, height: height)
                context.fill(Path(roundedRect: rect, cornerRadius: height / 2), with: .color(colors[row % colors.count].opacity(0.85 * (1 - p * 0.3))))
            }
        case "screen-chevron":
            // A ring of nine markers lighting up in turn, then a ripple from the centre.
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) * 0.32
            context.stroke(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)), with: .color(fg.opacity(0.25)), lineWidth: 6)
            for i in 0..<9 {
                let lit = t > Double(i) / 9 * 0.7
                let angle = -Double.pi / 2 + Double(i) * 2 * Double.pi / 9
                let p = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
                context.fill(Path(ellipseIn: CGRect(x: p.x - 7, y: p.y - 7, width: 14, height: 14)), with: .color(lit ? accent : fg.opacity(0.2)))
            }
            if t > 0.7 {
                let r = radius * (t - 0.7) / 0.3 * 1.6
                context.stroke(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)), with: .color(accent.opacity(1 - (t - 0.7) / 0.3)), lineWidth: 3)
                context.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)), with: .color(accent.opacity(0.25 * (1 - (t - 0.7) / 0.3))))
            }
        case "screen-rebel":
            // Grid lines converging to a crosshair.
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let n = 12
            for i in 0...n {
                let f = Double(i) / Double(n)
                let x = size.width * f
                let y = size.height * f
                let reach = min(t / 0.6, 1)
                context.stroke(Path { $0.move(to: CGPoint(x: x, y: 0)); $0.addLine(to: CGPoint(x: x, y: size.height * reach)) }, with: .color(Color(hex: "#ff3b3b").opacity(0.35)), lineWidth: 1)
                context.stroke(Path { $0.move(to: CGPoint(x: 0, y: y)); $0.addLine(to: CGPoint(x: size.width * reach, y: y)) }, with: .color(Color(hex: "#ff3b3b").opacity(0.35)), lineWidth: 1)
            }
            let s = max(0, 1 - t / 0.8) * min(size.width, size.height) * 0.6 + 40
            var cross = Path()
            cross.addEllipse(in: CGRect(x: center.x - s / 2, y: center.y - s / 2, width: s, height: s))
            cross.move(to: CGPoint(x: center.x - s * 0.7, y: center.y)); cross.addLine(to: CGPoint(x: center.x + s * 0.7, y: center.y))
            cross.move(to: CGPoint(x: center.x, y: center.y - s * 0.7)); cross.addLine(to: CGPoint(x: center.x, y: center.y + s * 0.7))
            context.stroke(cross, with: .color(Color(hex: "#5ee6ff")), lineWidth: 2)
        case "screen-wopr":
            // Dotted map lines and a typed status line with a blinking block cursor.
            for i in 0..<14 {
                let y = size.height * (0.15 + 0.7 * Double(i) / 13)
                let width = size.width * min(t / 0.5, 1)
                context.stroke(Path { $0.move(to: CGPoint(x: 0, y: y)); $0.addLine(to: CGPoint(x: width, y: y)) },
                               with: .color(Color(hex: "#2b6cb0").opacity(0.5)), style: StrokeStyle(lineWidth: 1, dash: [2, 6]))
            }
            let message = "SYSTEM READY"
            let shown = String(message.prefix(Int(Double(message.count) * min(t / 0.6, 1))))
            let text = Text(shown + ((Int(t * 8) % 2 == 0) ? "█" : " ")).font(.system(size: 28, weight: .bold, design: .monospaced)).foregroundStyle(Color(hex: "#9fd3ff"))
            context.draw(text, at: CGPoint(x: 40, y: size.height * 0.5), anchor: .leading)
        case "screen-gibson":
            // Wireframe towers rising from a vanishing point.
            let base = size.height * 0.85
            for i in 0..<9 {
                let f = Double(i) / 8
                let x = size.width * (0.1 + 0.8 * f)
                let h = size.height * (0.2 + 0.5 * Double(rng.next() % 100) / 100) * min(t / 0.7, 1)
                let w = size.width * 0.06
                let rect = CGRect(x: x - w / 2, y: base - h, width: w, height: h)
                context.stroke(Path(rect), with: .color(i % 2 == 0 ? accent : Color(hex: "#ff2bd6")), lineWidth: 1.5)
                var inner = Path()
                var y = rect.minY + 8
                while y < rect.maxY {
                    inner.move(to: CGPoint(x: rect.minX, y: y)); inner.addLine(to: CGPoint(x: rect.maxX, y: y))
                    y += 12
                }
                context.stroke(inner, with: .color(fg.opacity(0.2)), lineWidth: 0.5)
            }
            context.stroke(Path { $0.move(to: CGPoint(x: 0, y: base)); $0.addLine(to: CGPoint(x: size.width, y: base)) }, with: .color(accent.opacity(0.6)), lineWidth: 1)
        case "screen-rain":
            // Falling glyph columns.
            let glyphs = Array("ｱｲｳｴｵｶｷｸｹｺ0123456789ABCDEFZ")
            let columnWidth: Double = 16
            let columns = Int(size.width / columnWidth)
            for c in 0..<columns {
                let speed = 0.6 + Double(rng.next() % 100) / 100
                let offset = Double(rng.next() % 100) / 100
                let headY = (t * speed + offset).truncatingRemainder(dividingBy: 1.2) * size.height * 1.3 - size.height * 0.2
                for k in 0..<14 {
                    let y = headY - Double(k) * 16
                    guard y > -16, y < size.height else { continue }
                    let glyph = String(glyphs[Int(rng.next() % UInt64(glyphs.count))])
                    let alpha = k == 0 ? 1.0 : max(0, 0.9 - Double(k) * 0.07)
                    let color = k == 0 ? Color.white : accent
                    let text = Text(glyph).font(.system(size: 14, weight: .medium, design: .monospaced)).foregroundStyle(color.opacity(alpha))
                    context.draw(text, at: CGPoint(x: Double(c) * columnWidth + 8, y: y), anchor: .center)
                }
            }
        case "screen-section9":
            // Horizontal scan bands with hex readouts.
            let band = size.height * min(t / 0.7, 1)
            context.fill(Path(CGRect(x: 0, y: band - 3, width: size.width, height: 6)), with: .color(accent.opacity(0.8)))
            context.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: band)), with: .color(accent.opacity(0.06)))
            for i in 0..<10 {
                let y = size.height * (0.1 + 0.8 * Double(i) / 9)
                guard y < band else { continue }
                let hex = String(format: "%08llX  %04llX  %02llX", rng.next() & 0xFFFFFFFF, rng.next() & 0xFFFF, rng.next() & 0xFF)
                let text = Text(hex).font(.system(size: 12, design: .monospaced)).foregroundStyle((i % 3 == 0 ? Color(hex: "#ff7a1a") : fg).opacity(0.7))
                context.draw(text, at: CGPoint(x: size.width * (0.05 + 0.6 * Double((i * 7) % 5) / 5), y: y), anchor: .leading)
            }
        case "screen-grid":
            // Perspective floor grid with a light trail.
            let horizon = size.height * 0.45
            let center = size.width / 2
            for i in -8...8 {
                let xBottom = center + Double(i) * size.width / 8
                context.stroke(Path { $0.move(to: CGPoint(x: center + Double(i) * 6, y: horizon)); $0.addLine(to: CGPoint(x: xBottom, y: size.height)) },
                               with: .color(accent.opacity(0.5)), lineWidth: 1)
            }
            for k in 0..<8 {
                let f = pow((Double(k) / 8 + t * 0.2).truncatingRemainder(dividingBy: 1), 2.2)
                let y = horizon + (size.height - horizon) * f
                context.stroke(Path { $0.move(to: CGPoint(x: 0, y: y)); $0.addLine(to: CGPoint(x: size.width, y: y)) }, with: .color(accent.opacity(0.5)), lineWidth: 1)
            }
            let trailX = size.width * min(t / 0.8, 1)
            context.stroke(Path { $0.move(to: CGPoint(x: 0, y: size.height * 0.72)); $0.addLine(to: CGPoint(x: trailX, y: size.height * 0.72)) },
                           with: .color(Color(hex: "#ff6a00")), lineWidth: 4)
            context.fill(Path(ellipseIn: CGRect(x: trailX - 6, y: size.height * 0.72 - 6, width: 12, height: 12)), with: .color(.white))
        case "screen-november":
            // Broadcast interference: vertical static bars that settle, over a red wash.
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(accent.opacity(0.35 * (1 - t))))
            let bars = 40
            for i in 0..<bars {
                let x = size.width * Double(i) / Double(bars)
                let jitter = Double(rng.next() % 100) / 100 * (1 - t)
                let h = size.height * (0.2 + 0.8 * jitter)
                context.fill(Path(CGRect(x: x, y: (size.height - h) / 2, width: size.width / Double(bars) * 0.6, height: h)), with: .color(fg.opacity(0.12 * (1 - t) + 0.02)))
            }
            let gold = Color(hex: "#d4a017")
            let w = size.width * 0.5 * min(t / 0.5, 1)
            context.stroke(Path { $0.move(to: CGPoint(x: size.width / 2 - w / 2, y: size.height / 2)); $0.addLine(to: CGPoint(x: size.width / 2 + w / 2, y: size.height / 2)) }, with: .color(gold), lineWidth: 2)
        case "screen-basement":
            // CRT power-on: a bright line that opens to the full screen, with a flicker.
            let open = min(t / 0.5, 1)
            let eased = 1 - pow(1 - open, 3)
            let h = max(2, size.height * eased)
            let flicker = t > 0.5 && t < 0.62 && Int(t * 40) % 2 == 0 ? 0.6 : 1.0
            context.fill(Path(CGRect(x: 0, y: (size.height - h) / 2, width: size.width, height: h)), with: .color(fg.opacity(0.25 * (1 - open) + 0.04)))
            context.fill(Path(CGRect(x: 0, y: size.height / 2 - 1.5, width: size.width, height: 3)), with: .color(.white.opacity((1 - open) * flicker)))
            var scan = Path()
            var y = 0.0
            while y < size.height { scan.move(to: CGPoint(x: 0, y: y)); scan.addLine(to: CGPoint(x: size.width, y: y)); y += 4 }
            context.stroke(scan, with: .color(.black.opacity(0.18 * open)), lineWidth: 1)
        case "screen-incubator":
            // Bars rising on a whiteboard-style chart and a blinking prompt.
            let bars = 7
            for i in 0..<bars {
                let f = Double(i) / Double(bars - 1)
                let x = size.width * (0.15 + 0.7 * f)
                let target = size.height * (0.15 + 0.5 * f)
                let h = target * min(max((t - Double(i) * 0.06) / 0.5, 0), 1)
                context.fill(Path(roundedRect: CGRect(x: x - 14, y: size.height * 0.8 - h, width: 28, height: h), cornerRadius: 4), with: .color(i == bars - 1 ? accent : Color(hex: "#2d7ff9").opacity(0.8)))
            }
            let prompt = Text("$ " + ((Int(t * 6) % 2 == 0) ? "▍" : " ")).font(.system(size: 22, weight: .semibold, design: .monospaced)).foregroundStyle(fg)
            context.draw(prompt, at: CGPoint(x: size.width * 0.15 - 14, y: size.height * 0.88), anchor: .leading)
        default:
            break
        }
    }
}

/// Deterministic pseudo-random numbers, so each frame draws the same scene.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 | 1 }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

extension Color {
    init(hex: String) {
        self.init(nsColor: NSColor(hex: hex))
    }
}
