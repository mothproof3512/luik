import AppKit
import Foundation

/// Prompt markers (OSC 133, as iTerm2, VS Code and WezTerm use them) tell Luik exactly where a
/// command's output starts and ends and what its exit status was — exact with multi-line
/// prompts and when you type the next command while the previous one still prints. Luik writes
/// the scripts into its data folder on every launch; "Install" adds one `source` line to the
/// shell's rc file. Without it the Enter-key heuristic keeps working.
enum ShellIntegration {
    enum Shell: String, CaseIterable, Identifiable {
        case zsh, bash

        var id: String { rawValue }

        var rcFile: URL {
            let home = FileManager.default.homeDirectoryForCurrentUser
            return home.appendingPathComponent(self == .zsh ? ".zshrc" : ".bashrc")
        }

        var scriptName: String { "shell-integration.\(rawValue)" }
    }

    static func scriptURL(for shell: Shell) -> URL {
        Storage.url(for: shell.scriptName)
    }

    /// The line that goes into ~/.zshrc or ~/.bashrc.
    static func sourceLine(for shell: Shell) -> String {
        "[ -f \"\(scriptURL(for: shell).path)\" ] && source \"\(scriptURL(for: shell).path)\"  # Luik shell integration"
    }

    static let zshScript = """
    # Luik shell integration — prompt markers (OSC 133) so Luik knows exactly where a command's
    # output starts and ends, and its exit status. Only active inside Luik's terminal tabs.
    if [[ "$TERM_PROGRAM" == "Luik" && -z "$LUIK_SHELL_INTEGRATION" ]]; then
      export LUIK_SHELL_INTEGRATION=1
      __luik_precmd() { local st=$?; printf '\\033]133;D;%s\\a\\033]133;A\\a' "$st"; }
      __luik_preexec() { printf '\\033]133;C\\a'; }
      autoload -Uz add-zsh-hook
      add-zsh-hook precmd __luik_precmd
      add-zsh-hook preexec __luik_preexec
      # End-of-prompt marker, invisible to zsh's width calculation (prompt themes may replace it).
      PS1="${PS1}%{$(printf '\\033]133;B\\a')%}"
    fi
    """

    static let bashScript = """
    # Luik shell integration — prompt markers (OSC 133) so Luik knows exactly where a command's
    # output starts and ends, and its exit status. Only active inside Luik's terminal tabs.
    if [[ "$TERM_PROGRAM" == "Luik" && -z "$LUIK_SHELL_INTEGRATION" ]]; then
      export LUIK_SHELL_INTEGRATION=1
      __luik_at_prompt=0
      __luik_status() { __luik_st=$?; }
      __luik_precmd() { printf '\\033]133;D;%s\\a\\033]133;A\\a' "$__luik_st"; __luik_at_prompt=1; }
      __luik_debug() { [[ $__luik_at_prompt == 1 ]] || return 0; __luik_at_prompt=0; printf '\\033]133;C\\a'; }
      PROMPT_COMMAND="__luik_status${PROMPT_COMMAND:+; $PROMPT_COMMAND}; __luik_precmd"
      trap '__luik_debug' DEBUG
    fi
    """

    /// Writes the current scripts (called at launch, so an update of Luik updates the hooks).
    static func writeScripts() {
        for shell in Shell.allCases {
            let script = shell == .zsh ? zshScript : bashScript
            let url = scriptURL(for: shell)
            if (try? String(contentsOf: url, encoding: .utf8)) == script { continue }
            try? script.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    static func isInstalled(_ shell: Shell) -> Bool {
        guard let text = try? String(contentsOf: shell.rcFile, encoding: .utf8) else { return false }
        return text.contains(shell.scriptName)
    }

    /// Appends the source line to the rc file. Returns a message for the UI.
    static func install(_ shell: Shell) -> String {
        writeScripts()
        if isInstalled(shell) { return "\(shell.rcFile.lastPathComponent) already sources the Luik script." }
        var text = (try? String(contentsOf: shell.rcFile, encoding: .utf8)) ?? ""
        if !text.isEmpty && !text.hasSuffix("\n") { text += "\n" }
        text += "\n" + sourceLine(for: shell) + "\n"
        do {
            try text.write(to: shell.rcFile, atomically: true, encoding: .utf8)
            ActivityLog.shared.record(.action, "Shell integration installed in \(shell.rcFile.lastPathComponent)", source: "Terminal")
            return "Added to \(shell.rcFile.lastPathComponent) — takes effect in new terminal tabs."
        } catch {
            return "Could not write \(shell.rcFile.lastPathComponent): \(error.localizedDescription)"
        }
    }

    /// Removes the source line again.
    static func uninstall(_ shell: Shell) -> String {
        guard var text = try? String(contentsOf: shell.rcFile, encoding: .utf8), text.contains(shell.scriptName) else {
            return "Nothing to remove from \(shell.rcFile.lastPathComponent)."
        }
        let lines = text.components(separatedBy: "\n").filter { !$0.contains(shell.scriptName) }
        text = lines.joined(separator: "\n")
        do {
            try text.write(to: shell.rcFile, atomically: true, encoding: .utf8)
            return "Removed from \(shell.rcFile.lastPathComponent)."
        } catch {
            return "Could not write \(shell.rcFile.lastPathComponent): \(error.localizedDescription)"
        }
    }

    static func copySnippet(_ shell: Shell) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(sourceLine(for: shell), forType: .string)
    }

    /// Whether the selected terminal tab has sent a marker yet.
    static var activeInSelectedTab: Bool {
        TerminalStore.shared.selected?.view.hasShellIntegration ?? false
    }
}
