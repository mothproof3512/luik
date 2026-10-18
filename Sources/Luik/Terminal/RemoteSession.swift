import AppKit
import Foundation

/// The machine a terminal tab is logged in to over ssh — the attack VM, a jump host. Luik knows
/// it from the connection that opened the tab or from the `ssh …` line typed in it, and uses it
/// to tag the Log (`via`), to put its shell integration on that machine and to export
/// `$RHOST/$RPORT` into that shell (the Mac's environment does not travel over ssh).
struct RemoteHost: Equatable {
    var host: String
    var user: String?
    /// Name of the saved connection that opened the tab, when there is one.
    var connectionName: String?
    var since = Date()
    /// Luik's shell integration has been put on this machine in this tab.
    var prepared = false

    var label: String {
        if let user, !user.isEmpty { return "\(user)@\(host)" }
        return host
    }

    /// Short name for the Log's `via` field and the tab chip.
    var shortName: String { connectionName ?? host }
}

enum RemoteDetect {
    /// ssh options that take an argument (OpenSSH 9): the token after them is not the host.
    private static let optionsWithArgument: Set<String> = ["-B", "-b", "-c", "-D", "-E", "-e", "-F", "-I", "-i", "-J", "-L", "-l", "-m", "-O", "-o", "-p", "-Q", "-R", "-S", "-W", "-w", "-P"]

    /// `ssh [options] [user@]host [command]` → the user and host. Also finds `ssh` after `sshpass …`
    /// or `sudo`. Nil for anything else (scp, sftp, ssh-keygen, ssh with a remote command are
    /// not logins into a shell).
    static func sshLogin(in command: String) -> RemoteHost? {
        let tokens = tokenize(command)
        guard let sshIndex = tokens.firstIndex(where: { $0 == "ssh" || $0.hasSuffix("/ssh") }) else { return nil }
        var user: String?
        var host: String?
        var index = sshIndex + 1
        while index < tokens.count {
            let token = tokens[index]
            if token.hasPrefix("-") {
                if optionsWithArgument.contains(token) {
                    if token == "-l", index + 1 < tokens.count { user = tokens[index + 1] }
                    index += 2
                } else if token.count > 2, optionsWithArgument.contains(String(token.prefix(2))) {
                    if token.hasPrefix("-l") { user = String(token.dropFirst(2)) }
                    index += 1   // -p2222, -luser
                } else {
                    index += 1   // -v, -A, -tt …
                }
                continue
            }
            host = token
            // Anything after the host is a remote command: not an interactive login.
            if index + 1 < tokens.count, !tokens[index + 1].hasPrefix("-") { return nil }
            break
        }
        guard var hostToken = host, !hostToken.isEmpty else { return nil }
        if hostToken.hasPrefix("ssh://") { hostToken = String(hostToken.dropFirst(6)) }
        if let at = hostToken.lastIndex(of: "@") {
            user = String(hostToken[..<at])
            hostToken = String(hostToken[hostToken.index(after: at)...])
        }
        if let colon = hostToken.firstIndex(of: ":"), !hostToken.contains("[") { hostToken = String(hostToken[..<colon]) }
        guard !hostToken.isEmpty else { return nil }
        return RemoteHost(host: hostToken, user: user)
    }

    /// `exit`, `logout` or Ctrl-D at the prompt end the remote shell.
    static func endsLogin(_ command: String) -> Bool {
        let word = command.trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init) ?? ""
        return word == "exit" || word == "logout"
    }

    private static func tokenize(_ command: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quote: Character?
        for character in command {
            if let open = quote {
                if character == open { quote = nil } else { current.append(character) }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == " " || character == "\t" {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else if character == "|" || character == ";" || character == "&" {
                if !current.isEmpty { tokens.append(current); current = "" }
                tokens.append(String(character))
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        // Only the first simple command matters (`ssh box | tee log` still logs in).
        if let separator = tokens.firstIndex(where: { $0 == "|" || $0 == ";" || $0 == "&" }) {
            return Array(tokens[..<separator])
        }
        return tokens
    }
}

/// Shell integration for the remote machine: the same OSC 133 markers, in one script that
/// works for bash and zsh, written through the ssh session itself (no scp, no agent).
enum RemoteShellIntegration {
    static let scriptPath = "~/.luik/shell-integration.sh"

    static let script = """
    # Luik shell integration (remote) — prompt markers (OSC 133) so the Luik terminal on the Mac
    # knows exactly where a command's output starts and ends, and its exit status. Harmless in
    # other terminals: they ignore the markers.
    if [ -z "$LUIK_SHELL_INTEGRATION" ]; then
      export LUIK_SHELL_INTEGRATION=1
      if [ -n "$ZSH_VERSION" ]; then
        __luik_precmd() { local st=$?; printf '\\033]133;D;%s\\a\\033]133;A\\a' "$st"; }
        __luik_preexec() { printf '\\033]133;C\\a'; }
        autoload -Uz add-zsh-hook
        add-zsh-hook precmd __luik_precmd
        add-zsh-hook preexec __luik_preexec
        PS1="${PS1}%{$(printf '\\033]133;B\\a')%}"
      elif [ -n "$BASH_VERSION" ]; then
        __luik_at_prompt=0
        __luik_status() { __luik_st=$?; }
        __luik_precmd() { printf '\\033]133;D;%s\\a\\033]133;A\\a' "$__luik_st"; __luik_at_prompt=1; }
        __luik_debug() { [ "$__luik_at_prompt" = 1 ] || return 0; __luik_at_prompt=0; printf '\\033]133;C\\a'; }
        PROMPT_COMMAND="__luik_status${PROMPT_COMMAND:+; $PROMPT_COMMAND}; __luik_precmd"
        trap '__luik_debug' DEBUG
      fi
    fi
    """

    /// One paste that writes the script, sources it from .bashrc and .zshrc (once) and loads it in
    /// the current shell. Quoted heredoc: nothing is expanded on the way in.
    static var prepareCommand: String {
        let sourceLine = "[ -f \(scriptPath) ] && . \(scriptPath)  # Luik shell integration"
        var lines: [String] = []
        lines.append("mkdir -p ~/.luik && cat > \(scriptPath) <<'LUIK_SHELL_INTEGRATION_EOF'")
        lines.append(script)
        lines.append("LUIK_SHELL_INTEGRATION_EOF")
        for rc in ["~/.bashrc", "~/.zshrc"] {
            lines.append("grep -qs 'luik/shell-integration' \(rc) || printf '\\n%s\\n' '\(sourceLine)' >> \(rc)")
        }
        lines.append(". \(scriptPath) && echo 'Luik shell integration ready'")
        return lines.joined(separator: "\n") + "\n"
    }
}
