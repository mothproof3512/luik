import AppKit
import SwiftUI

/// Two panes side by side with a draggable divider. The divider position is a fraction of the
/// total width; it starts at `defaultFraction` and is remembered under `storageKey`, so a manual
/// adjustment sticks. Unlike HSplitView, the initial position does not depend on the panes'
/// ideal sizes, which made the detail pane open far too narrow.
struct SplitPane<Leading: View, Trailing: View>: View {
    let storageKey: String
    let defaultFraction: Double
    let minFraction: Double
    let maxFraction: Double
    let leading: () -> Leading
    let trailing: () -> Trailing

    @State private var fraction: Double
    @State private var hovering = false

    private static var dividerWidth: CGFloat { 9 }

    init(storageKey: String,
         defaultFraction: Double,
         minFraction: Double = 0.2,
         maxFraction: Double = 0.85,
         @ViewBuilder leading: @escaping () -> Leading,
         @ViewBuilder trailing: @escaping () -> Trailing) {
        self.storageKey = storageKey
        self.defaultFraction = defaultFraction
        self.minFraction = minFraction
        self.maxFraction = maxFraction
        self.leading = leading
        self.trailing = trailing
        let stored = UserDefaults.standard.object(forKey: storageKey) as? Double
        let initial = min(max(stored ?? defaultFraction, minFraction), maxFraction)
        _fraction = State(initialValue: initial)
    }

    var body: some View {
        GeometryReader { geometry in
            let total = geometry.size.width
            let leadingWidth = max(0, (total - SplitPane.dividerWidth) * fraction).rounded()
            HStack(spacing: 0) {
                leading()
                    .frame(width: leadingWidth)
                    .clipped()
                divider(total: total)
                trailing()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
            .coordinateSpace(name: "splitPane")
        }
    }

    private func divider(total: CGFloat) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.white.opacity(hovering ? 0.3 : 0.12))
                .frame(width: 1)
        }
        .frame(width: SplitPane.dividerWidth)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .onHover { inside in
            hovering = inside
            if inside {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
        .onDisappear {
            if hovering {
                hovering = false
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .named("splitPane"))
                .onChanged { value in
                    guard total > SplitPane.dividerWidth else { return }
                    let proposed = (value.location.x - SplitPane.dividerWidth / 2) / (total - SplitPane.dividerWidth)
                    fraction = min(max(proposed, minFraction), maxFraction)
                }
                .onEnded { _ in
                    UserDefaults.standard.set(fraction, forKey: storageKey)
                }
        )
        .help("Drag to resize; double-click to reset")
        .onTapGesture(count: 2) {
            fraction = defaultFraction
            UserDefaults.standard.set(fraction, forKey: storageKey)
        }
    }
}
