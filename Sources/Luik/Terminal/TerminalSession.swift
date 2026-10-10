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

/// SwiftTerm's terminal view plus a hook on the keyboard input that goes to the shell, so typed
/// commands can be written to the activity log. Lines typed while the pty has echo switched off
/// (password prompts) are never recorded.
final class LoggingTerminalView: LocalProcessTerminalView {
    private let recorder = TypedLineRecorder()
    /// Called on the main thread with every completed line.
    var onTypedLine: ((String) -> Void)?

    override func send(source: TerminalView, data: ArraySlice<UInt8>) {
        if let line = recorder.feed(data), echoIsOn {
            let callback = onTypedLine
            DispatchQueue.main.async { callback?(line) }
        }
        super.send(source: source, data: data)
    }

    /// True unless the shell (or a program such as sudo/ssh) turned echo off on the pty.
    private var echoIsOn: Bool {
        guard let process, process.childfd >= 0 else { return true }
        var attributes = termios()
        guard tcgetattr(process.childfd, &attributes) == 0 else { return true }
        return (attributes.c_lflag & UInt(ECHO)) != 0
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

    func send(_ text: String) {
        view.send(txt: text)
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
