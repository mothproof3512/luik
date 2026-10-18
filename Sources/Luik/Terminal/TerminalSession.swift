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
    /// Called on the main thread with what the previous command printed, once the next command
    /// line begins (the shell is back at its prompt).
    var onCommandOutput: ((String) -> Void)?
    /// Set by TerminalSession around text Luik sends itself (one-liners, connections).
    var programmaticInput = false

    /// Screen row where the output of the last command starts; nil when no command is pending.
    private var outputStartRow: Int?

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
                closeOutput()
                outputStartRow = getTerminal().cursorScrollInvariantRow + 1
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
        closeOutput()
    }

    /// Hands the rows between the last command and the current prompt to `onCommandOutput`.
    private func closeOutput() {
        guard let start = outputStartRow else { return }
        outputStartRow = nil
        let terminal = getTerminal()
        guard !terminal.isCurrentBufferAlternate else { return }
        let end = terminal.cursorScrollInvariantRow - 1   // the prompt row itself is not output
        guard end >= start else { return }
        let text = LoggingTerminalView.rows(start...end, in: terminal)
        onCommandOutput?(text)
    }

    /// Output of the running / last command so far (for "pin now", before the next prompt).
    func currentOutput() -> String? {
        guard let start = outputStartRow else { return nil }
        let terminal = getTerminal()
        guard !terminal.isCurrentBufferAlternate else { return nil }
        let end = lineActive ? startRow - 1 : terminal.cursorScrollInvariantRow
        guard end >= start else { return nil }
        return LoggingTerminalView.rows(start...end, in: terminal)
    }

    /// Text of scroll-invariant rows, soft-wrapped rows joined. Rows that left the scrollback are skipped.
    static func rows(_ range: ClosedRange<Int>, in terminal: Terminal) -> String {
        var lines: [String] = []
        var current = ""
        var continuing = false
        for row in range {
            guard let text = terminal.scrollInvariantLineText(row: row, trimRight: !terminal.scrollInvariantLineIsWrapped(row: row + 1)) else { continue }
            if continuing {
                current += text
            } else {
                if !current.isEmpty || !lines.isEmpty { lines.append(current) }
                current = text
            }
            continuing = terminal.scrollInvariantLineIsWrapped(row: row + 1)
        }
        lines.append(current)
        return lines.joined(separator: "\n")
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
        // Whatever follows this row is the command's output, until the next prompt.
        closeOutput()
        outputStartRow = end + 1
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
    /// Host this tab was opened for (Targets › Open terminal): RHOST/RPORT/LHOST are exported in
    /// its shell and every command in it is tagged with the host in the Log.
    var boundHost: String?
    var boundPort: Int?
    /// Log entry of the command whose output is being collected, and the command itself.
    @ObservationIgnored var pendingEntryID: UUID?
    @ObservationIgnored var pendingCommand = ""
    @ObservationIgnored var pendingTime = Date()

    init(shell: String, fontSize: CGFloat, opacity: CGFloat, boundHost: String? = nil, boundPort: Int? = nil) {
        self.boundHost = boundHost
        self.boundPort = boundPort
        view = LoggingTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 400))
        applyAppearance(fontSize: fontSize, opacity: opacity)
        view.getTerminal().changeHistorySize(5000)   // SwiftTerm's default of 500 lines is short for scan output
        view.optionAsMetaKey = true
        view.processDelegate = self
        view.onTypedLine = { [weak self] line in
            guard let self, UserDefaults.standard.bool(forKey: SettingsKey.logTypedCommands) else { return }
            let host = TargetContext.host(for: line, boundHost: self.boundHost)
            self.pendingEntryID = ActivityLog.shared.record(.typed, line, source: "Terminal: \(self.title)", host: host)
            self.pendingCommand = line
            self.pendingTime = Date()
            TerminalStore.warnIfOutOfScope(line)
        }
        view.onCommandOutput = { [weak self] output in
            guard let self, UserDefaults.standard.bool(forKey: SettingsKey.captureOutput) else { return }
            guard let entryID = self.pendingEntryID else { return }
            self.pendingEntryID = nil
            CommandOutputStore.shared.store(output, for: entryID, command: self.pendingCommand, source: "Terminal: \(self.title)")
        }

        var environment = ProcessInfo.processInfo.environment
        if let boundHost {
            // The shell knows the host too: `nmap $RHOST` works straight away in a bound tab.
            environment["RHOST"] = boundHost
            if let boundPort { environment["RPORT"] = String(boundPort) }
            let lhost = SnippetStore.shared.lhost.trimmingCharacters(in: .whitespaces)
            if !lhost.isEmpty { environment["LHOST"] = lhost }
            let lport = SnippetStore.shared.lport.trimmingCharacters(in: .whitespaces)
            if !lport.isEmpty { environment["LPORT"] = lport }
        }
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
        let theme = LuikTheme.current
        view.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        view.nativeBackgroundColor = theme.backgroundNS.withAlphaComponent(opacity)
        view.nativeForegroundColor = theme.foregroundNS
        view.caretColor = theme.cursorNS
        view.selectedTextBackgroundColor = theme.accentNS.withAlphaComponent(0.35)
        // SwiftTerm sets the layer colour only when the view is created (solid black) and then
        // paints each cell's background with nativeBackgroundColor. Make the layer transparent,
        // otherwise the alpha above has no effect.
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.needsDisplay = true
    }

    func terminate() {
        view.terminate()
    }

    /// Text Luik sends itself (one-liners, Searchsploit commands, connections). `entryID` is the
    /// Log entry of that command, so its output can be attached.
    func send(_ text: String, entryID: UUID? = nil) {
        view.programmaticInput = true
        view.send(txt: text)   // closes the previous command's output first (synchronously)
        view.programmaticInput = false
        if text.contains("\n") || text.contains("\r") {
            pendingEntryID = entryID
            pendingCommand = text.trimmingCharacters(in: .whitespacesAndNewlines)
            pendingTime = Date()
        }
    }

    /// The last command and what it printed so far (or the complete output once it is stored).
    var lastCommandOutput: (command: String, output: String, time: Date)? {
        if let live = view.currentOutput(), !pendingCommand.isEmpty {
            return (pendingCommand, CommandOutputStore.clean(live), pendingTime)
        }
        if !pendingCommand.isEmpty, let entryID = pendingEntryID, let record = CommandOutputStore.shared.record(forEntry: entryID) {
            return (record.command, CommandOutputStore.shared.text(of: record), record.time)
        }
        if let record = CommandOutputStore.shared.records.last(where: { $0.source.hasSuffix("Terminal: \(title)") }) {
            return (record.command, CommandOutputStore.shared.text(of: record), record.time)
        }
        return nil
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
            // A bound tab keeps the host as its name.
            if let host = self.boundHost { self.title = host; return }
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
    func newSession(boundHost: String? = nil, boundPort: Int? = nil) -> TerminalSession {
        let defaults = UserDefaults.standard
        var shell = defaults.string(forKey: SettingsKey.shellPath) ?? "/bin/zsh"
        if shell.isEmpty || !FileManager.default.isExecutableFile(atPath: shell) {
            shell = "/bin/zsh"
        }
        let session = TerminalSession(shell: shell,
                                      fontSize: CGFloat(defaults.double(forKey: SettingsKey.fontSize)),
                                      opacity: CGFloat(defaults.double(forKey: SettingsKey.terminalExtraOpacity)),
                                      boundHost: boundHost, boundPort: boundPort)
        if let boundHost { session.title = boundHost }
        sessions.append(session)
        selectedID = session.id
        focusSelected(afterDelay: true)
        return session
    }

    /// A terminal tab for a Targets node: the host (and port) become $RHOST/$RPORT in the app and
    /// RHOST/RPORT/LHOST/LPORT in the shell's environment.
    @discardableResult
    func newSession(boundTo node: TargetNode) -> TerminalSession {
        let host = TargetStore.shared.host(of: node)
        let address = host?.address.trimmingCharacters(in: .whitespaces) ?? ""
        TargetContext.use(node)
        let session = newSession(boundHost: address.isEmpty ? nil : address, boundPort: node.kind == .port ? node.portNumber : nil)
        ActivityLog.shared.record(.action, "Terminal opened for \(address)\(node.kind == .port ? ":\(node.portNumber)" : "")", source: "Targets", host: address)
        return session
    }

    /// A command that names a host outside the engagement's scope gets a red note — in the Log and
    /// at the bottom of the panel. It is not blocked: the tester decides, Luik remembers.
    static func warnIfOutOfScope(_ command: String) {
        let problems = TargetContext.scopeProblems(in: command)
        guard !problems.isEmpty else { return }
        let list = problems.joined(separator: ", ")
        ActivityLog.shared.record(.action, "⚠️ OUT OF SCOPE: \(list) in “\(CommandOutputStore.shortCommand(command))”", source: "Scope")
        UIState.shared.flash("⚠️ Not in scope: \(list)", seconds: 4)
        NSSound.beep()
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
        let host = TargetContext.host(for: text, boundHost: session.boundHost)
        let entryID = ActivityLog.shared.record(.command, text, source: "\(source) → Terminal: \(session.title)", host: host)
        session.send(text, entryID: entryID)
        TerminalStore.warnIfOutOfScope(text)
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
