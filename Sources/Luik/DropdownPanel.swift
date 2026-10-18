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
    /// Strip along the bottom edge: drag to change the height, double-click to reset it.
    private let resizeHandle = ResizeHandleView()
    private(set) var isShown = false
    private var isAnimating = false
    private var hideWhenAnimationEnds = false
    private var previousApp: NSRunningApplication?
    private var resizeStartFrame: NSRect?
    /// True while the bottom edge is being dragged (settings changes must not move the panel then).
    private(set) var isResizing = false

    /// Called once the panel is fully visible.
    var onDidShow: (() -> Void)?
    /// Called at the start of a themed entrance, so an overlay effect can play during it.
    var onWillShow: (() -> Void)?

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
        resizeHandle.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(resizeHandle)
        NSLayoutConstraint.activate([
            resizeHandle.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            resizeHandle.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            resizeHandle.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            resizeHandle.heightAnchor.constraint(equalToConstant: ResizeHandleView.thickness),
        ])
        resizeHandle.onBegin = { [weak self] in self?.beginResize() ?? false }
        resizeHandle.onDrag = { [weak self] delta in self?.resize(by: delta) }
        resizeHandle.onEnd = { [weak self] in self?.endResize() }
        resizeHandle.onReset = { [weak self] in self?.resetHeight() }
        panel.contentView = container
        applyCornerStyle()
    }

    // MARK: - Resizing with the mouse

    /// Smallest height the panel can be dragged to: a fifth of the screen, at least 160 pt.
    private func minimumHeight(on screen: NSScreen) -> CGFloat {
        max(160, (screen.visibleFrame.height * 0.2).rounded())
    }

    private func beginResize() -> Bool {
        guard isShown, !isAnimating else { return false }
        resizeStartFrame = panel.frame
        isResizing = true
        return true
    }

    /// Moves the bottom edge; the top edge stays where it is (the panel hangs from the top).
    private func resize(by delta: CGFloat) {
        guard isResizing, let start = resizeStartFrame, let screen = panel.screen ?? currentScreen() else { return }
        let visible = screen.visibleFrame
        let maxHeight = start.maxY - visible.minY   // down to the Dock / bottom of the screen
        let height = min(max((start.height + delta).rounded(), minimumHeight(on: screen)), maxHeight)
        let frame = NSRect(x: start.minX, y: start.maxY - height, width: start.width, height: height)
        if frame != panel.frame {
            panel.setFrame(frame, display: true)
        }
    }

    /// Stores the new height as the Height setting (as a fraction of the screen, like the slider).
    private func endResize() {
        guard isResizing else { return }
        isResizing = false
        resizeStartFrame = nil
        panel.invalidateShadow()
        guard let screen = panel.screen ?? currentScreen() else { return }
        let fraction = min(max(Double(panel.frame.height / screen.visibleFrame.height), 0.2), 1.0)
        UserDefaults.standard.set(fraction, forKey: SettingsKey.heightFraction)
    }

    /// Double-click on the bottom edge: back to the default height, with a short animation.
    private func resetHeight() {
        guard isShown, !isAnimating, !isResizing, let screen = panel.screen ?? currentScreen() else { return }
        let fraction = SettingsDefaults.defaultHeightFraction
        let visible = screen.visibleFrame
        let height = (visible.height * fraction).rounded()
        let current = panel.frame
        let frame = NSRect(x: current.minX, y: current.maxY - height, width: current.width, height: height)
        isResizing = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.panel.animator().setFrame(frame, display: true)
        }, completionHandler: {
            self.isResizing = false
            self.panel.invalidateShadow()
            UserDefaults.standard.set(fraction, forKey: SettingsKey.heightFraction)
        })
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

        // Themed entrance (Settings › Colours): the panel itself arrives the way its scheme does.
        if UserDefaults.standard.bool(forKey: SettingsKey.themeIntro), let layer = container.layer,
           ThemeEntrance.duration(for: LuikTheme.current) != nil {
            panel.setFrame(endFrame, display: true)
            panel.alphaValue = 1
            panel.hasShadow = false   // the window shadow would stay rectangular while the content moves
            onWillShow?()
            let played = ThemeEntrance.play(on: layer, size: endFrame.size, theme: LuikTheme.current) {
                self.panel.hasShadow = true
                finish()
            }
            if played { return }
            panel.hasShadow = true
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
        guard isShown, !isAnimating, !isResizing else { return }
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
