import AppKit

/// Thin strip along the bottom edge of the panel. Drag it to change the panel height (the new
/// height becomes the Height setting), double-click it to go back to the default height. A small
/// grip appears while the mouse is over it, and the cursor becomes the up/down resize arrow.
final class ResizeHandleView: NSView {
    /// Height of the strip that catches the mouse.
    static let thickness: CGFloat = 7

    /// Asked when a drag starts; return false when resizing is not possible right now.
    var onBegin: (() -> Bool)?
    /// Called while dragging, with the change in height since the drag started (positive = taller).
    var onDrag: ((CGFloat) -> Void)?
    var onEnd: (() -> Void)?
    var onReset: (() -> Void)?

    private let grip = NSView()
    private var dragStartY: CGFloat = 0
    private var dragging = false
    private var hovering = false
    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        grip.wantsLayer = true
        grip.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.45).cgColor
        grip.layer?.cornerRadius = 1.5
        grip.alphaValue = 0
        grip.translatesAutoresizingMaskIntoConstraints = false
        addSubview(grip)
        NSLayoutConstraint.activate([
            grip.centerXAnchor.constraint(equalTo: centerXAnchor),
            grip.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            grip.widthAnchor.constraint(equalToConstant: 44),
            grip.heightAnchor.constraint(equalToConstant: 3),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var acceptsFirstResponder: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// The grip must not swallow the mouse.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let view = super.hitTest(point)
        return view == nil ? nil : self
    }

    // MARK: Hover and cursor

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect],
                                  owner: self,
                                  userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.resizeUpDown.set()
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        showGrip(true)
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        if !dragging {
            showGrip(false)
            NSCursor.arrow.set()
        }
    }

    private func showGrip(_ visible: Bool) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            grip.animator().alphaValue = visible ? 1 : 0
        }
    }

    // MARK: Dragging

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onReset?()
            return
        }
        guard onBegin?() == true else { return }
        dragging = true
        dragStartY = NSEvent.mouseLocation.y
        showGrip(true)
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragging else { return }
        // The panel hangs from the top of the screen: moving the mouse down makes it taller.
        onDrag?(dragStartY - NSEvent.mouseLocation.y)
    }

    override func mouseUp(with event: NSEvent) {
        guard dragging else { return }
        dragging = false
        onEnd?()
        if !hovering {
            showGrip(false)
            NSCursor.arrow.set()
        }
    }
}
