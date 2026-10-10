import AppKit
import Carbon
import SwiftUI

/// A field that "records" a hotkey: click it and press the key or combination you want.
/// Escape cancels, ⌫ clears the hotkey (= no hotkey).
struct HotKeyRecorder: NSViewRepresentable {
    /// Stored text form, e.g. "ctrl+grave"; empty = no hotkey.
    @Binding var value: String

    func makeNSView(context: Context) -> HotKeyRecorderView {
        let view = HotKeyRecorderView()
        view.comboString = value
        view.onChange = { newValue in
            value = newValue
        }
        return view
    }

    func updateNSView(_ nsView: HotKeyRecorderView, context: Context) {
        if nsView.comboString != value {
            nsView.comboString = value
        }
    }
}

final class HotKeyRecorderView: NSView {
    var onChange: ((String) -> Void)?

    var comboString: String = "" {
        didSet { needsDisplay = true }
    }

    private var isRecording = false {
        didSet { needsDisplay = true }
    }
    private var pressedModifiers: NSEvent.ModifierFlags = []
    private var localMonitor: Any?
    private var flashMessage: String? {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Record hotkey")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 220, height: 28)
    }

    override var acceptsFirstResponder: Bool { true }

    // MARK: Recording

    override func mouseDown(with event: NSEvent) {
        if isRecording {
            stopRecording()
        } else {
            window?.makeFirstResponder(self)
            startRecording()
        }
    }

    override func resignFirstResponder() -> Bool {
        stopRecording()
        return super.resignFirstResponder()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            stopRecording()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    private func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        pressedModifiers = []
        flashMessage = nil
        // Local monitor: catches the key before the main menu (⌘Q, ⌘W, …) claims it.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, self.isRecording else { return event }
            return self.handle(event) ? nil : event
        }
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        pressedModifiers = []
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    /// Returns true if the event was handled (and must not propagate).
    private func handle(_ event: NSEvent) -> Bool {
        switch event.type {
        case .flagsChanged:
            pressedModifiers = event.modifierFlags.intersection(HotKeyCombo.relevantModifiers)
            needsDisplay = true
            return true
        case .keyDown:
            let keyCode = UInt32(event.keyCode)
            let modifiers = event.modifierFlags.intersection(HotKeyCombo.relevantModifiers)
            if keyCode == UInt32(kVK_Escape) && modifiers.isEmpty {
                stopRecording()
                return true
            }
            if (keyCode == UInt32(kVK_Delete) || keyCode == UInt32(kVK_ForwardDelete)) && modifiers.isEmpty {
                comboString = ""
                onChange?("")
                stopRecording()
                return true
            }
            let combo = HotKeyCombo(keyCode: keyCode, modifiers: modifiers)
            if let problem = combo.problem {
                // Show the reason briefly in the field and keep recording.
                flashMessage = problem
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                    if self?.flashMessage == problem {
                        self?.flashMessage = nil
                    }
                }
                return true
            }
            comboString = combo.stringValue
            onChange?(combo.stringValue)
            stopRecording()
            return true
        default:
            return false
        }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        (isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.18) : NSColor.white.withAlphaComponent(0.06)).setFill()
        path.fill()
        (isRecording ? NSColor.controlAccentColor : NSColor.white.withAlphaComponent(0.25)).setStroke()
        path.lineWidth = 1
        path.stroke()

        let text: String
        var color = NSColor.labelColor
        var font = NSFont.systemFont(ofSize: 13, weight: .medium)
        if let flashMessage {
            text = flashMessage
            color = .systemOrange
            font = NSFont.systemFont(ofSize: 11)
        } else if isRecording {
            let symbols = HotKeyCombo.modifierSymbols(pressedModifiers)
            text = symbols.isEmpty ? "Press the key(s) you want…" : symbols + " …"
            color = .secondaryLabelColor
        } else if let combo = HotKeyCombo(string: comboString) {
            text = combo.displayString
        } else {
            text = "No hotkey — click to set one"
            color = .secondaryLabelColor
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
        let size = (text as NSString).size(withAttributes: attributes)
        let textRect = NSRect(x: rect.minX + 6, y: rect.midY - size.height / 2, width: rect.width - 12, height: size.height)
        (text as NSString).draw(in: textRect, withAttributes: attributes)
    }
}
