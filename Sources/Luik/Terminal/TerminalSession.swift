import AppKit
import Observation
import SwiftTerm
import SwiftUI

/// Bridge between SwiftUI and SwiftTerm's AppKit terminal view.
/// The view is kept in the session so the shell keeps running when you switch tabs.
struct TerminalViewRepresentable: NSViewRepresentable {
    let session: TerminalSession

    func makeNSView(context: Context) -> LoggingTerminalView {
        session.view
    }

    func updateNSView(_ nsView: LoggingTerminalView, context: Context) {}
}

/// SwiftTerm's terminal view plus a hook on the input that goes to the shell, so the command the
/// user runs can be written to the activity log.
///
/// Shells and most interactive programs (the zsh/bash line editors, ssh, msfconsole, python…) put
/// the pty in raw mode and echo keystrokes themselves, so the pty's ECHO flag says nothing useful
/// about what the user is typing. Instead, when Enter is pressed the view reads the screen: the
/// text that appeared on the cursor row after the prompt is what was run — including commands
/// recalled from history, tab completions and commands typed inside an ssh session. Input that
/// never shows up on screen (a password at a local or remote prompt) is therefore never logged,
/// and full-screen programs (vim, less, htop) are ignored because they use the alternate buffer.
final class LoggingTerminalView: LocalProcessTerminalView {
    /// Called on the main thread with every command the user ran.
    var onTypedLine: ((String) -> Void)?
    /// Set by TerminalSession around text Luik sends itself (one-liners, connections).
    var programmaticInput = false

    private var lineActive = false
    private var startRow = 0
    private var promptPrefix = ""
    private var lastPrompt = ""
    private var typedBytes: [UInt8] = []
    private var inEscape = false
    private var escapeLength = 0
    private var lastProgrammaticText = ""

    override func send(source: TerminalView, data: ArraySlice<UInt8>) {
        inspect(data)
        super.send(source: source, data: data)
    }

    private func inspect(_ data: ArraySlice<UInt8>) {
        guard !data.isEmpty else { return }
        if programmaticInput {
            let text = String(decoding: data, as: UTF8.self)
            if text.contains("\n") || text.contains("\r") {
                // Luik ran the command itself; it is already in the log as "Command".
                lineActive = false
                lastProgrammaticText = ""
            } else {
                // Pasted for editing: the line starts here, with the prompt as it is right now.
                if !lineActive { beginLine() }
                typedBytes.append(contentsOf: data.filter { $0 >= 0x20 })
                lastProgrammaticText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return
        }
        if !lineActive { beginLine() }
        for byte in data {
            if inEscape {
                escapeLength += 1
                if escapeLength == 1 {
                    if byte != 0x5B && byte != 0x4F { inEscape = false }
                } else if byte >= 0x40 && byte <= 0x7E {
                    inEscape = false
                }
                continue
            }
            switch byte {
            case 0x1B:
                inEscape = true
                escapeLength = 0
            case 0x0D, 0x0A:
                finishLine()
                return // the remaining lines of a multi-line paste are not followed
            case 0x03, 0x04: // Ctrl-C, Ctrl-D: the line is abandoned
                lineActive = false
                return
            case 0x7F, 0x08:
                if !typedBytes.isEmpty { typedBytes.removeLast() }
            case 0x15: // Ctrl-U clears the line
                typedBytes.removeAll()
            default:
                if byte >= 0x20 { typedBytes.append(byte) }
            }
        }
    }

    private func beginLine() {
        let terminal = getTerminal()
        lineActive = true
        typedBytes.removeAll()
        inEscape = false
        startRow = terminal.cursorScrollInvariantRow
        promptPrefix = terminal.scrollInvariantLineText(row: startRow, endCol: terminal.cursorColumn) ?? ""
    }

    private func finishLine() {
        let terminal = getTerminal()
        lineActive = false
        guard !terminal.isCurrentBufferAlternate else { return } // vim, less, htop, tmux…
        if isCookedModeWithoutEcho { return }                     // a classic local password prompt
        let start = startRow
        let end = terminal.cursorScrollInvariantRow
        let endCol = terminal.cursorColumn
        let prefix = promptPrefix
        let typed = String(decoding: typedBytes, as: UTF8.self)
        let pasted = lastProgrammaticText
        lastProgrammaticText = ""
        // Read the screen a moment later, when the echo of the last keystrokes has arrived
        // (remote shells over ssh answer with a delay).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, let command = self.command(from: start, to: end, endCol: endCol, prefix: prefix, typed: typed) else { return }
            // Typed, but (almost) nothing of it on screen: a password or other hidden input.
            if typed.count >= 3 && command.count * 2 < typed.count { return }
            if command == pasted { return } // pasted by Luik and run unchanged: already logged
            self.onTypedLine?(command)
        }
    }

    /// The text on the rows the line occupied, minus the prompt. Nil when nothing usable is there.
    private func command(from start: Int, to end: Int, endCol: Int, prefix: String, typed: String) -> String? {
        let terminal = getTerminal()
        guard start <= end else { return nil }
        var text = ""
        for row in max(start, end - 8)...end {
            if row == end {
                guard let rowText = terminal.scrollInvariantLineText(row: row) else { continue }
                // Up to the cursor, plus whatever directly follows it (cursor in the middle of the
                // line); text further to the right — a right-hand prompt with the time or the git
                // branch — is left out.
                let upToCursor = terminal.scrollInvariantLineText(row: row, endCol: endCol) ?? ""
                var rest = String(rowText.dropFirst(upToCursor.count))
                if let gap = rest.range(of: "  ") { rest = String(rest[..<gap.lowerBound]) }
                text += upToCursor + rest
            } else {
                // Rows a long command wrapped over keep their trailing spaces.
                let wrapped = terminal.scrollInvariantLineIsWrapped(row: row + 1)
                guard let rowText = terminal.scrollInvariantLineText(row: row, trimRight: !wrapped) else { continue }
                text += rowText
            }
        }

        var command: String
        let candidates = [prefix, lastPrompt].filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if let found = candidates.first(where: { text.contains($0) }), let range = text.range(of: found) {
            command = String(text[range.upperBound...])
            lastPrompt = found
        } else if candidates.isEmpty {
            command = text
        } else if !typed.isEmpty, let range = text.range(of: typed) {
            // The prompt we saw is gone (typed ahead of it, or a prompt that redraws itself on
            // Enter): fall back to the reconstructed keystrokes, as they appear on screen.
            command = String(text[range.lowerBound...])
        } else {
            return nil
        }
        command = command.trimmingCharacters(in: .whitespacesAndNewlines)
        return command.isEmpty ? nil : command
    }

    /// Canonical mode with echo switched off is how sudo, ssh, su and `read -s` ask for a password.
    private var isCookedModeWithoutEcho: Bool {
        guard let process, process.childfd >= 0 else { return false }
        var attributes = termios()
        guard tcgetattr(process.childfd, &attributes) == 0 else { return false }
        return (attributes.c_lflag & UInt(ICANON)) != 0 && (attributes.c_lflag & UInt(ECHO)) == 0
    }
}

/// One terminal tab: a SwiftTerm view with a shell inside.
@Observable
final class TerminalSession: Identifiable {
    let id = UUID()
    var title: String = "Shell"
    let view: LoggingTerminalView

    init(shell: String, fontSize: CGFloat, opacity: CGFloat) {
        view = LoggingTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 400))
        applyAppearance(fontSize: fontSize, opacity: opacity)
        view.getTerminal().changeHistorySize(5000)   // SwiftTerm's default of 500 lines is short for scan output
        view.optionAsMetaKey = true
        view.processDelegate = self
        view.onTypedLine = { [weak self] line in
            guard let self, UserDefaults.standard.bool(forKey: SettingsKey.logTypedCommands) else { return }
            ActivityLog.shared.record(.typed, line, source: "Terminal: \(self.title)")
        }

        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"
        environment["TERM_PROGRAM"] = "Luik"
        if environment["LANG"] == nil {
            environment["LANG"] = "en_US.UTF-8"
        }
        let environmentList = environment.map { "\($0.key)=\($0.value)" }

        // "-l": login shell, so PATH/aliases from .zprofile/.zshrc are loaded.
        view.startProcess(executable: shell,
                          args: ["-l"],
                          environment: environmentList,
                          execName: nil,
                          currentDirectory: NSHomeDirectory())
    }

    /// `opacity` is the extra dark layer under the terminal text (0 = the panel background
    /// shows through completely, 1 = solid).
    func applyAppearance(fontSize: CGFloat, opacity: CGFloat) {
        view.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        view.nativeBackgroundColor = NSColor(calibratedRed: 0.07, green: 0.08, blue: 0.10, alpha: opacity)
        view.nativeForegroundColor = NSColor(calibratedWhite: 0.92, alpha: 1)
        view.caretColor = NSColor(calibratedRed: 0.55, green: 0.85, blue: 0.55, alpha: 1)
        // SwiftTerm sets the layer colour only when the view is created (solid black) and then
        // paints each cell's background with nativeBackgroundColor. Make the layer transparent,
        // otherwise the alpha above has no effect.
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.needsDisplay = true
    }

    func terminate() {
        view.terminate()
    }

    /// Text Luik sends itself (one-liners, Searchsploit commands, connections).
    func send(_ text: String) {
        view.programmaticInput = true
        view.send(txt: text)
        view.programmaticInput = false
    }

    func focus() {
        guard let window = view.window else { return }
        window.makeFirstResponder(view)
    }
}

extension TerminalSession: LocalProcessTerminalViewDelegate {
    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        DispatchQueue.main.async {
            self.title = title.isEmpty ? "Shell" : title
        }
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        DispatchQueue.main.async {
            TerminalStore.shared.sessionEnded(self)
        }
    }
}

/// Manages all terminal tabs.
@Observable
final class TerminalStore {
    static let shared = TerminalStore()

    var sessions: [TerminalSession] = []
    var selectedID: UUID?

    var selected: TerminalSession? {
        sessions.first { $0.id == selectedID }
    }

    func ensureSession() {
        if sessions.isEmpty {
            newSession()
        }
    }

    @discardableResult
    func newSession() -> TerminalSession {
        let defaults = UserDefaults.standard
        var shell = defaults.string(forKey: SettingsKey.shellPath) ?? "/bin/zsh"
        if shell.isEmpty || !FileManager.default.isExecutableFile(atPath: shell) {
            shell = "/bin/zsh"
        }
        let session = TerminalSession(shell: shell,
                                      fontSize: CGFloat(defaults.double(forKey: SettingsKey.fontSize)),
                                      opacity: CGFloat(defaults.double(forKey: SettingsKey.terminalExtraOpacity)))
        sessions.append(session)
        selectedID = session.id
        focusSelected(afterDelay: true)
        return session
    }

    func close(_ session: TerminalSession) {
        session.terminate()
        remove(session)
    }

    func sessionEnded(_ session: TerminalSession) {
        remove(session)
    }

    private func remove(_ session: TerminalSession) {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        sessions.remove(at: index)
        if sessions.isEmpty {
            newSession()
            return
        }
        if selectedID == session.id {
            selectedID = sessions[min(index, sessions.count - 1)].id
        }
        focusSelected(afterDelay: true)
    }

    func select(_ id: UUID) {
        selectedID = id
        focusSelected(afterDelay: true)
    }

    func selectNext() {
        guard sessions.count > 1, let index = sessions.firstIndex(where: { $0.id == selectedID }) else { return }
        select(sessions[(index + 1) % sessions.count].id)
    }

    func selectPrevious() {
        guard sessions.count > 1, let index = sessions.firstIndex(where: { $0.id == selectedID }) else { return }
        select(sessions[(index - 1 + sessions.count) % sessions.count].id)
    }

    func focusSelected(afterDelay: Bool = false) {
        let work: () -> Void = { [weak self] in
            self?.selected?.focus()
        }
        if afterDelay {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
        } else {
            work()
        }
    }

    /// The terminal stays in the view hierarchy while another tab is shown (see RootView), so it
    /// must give up the keyboard, or keystrokes meant for Notes would still reach the shell.
    func resignFocus() {
        for session in sessions {
            if let window = session.view.window, window.firstResponder === session.view {
                window.makeFirstResponder(nil)
            }
        }
    }

    /// Paste text into the active terminal (without Enter, so it can still be edited).
    /// `source` names the tab it came from, for the activity log.
    func sendToSelected(_ text: String, source: String = "Luik") {
        guard let session = selected else { return }
        session.send(text)
        ActivityLog.shared.record(.command, text, source: "\(source) → Terminal: \(session.title)")
    }

    func applyAppearance() {
        let defaults = UserDefaults.standard
        let fontSize = CGFloat(defaults.double(forKey: SettingsKey.fontSize))
        let opacity = CGFloat(defaults.double(forKey: SettingsKey.terminalExtraOpacity))
        for session in sessions {
            session.applyAppearance(fontSize: fontSize, opacity: opacity)
        }
    }

    func terminateAll() {
        for session in sessions {
            session.terminate()
        }
    }
}
