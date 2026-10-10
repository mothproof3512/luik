import AppKit
import QuartzCore
import SwiftUI

/// Borderless panel that can take keyboard focus and may sit partly off-screen
/// (needed for the slide animation from the top edge).
final class DropdownPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

/// Implements the Guake-like behaviour: show from the top edge of the screen the mouse is on,
/// hide with an animation, and hand focus back to the previous app.
/// All methods must be called on the main thread.
final class DropdownController {
    let panel: DropdownPanel
    /// Non-flipped container that rounds and clips the content (NSHostingView itself is
    /// flipped, so corner masks on it would hit the wrong corners).
    private let container = NSView()
    private(set) var isShown = false
    private var isAnimating = false
    private var hideWhenAnimationEnds = false
    private var previousApp: NSRunningApplication?

    /// Called once the panel is fully visible.
    var onDidShow: (() -> Void)?

    init<Content: View>(rootView: Content) {
        panel = DropdownPanel(contentRect: NSRect(x: 0, y: 0, width: 900, height: 500),
                              styleMask: [.borderless],
                              backing: .buffered,
                              defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.isMovable = false
        panel.appearance = NSAppearance(named: .darkAqua)

        container.wantsLayer = true
        container.layer?.masksToBounds = true
        container.layer?.backgroundColor = NSColor.clear.cgColor

        let hosting = NSHostingView(rootView: rootView)
        hosting.sizingOptions = []
        hosting.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        panel.contentView = container
        applyCornerStyle()
    }

    // MARK: - Appearance

    /// Rounded corners per the settings (radius, and whether the top corners join in).
    func applyCornerStyle() {
        let defaults = UserDefaults.standard
        let radius = CGFloat(min(max(defaults.double(forKey: SettingsKey.cornerRadius), 0), 60))
        let top = defaults.bool(forKey: SettingsKey.roundTopCorners)
        container.layer?.cornerRadius = radius
        // The container is not flipped: MinY = bottom.
        var corners: CACornerMask = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        if top {
            corners.formUnion([.layerMinXMaxYCorner, .layerMaxXMaxYCorner])
        }
        container.layer?.maskedCorners = corners
        if #available(macOS 10.15, *) {
            container.layer?.cornerCurve = .continuous
        }
    }

    private var animationDuration: TimeInterval {
        min(max(UserDefaults.standard.double(forKey: SettingsKey.animationDuration), 0), 1.0)
    }

    // MARK: - Geometry

    private func currentScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }

    private func targetFrame(on screen: NSScreen) -> NSRect {
        let defaults = UserDefaults.standard
        let heightFraction = min(max(defaults.double(forKey: SettingsKey.heightFraction), 0.2), 1.0)
        let widthFraction = min(max(defaults.double(forKey: SettingsKey.widthFraction), 0.3), 1.0)
        let visible = screen.visibleFrame // excludes menu bar and Dock
        let width = (visible.width * widthFraction).rounded()
        let height = (visible.height * heightFraction).rounded()
        let x = (visible.midX - width / 2).rounded()
        return NSRect(x: x, y: visible.maxY - height, width: width, height: height)
    }

    // MARK: - Show / hide

    /// Remember which app was active, so it gets focus back after hiding.
    private func rememberFrontmostApp() {
        let front = NSWorkspace.shared.frontmostApplication
        if let front, front.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp = front
        }
    }

    func show() {
        guard !isAnimating else { return }
        hideWhenAnimationEnds = false
        if isShown {
            rememberFrontmostApp()
            NSApp.unhide(nil)
            NSApp.activate()
            panel.makeKeyAndOrderFront(nil)
            return
        }
        guard let screen = currentScreen() else { return }
        rememberFrontmostApp()

        let endFrame = targetFrame(on: screen)
        let startFrame = NSRect(x: endFrame.minX, y: endFrame.maxY, width: endFrame.width, height: endFrame.height)
        panel.setFrame(startFrame, display: false)
        panel.alphaValue = 0
        isShown = true
        isAnimating = true

        NSApp.unhide(nil)
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)

        let finish = {
            self.isAnimating = false
            self.panel.invalidateShadow()
            if self.hideWhenAnimationEnds {
                self.hideWhenAnimationEnds = false
                self.hide(restoreFocus: false)
            } else {
                self.onDidShow?()
            }
        }

        let duration = animationDuration
        if duration < 0.02 {
            // No animation: straight into place.
            panel.setFrame(endFrame, display: true)
            panel.alphaValue = 1
            DispatchQueue.main.async(execute: finish)
            return
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.panel.animator().setFrame(endFrame, display: true)
            self.panel.animator().alphaValue = 1
        }, completionHandler: finish)
    }

    func hide(restoreFocus: Bool = true) {
        guard isShown else { return }
        if isAnimating {
            // Request arrived during the slide animation: hide once it finishes.
            hideWhenAnimationEnds = true
            return
        }
        isShown = false
        isAnimating = true

        let frame = panel.frame
        let upFrame = NSRect(x: frame.minX, y: frame.maxY, width: frame.width, height: frame.height)
        let appToRestore = restoreFocus ? previousApp : nil
        previousApp = nil

        let finish = {
            self.isAnimating = false
            self.panel.orderOut(nil)
            if restoreFocus {
                self.handBackFocus(to: appToRestore)
            }
        }

        // Sliding in is slightly faster than sliding out; that feels more natural.
        let duration = animationDuration * 0.85
        if duration < 0.02 {
            panel.alphaValue = 0
            DispatchQueue.main.async(execute: finish)
            return
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.panel.animator().setFrame(upFrame, display: true)
            self.panel.animator().alphaValue = 0
        }, completionHandler: finish)
    }

    /// Hands activation back to the app that was active before Luik appeared.
    /// macOS 14+ uses "cooperative activation": yield first, then activate. If Luik still ends up
    /// as the active app (with no visible window), Luik hides itself so macOS passes activation to
    /// the next app. Otherwise that app would get mouse input but no keyboard input.
    private func handBackFocus(to app: NSRunningApplication?) {
        guard NSApp.isActive else { return } // another app is already active
        if let app, !app.isTerminated, app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            NSApp.yieldActivation(to: app)
            app.activate(options: [])
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if NSApp.isActive && !self.isShown {
                NSApp.hide(nil)
            }
        }
    }

    func toggle() {
        if isShown && NSApp.isActive {
            hide()
        } else {
            show()
        }
    }

    /// Re-apply size and corners after the settings changed.
    func relayoutIfShown() {
        applyCornerStyle()
        guard isShown, !isAnimating else { return }
        guard let screen = panel.screen ?? currentScreen() else { return }
        let frame = targetFrame(on: screen)
        if frame != panel.frame {
            panel.setFrame(frame, display: true)
        }
        // The window shadow depends on the content's opacity; recompute it so it is
        // correct after the transparency changed.
        DispatchQueue.main.async {
            self.panel.invalidateShadow()
        }
    }
}
