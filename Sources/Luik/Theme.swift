import AppKit
import SwiftUI

/// A colour scheme for the whole panel: background tint, accent, terminal text and cursor.
/// The built-in schemes are combinations from Sanzo Wada's "A Dictionary of Color Combinations"
/// (1933); the hex values come from the dataset by Matt DesLauriers (MIT licence). From each
/// combination the darkest colour becomes the panel tint (darkened so text stays readable), the
/// lightest the terminal text (lightened a little) and the most saturated one the accent.
struct LuikTheme: Identifiable, Equatable {
    struct Swatch: Equatable {
        let name: String
        let hex: String

        init(_ name: String, _ hex: String) {
            self.name = name
            self.hex = hex
        }
    }

    let id: String
    let name: String
    let detail: String
    let swatches: [Swatch]
    let background: String
    let foreground: String
    let accent: String

    var isDefault: Bool { id == "default" }

    var backgroundColor: Color { Color(nsColor: backgroundNS) }
    /// The default scheme keeps macOS's own accent colour (System Settings › Appearance).
    var accentColor: Color { isDefault ? Color.accentColor : Color(nsColor: accentNS) }
    var foregroundColor: Color { Color(nsColor: foregroundNS) }
    var backgroundNS: NSColor { NSColor(hex: background) }
    var accentNS: NSColor { isDefault ? NSColor.controlAccentColor : NSColor(hex: accent) }
    var foregroundNS: NSColor { NSColor(hex: foreground) }
    /// Terminal cursor: the accent, except for the default scheme which keeps its green caret.
    var cursorNS: NSColor { isDefault ? NSColor(calibratedRed: 0.55, green: 0.85, blue: 0.55, alpha: 1) : NSColor(hex: accent) }

    static let luik = LuikTheme(id: "default", name: "Luik", detail: "Dark blue-grey with the system accent colour",
                                swatches: [Swatch("Panel", "#12141a"), Swatch("Text", "#ebebeb"), Swatch("Cursor", "#8cd98c")],
                                background: "#12141a", foreground: "#ebebeb", accent: "#4f8ef7")

    /// Sanzo Wada combinations, by their number in the book.
    static let wada: [LuikTheme] = [
        LuikTheme(id: "wada-141", name: "No. 141", detail: "Orange · Yellow Green · Dark Tyrian Blue",
                  swatches: [Swatch("Orange", "#f37420"), Swatch("Yellow Green", "#afd472"), Swatch("Dark Tyrian Blue", "#12354e")],
                  background: "#092133", foreground: "#bedb94", accent: "#f37420"),
        LuikTheme(id: "wada-232", name: "No. 232", detail: "Carmine · Pinkish Cinnamon · Deep Indigo",
                  swatches: [Swatch("Carmine", "#cc1236"), Swatch("Pinkish Cinnamon", "#eeb480"), Swatch("Deep Indigo", "#051230")],
                  background: "#051230", foreground: "#f2caab", accent: "#d25f69"),
        LuikTheme(id: "wada-271", name: "No. 271", detail: "Pomegranite Purple · Cobalt Green · Green Blue · Deep Slate Green",
                  swatches: [Swatch("Pomegranite Purple", "#b71f57"), Swatch("Cobalt Green", "#96d1aa"), Swatch("Green Blue", "#099197"), Swatch("Deep Slate Green", "#112f2c")],
                  background: "#0b2321", foreground: "#b2dbbf", accent: "#c2687e"),
        LuikTheme(id: "wada-278", name: "No. 278", detail: "Cream Yellow · Olive Ocher · Cossack Green · Dusky Green",
                  swatches: [Swatch("Cream Yellow", "#fdbf68"), Swatch("Olive Ocher", "#d6b43e"), Swatch("Cossack Green", "#437742"), Swatch("Dusky Green", "#004f46")],
                  background: "#002520", foreground: "#fdc887", accent: "#d6b43e"),
        LuikTheme(id: "wada-253", name: "No. 253", detail: "Lemon Yellow · Apricot Orange · Cotinga Purple · Slate Color",
                  swatches: [Swatch("Lemon Yellow", "#f8ed43"), Swatch("Apricot Orange", "#f68c50"), Swatch("Cotinga Purple", "#501345"), Swatch("Slate Color", "#34454c")],
                  background: "#3b0c32", foreground: "#f8ed43", accent: "#f68c50"),
        LuikTheme(id: "wada-145", name: "No. 145", detail: "Brown · Citron Yellow · Dull Violet Black",
                  swatches: [Swatch("Brown", "#7c4226"), Swatch("Citron Yellow", "#b2b73e"), Swatch("Dull Violet Black", "#1e0e3f")],
                  background: "#1e0e3f", foreground: "#d2d5a8", accent: "#b2b73e"),
        LuikTheme(id: "wada-125", name: "No. 125", detail: "Fawn · Cerulian Blue · Violet Blue",
                  swatches: [Swatch("Fawn", "#d1b0a7"), Swatch("Cerulian Blue", "#0093a5"), Swatch("Violet Blue", "#40456a")],
                  background: "#1c1e32", foreground: "#e1cdc9", accent: "#0093a5"),
        LuikTheme(id: "wada-190", name: "No. 190", detail: "Ivory Buff · English Red · Black",
                  swatches: [Swatch("Ivory Buff", "#ebd3a2"), Swatch("English Red", "#d96629"), Swatch("Black", "#111314")],
                  background: "#111314", foreground: "#ebd3a2", accent: "#d96629"),
        LuikTheme(id: "wada-192", name: "No. 192", detail: "Cream Yellow · Vandyke Brown · Deep Violet / Plumbeous",
                  swatches: [Swatch("Cream Yellow", "#fdbf68"), Swatch("Vandyke Brown", "#4b3317"), Swatch("Deep Violet / Plumbeous", "#70727c")],
                  background: "#2c1c0a", foreground: "#fdc887", accent: "#fdbf68"),
        LuikTheme(id: "wada-157", name: "No. 157", detail: "Pansy Purple · Olive Ocher · Olympic Blue",
                  swatches: [Swatch("Pansy Purple", "#7d133a"), Swatch("Olive Ocher", "#d6b43e"), Swatch("Olympic Blue", "#5a82b3")],
                  background: "#43061c", foreground: "#e4d0a0", accent: "#6186b5"),
    ]

    static let all: [LuikTheme] = [luik] + wada

    static func theme(id: String?) -> LuikTheme {
        all.first { $0.id == id } ?? luik
    }

    /// The scheme chosen in Settings › Colours.
    static var current: LuikTheme {
        theme(id: UserDefaults.standard.string(forKey: SettingsKey.colorScheme))
    }
}

extension NSColor {
    /// "#rrggbb" (or "rrggbb"); anything else gives mid grey.
    convenience init(hex: String) {
        var value: UInt64 = 0
        let cleaned = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard cleaned.count == 6, Scanner(string: cleaned).scanHexInt64(&value) else {
            self.init(calibratedWhite: 0.5, alpha: 1)
            return
        }
        self.init(calibratedRed: CGFloat((value >> 16) & 0xFF) / 255,
                  green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255,
                  alpha: 1)
    }
}

private struct LuikThemeKey: EnvironmentKey {
    static let defaultValue = LuikTheme.luik
}

extension EnvironmentValues {
    /// The active colour scheme, set by RootView so every view can use `theme.accentColor`.
    var luikTheme: LuikTheme {
        get { self[LuikThemeKey.self] }
        set { self[LuikThemeKey.self] = newValue }
    }
}

/// One scheme in Settings › Colours: swatches, a sample of terminal text and the names.
struct ThemeCard: View {
    let scheme: LuikTheme
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    ForEach(Array(scheme.swatches.enumerated()), id: \.offset) { _, swatch in
                        Circle()
                            .fill(Color(nsColor: NSColor(hex: swatch.hex)))
                            .frame(width: 14, height: 14)
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.25)))
                            .help(swatch.name)
                    }
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(scheme.accentColor)
                    }
                }
                Text(scheme.name)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(scheme.foregroundColor)
                Text("user@host ~ % nmap -sV $RHOST")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(scheme.foregroundColor.opacity(0.85))
                    .lineLimit(1)
                Text(scheme.detail)
                    .font(.caption2)
                    .foregroundStyle(scheme.foregroundColor.opacity(0.6))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(scheme.backgroundColor, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isSelected ? scheme.accentColor : Color.white.opacity(0.12), lineWidth: isSelected ? 2 : 1))
        }
        .buttonStyle(.plain)
        .help(scheme.detail)
    }
}
