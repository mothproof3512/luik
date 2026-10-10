import AppKit
import Carbon
import Foundation

/// A global hotkey: a key (Carbon key code) plus modifiers.
/// Stored as text, e.g. "f12", "ctrl+grave" or "cmd+shift+space".
struct HotKeyCombo: Equatable {
    var keyCode: UInt32
    var modifiers: NSEvent.ModifierFlags   // only .command, .option, .control, .shift

    static let defaultCombo = HotKeyCombo(keyCode: UInt32(kVK_F12), modifiers: [])
    static let relevantModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    // MARK: Text form

    /// "cmd+shift+space" → HotKeyCombo. Empty or unknown → nil (= no hotkey).
    /// Older versions stored "ctrl-grave" (with dashes); that form is understood too.
    init?(string: String) {
        let normalized = string.lowercased().replacingOccurrences(of: "-", with: "+")
        let parts = normalized.split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let keyPart = parts.last, let keyCode = HotKeyCombo.keyCode(forName: keyPart) else { return nil }
        var flags: NSEvent.ModifierFlags = []
        for part in parts.dropLast() {
            switch part {
            case "cmd", "command": flags.insert(.command)
            case "opt", "option", "alt": flags.insert(.option)
            case "ctrl", "control": flags.insert(.control)
            case "shift": flags.insert(.shift)
            default: return nil
            }
        }
        self.init(keyCode: keyCode, modifiers: flags)
    }

    init(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(HotKeyCombo.relevantModifiers)
    }

    var stringValue: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("ctrl") }
        if modifiers.contains(.option) { parts.append("opt") }
        if modifiers.contains(.shift) { parts.append("shift") }
        if modifiers.contains(.command) { parts.append("cmd") }
        parts.append(HotKeyCombo.name(forKeyCode: keyCode) ?? "key\(keyCode)")
        return parts.joined(separator: "+")
    }

    /// Display form as in macOS menus: "⌃⌥ Space", "F12".
    var displayString: String {
        let symbols = HotKeyCombo.modifierSymbols(modifiers)
        let key = HotKeyCombo.displayName(forKeyCode: keyCode)
        return symbols.isEmpty ? key : symbols + " " + key
    }

    /// "⌃⌥⇧⌘" in the order macOS uses.
    static func modifierSymbols(_ flags: NSEvent.ModifierFlags) -> String {
        var text = ""
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option) { text += "⌥" }
        if flags.contains(.shift) { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }
        return text
    }

    /// Carbon modifier mask for RegisterEventHotKey.
    var carbonModifiers: UInt32 {
        var result: UInt32 = 0
        if modifiers.contains(.command) { result |= UInt32(cmdKey) }
        if modifiers.contains(.option) { result |= UInt32(optionKey) }
        if modifiers.contains(.control) { result |= UInt32(controlKey) }
        if modifiers.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }

    /// Function keys and "special" keys may be used without a modifier; ordinary characters
    /// may not, or you could never type that character again.
    var isUsableWithoutModifiers: Bool {
        HotKeyCombo.standaloneKeyCodes.contains(keyCode)
    }

    /// Why this combination is unusable, or nil if it is fine.
    var problem: String? {
        if modifiers.isEmpty && !isUsableWithoutModifiers {
            return "Combine this key with ⌃, ⌥ or ⌘, otherwise you could never type it again."
        }
        if modifiers == [.shift] && !isUsableWithoutModifiers {
            return "⇧ alone is not enough; add ⌃, ⌥ or ⌘."
        }
        return nil
    }

    // MARK: Key names

    private static let standaloneKeyCodes: Set<UInt32> = [
        UInt32(kVK_F1), UInt32(kVK_F2), UInt32(kVK_F3), UInt32(kVK_F4), UInt32(kVK_F5), UInt32(kVK_F6),
        UInt32(kVK_F7), UInt32(kVK_F8), UInt32(kVK_F9), UInt32(kVK_F10), UInt32(kVK_F11), UInt32(kVK_F12),
        UInt32(kVK_F13), UInt32(kVK_F14), UInt32(kVK_F15), UInt32(kVK_F16), UInt32(kVK_F17), UInt32(kVK_F18),
        UInt32(kVK_F19), UInt32(kVK_F20),
        UInt32(kVK_Home), UInt32(kVK_End), UInt32(kVK_PageUp), UInt32(kVK_PageDown), UInt32(kVK_Help),
        UInt32(kVK_ISO_Section),
    ]

    /// Keys with a fixed name (independent of the keyboard layout).
    private static let namedKeys: [(name: String, display: String, code: Int)] = [
        ("f1", "F1", kVK_F1), ("f2", "F2", kVK_F2), ("f3", "F3", kVK_F3), ("f4", "F4", kVK_F4),
        ("f5", "F5", kVK_F5), ("f6", "F6", kVK_F6), ("f7", "F7", kVK_F7), ("f8", "F8", kVK_F8),
        ("f9", "F9", kVK_F9), ("f10", "F10", kVK_F10), ("f11", "F11", kVK_F11), ("f12", "F12", kVK_F12),
        ("f13", "F13", kVK_F13), ("f14", "F14", kVK_F14), ("f15", "F15", kVK_F15), ("f16", "F16", kVK_F16),
        ("f17", "F17", kVK_F17), ("f18", "F18", kVK_F18), ("f19", "F19", kVK_F19), ("f20", "F20", kVK_F20),
        ("space", "Space", kVK_Space), ("tab", "⇥", kVK_Tab), ("return", "↩", kVK_Return),
        ("enter", "⌤", kVK_ANSI_KeypadEnter), ("escape", "⎋", kVK_Escape), ("delete", "⌫", kVK_Delete),
        ("forwarddelete", "⌦", kVK_ForwardDelete), ("home", "↖", kVK_Home), ("end", "↘", kVK_End),
        ("pageup", "⇞", kVK_PageUp), ("pagedown", "⇟", kVK_PageDown), ("help", "Help", kVK_Help),
        ("left", "←", kVK_LeftArrow), ("right", "→", kVK_RightArrow), ("up", "↑", kVK_UpArrow), ("down", "↓", kVK_DownArrow),
        ("section", "§", kVK_ISO_Section),
        ("grave", "`", kVK_ANSI_Grave), ("minus", "-", kVK_ANSI_Minus), ("equal", "=", kVK_ANSI_Equal),
        ("leftbracket", "[", kVK_ANSI_LeftBracket), ("rightbracket", "]", kVK_ANSI_RightBracket),
        ("semicolon", ";", kVK_ANSI_Semicolon), ("quote", "'", kVK_ANSI_Quote), ("backslash", "\\", kVK_ANSI_Backslash),
        ("comma", ",", kVK_ANSI_Comma), ("period", ".", kVK_ANSI_Period), ("slash", "/", kVK_ANSI_Slash),
        ("a", "A", kVK_ANSI_A), ("b", "B", kVK_ANSI_B), ("c", "C", kVK_ANSI_C), ("d", "D", kVK_ANSI_D),
        ("e", "E", kVK_ANSI_E), ("f", "F", kVK_ANSI_F), ("g", "G", kVK_ANSI_G), ("h", "H", kVK_ANSI_H),
        ("i", "I", kVK_ANSI_I), ("j", "J", kVK_ANSI_J), ("k", "K", kVK_ANSI_K), ("l", "L", kVK_ANSI_L),
        ("m", "M", kVK_ANSI_M), ("n", "N", kVK_ANSI_N), ("o", "O", kVK_ANSI_O), ("p", "P", kVK_ANSI_P),
        ("q", "Q", kVK_ANSI_Q), ("r", "R", kVK_ANSI_R), ("s", "S", kVK_ANSI_S), ("t", "T", kVK_ANSI_T),
        ("u", "U", kVK_ANSI_U), ("v", "V", kVK_ANSI_V), ("w", "W", kVK_ANSI_W), ("x", "X", kVK_ANSI_X),
        ("y", "Y", kVK_ANSI_Y), ("z", "Z", kVK_ANSI_Z),
        ("0", "0", kVK_ANSI_0), ("1", "1", kVK_ANSI_1), ("2", "2", kVK_ANSI_2), ("3", "3", kVK_ANSI_3),
        ("4", "4", kVK_ANSI_4), ("5", "5", kVK_ANSI_5), ("6", "6", kVK_ANSI_6), ("7", "7", kVK_ANSI_7),
        ("8", "8", kVK_ANSI_8), ("9", "9", kVK_ANSI_9),
        ("keypad0", "Keypad 0", kVK_ANSI_Keypad0), ("keypad1", "Keypad 1", kVK_ANSI_Keypad1),
        ("keypad2", "Keypad 2", kVK_ANSI_Keypad2), ("keypad3", "Keypad 3", kVK_ANSI_Keypad3),
        ("keypad4", "Keypad 4", kVK_ANSI_Keypad4), ("keypad5", "Keypad 5", kVK_ANSI_Keypad5),
        ("keypad6", "Keypad 6", kVK_ANSI_Keypad6), ("keypad7", "Keypad 7", kVK_ANSI_Keypad7),
        ("keypad8", "Keypad 8", kVK_ANSI_Keypad8), ("keypad9", "Keypad 9", kVK_ANSI_Keypad9),
        ("keypadplus", "Keypad +", kVK_ANSI_KeypadPlus), ("keypadminus", "Keypad -", kVK_ANSI_KeypadMinus),
        ("keypadmultiply", "Keypad *", kVK_ANSI_KeypadMultiply), ("keypaddivide", "Keypad /", kVK_ANSI_KeypadDivide),
        ("keypaddecimal", "Keypad .", kVK_ANSI_KeypadDecimal), ("keypadequals", "Keypad =", kVK_ANSI_KeypadEquals),
        ("keypadclear", "Keypad Clear", kVK_ANSI_KeypadClear),
    ]

    static func keyCode(forName name: String) -> UInt32? {
        if let entry = namedKeys.first(where: { $0.name == name }) {
            return UInt32(entry.code)
        }
        // Unknown key, stored as "key<code>".
        if name.hasPrefix("key"), let code = UInt32(name.dropFirst(3)) {
            return code
        }
        return nil
    }

    static func name(forKeyCode code: UInt32) -> String? {
        namedKeys.first { UInt32($0.code) == code }?.name
    }

    static func displayName(forKeyCode code: UInt32) -> String {
        if let entry = namedKeys.first(where: { UInt32($0.code) == code }) {
            // For letter keys, show the actual letter of the current keyboard layout.
            if entry.name.count == 1, let typed = HotKeyCombo.character(forKeyCode: code) {
                return typed.uppercased()
            }
            return entry.display
        }
        if let typed = HotKeyCombo.character(forKeyCode: code) {
            return typed.uppercased()
        }
        return "Key \(code)"
    }

    /// The character this key code produces in the current keyboard layout (without modifiers).
    static func character(forKeyCode code: UInt32) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(layoutPointer).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        // Swift imports UniCharCount as Int.
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let status = layoutData.withUnsafeBytes { bytes -> OSStatus in
            guard let base = bytes.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return -1 }
            return UCKeyTranslate(base, UInt16(code), UInt16(kUCKeyActionDisplay), 0,
                                  UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysMask),
                                  &deadKeyState, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return nil }
        let text = String(utf16CodeUnits: chars, count: length)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.unicodeScalars.contains(where: { $0.value < 32 }) ? nil : trimmed
    }
}

/// Registers a system-wide hotkey through the Carbon hotkey API.
/// This works without Accessibility permissions.
final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private(set) var currentCombo: HotKeyCombo?
    private(set) var lastError: String?

    /// Called on the main thread whenever the hotkey is pressed.
    var onTrigger: (() -> Void)?

    /// Registers the combination. Returns false if macOS refuses the registration
    /// (usually because another app or the system already owns the same combination).
    @discardableResult
    func register(_ combo: HotKeyCombo) -> Bool {
        unregister()
        installHandlerIfNeeded()

        let hotKeyID = EventHotKeyID(signature: HotKeyManager.fourCharCode("LUIK"), id: 1)
        let status = RegisterEventHotKey(combo.keyCode, combo.carbonModifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        if status == noErr {
            currentCombo = combo
            lastError = nil
            return true
        }
        hotKeyRef = nil
        currentCombo = nil
        lastError = "Hotkey \(combo.displayString) could not be registered (error \(status)); another app may already be using it."
        NSLog("Luik: %@", lastError ?? "")
        return false
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        currentCombo = nil
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData -> OSStatus in
            guard let userData else { return noErr }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async {
                manager.onTrigger?()
            }
            return noErr
        }, 1, &eventType, selfPointer, &handlerRef)
    }

    private static func fourCharCode(_ string: String) -> OSType {
        var result: OSType = 0
        for byte in string.utf8 {
            result = (result << 8) + OSType(byte)
        }
        return result
    }
}
