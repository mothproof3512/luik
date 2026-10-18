import AppKit
import Foundation
import SwiftUI

/// "The host you are working on" as one notion for the whole app: `$RHOST` / `$RPORT` in the
/// One-liners store are the source of truth; Targets selection feeds them (when enabled), the
/// top bar shows them, terminals can be bound to them, log lines are tagged with them, and the
/// scope of the engagement is checked against every command that names a host.
enum TargetContext {
    /// Matches IPv4 addresses and host names with a dot (so "ls -la" never counts).
    static let addressPattern = try! NSRegularExpression(pattern: #"(?<![\w.-])((?:\d{1,3}\.){3}\d{1,3}(?:/\d{1,2})?|(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,24})(?![\w-])"#)

    /// Words in a command that look like a host or an IP, without duplicates, in order.
    static func addresses(in command: String) -> [String] {
        var found: [String] = []
        let range = NSRange(command.startIndex..., in: command)
        for match in addressPattern.matches(in: command, range: range) {
            guard let r = Range(match.range(at: 1), in: command) else { continue }
            var text = String(command[r])
            if let slash = text.firstIndex(of: "/") { text = String(text[..<slash]) }
            let lower = text.lowercased()
            // File names and common words that look like hosts.
            if lower.hasSuffix(".txt") || lower.hasSuffix(".py") || lower.hasSuffix(".sh") || lower.hasSuffix(".xml") || lower.hasSuffix(".json")
                || lower.hasSuffix(".md") || lower.hasSuffix(".log") || lower.hasSuffix(".gz") || lower.hasSuffix(".zip") || lower.hasSuffix(".nmap")
                || lower.hasSuffix(".gnmap") || lower.hasSuffix(".csv") || lower.hasSuffix(".pdf") || lower.hasSuffix(".png") || lower.hasSuffix(".jpg")
                || lower.hasSuffix(".conf") || lower.hasSuffix(".yaml") || lower.hasSuffix(".yml") || lower.hasSuffix(".rb") || lower.hasSuffix(".js")
                || lower.hasSuffix(".html") || lower.hasSuffix(".php") || lower.hasSuffix(".exe") || lower.hasSuffix(".dll") || lower.hasSuffix(".so")
                || lower.hasSuffix(".local") && lower.hasPrefix("github") {
                continue
            }
            if lower == "127.0.0.1" || lower.hasPrefix("0.0.0.0") || lower == "localhost" { continue }
            if !found.contains(text) { found.append(text) }
        }
        return found
    }

    /// Addresses in the command that the engagement's scope does not allow (empty when no scope is set).
    static func scopeProblems(in command: String) -> [String] {
        let engagement = EngagementStore.shared
        guard engagement.hasScope else { return [] }
        return addresses(in: command).filter { engagement.scopeStatus(of: $0).isProblem }
    }

    /// The host of the current `$RHOST`, when it is in Targets.
    static var currentHostNode: TargetNode? {
        let target = SnippetStore.shared.target.trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty else { return nil }
        return TargetStore.shared.hosts.first { $0.address == target || $0.title == target || $0.subtitle == target }
    }

    /// Makes a Targets node the context: its host becomes `$RHOST`, a port node also sets `$RPORT`.
    /// With `export`, the selected terminal tab also gets an `export RHOST=…` line typed in (when
    /// its shell is idle and the setting is on) — the way a shell on the attack VM learns the target.
    static func use(_ node: TargetNode, export: Bool = false) {
        let store = TargetStore.shared
        guard let host = store.host(of: node) else { return }
        let address = host.address.trimmingCharacters(in: .whitespaces)
        guard !address.isEmpty else { return }
        let snippets = SnippetStore.shared
        var changed = false
        if snippets.target != address { snippets.target = address; changed = true }
        if node.kind == .port, node.portNumber > 0, snippets.rport != String(node.portNumber) {
            snippets.rport = String(node.portNumber)
            changed = true
        }
        if changed { snippets.saveTarget() }
        if export, UserDefaults.standard.bool(forKey: SettingsKey.exportTargetToTerminal) {
            if TerminalStore.shared.exportTargetToSelected() {
                UIState.shared.flash("$RHOST exported into the terminal tab “\(TerminalStore.shared.selected?.title ?? "")”.", seconds: 2)
            }
        }
    }

    static func clear() {
        let snippets = SnippetStore.shared
        snippets.target = ""
        snippets.rport = ""
        snippets.saveTarget()
    }

    /// The host a command is about: the bound host of its terminal, else the current `$RHOST`
    /// when the command mentions it, else the first address in the command that is in Targets.
    static func host(for command: String, boundHost: String?) -> String? {
        if let boundHost, !boundHost.isEmpty { return boundHost }
        let target = SnippetStore.shared.target.trimmingCharacters(in: .whitespaces)
        if !target.isEmpty, command.contains(target) { return target }
        let known = Set(TargetStore.shared.hosts.map { $0.address })
        return addresses(in: command).first { known.contains($0) }
    }

    // MARK: - Host dossier

    /// Everything Luik knows about one host, as one Markdown page for the report or a hand-over.
    static func dossier(for host: TargetNode) -> String {
        let store = TargetStore.shared
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        var out = "# \(host.title)\(host.subtitle.isEmpty ? "" : " — \(host.subtitle)")\n\n"
        out += "_Host dossier from Luik, \(formatter.string(from: Date())) · engagement “\(EngagementStore.shared.current.displayName)”_\n\n"
        if EngagementStore.shared.hasScope {
            out += "Scope: \(EngagementStore.shared.scopeStatus(of: host.address).label)\n\n"
        }
        out += "Status: \(host.status.label)\n\n"

        let ports = host.children.filter { $0.kind == .port }.sorted { $0.portNumber < $1.portNumber }
        if !ports.isEmpty {
            out += "## Ports\n\n| Port | Service | Status |\n|---|---|---|\n"
            for port in ports {
                out += "| \(port.portNumber)/\(port.portProtocol) | \(port.subtitle.replacingOccurrences(of: "|", with: "\\|")) | \(port.status.label) |\n"
            }
            out += "\n"
        }

        let notes = host.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty { out += "## Notes\n\n\(notes)\n\n" }

        for port in ports {
            let portNotes = port.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            let items = port.children.filter { $0.kind == .task }
            guard !portNotes.isEmpty || items.contains(where: { $0.status != .todo || !$0.notes.isEmpty }) else { continue }
            out += "## \(port.portNumber)/\(port.portProtocol) \(port.subtitle)\n\n"
            if !portNotes.isEmpty { out += portNotes + "\n\n" }
            for item in items where item.status != .todo || !item.notes.isEmpty {
                let mark = item.status == .done ? "x" : " "
                out += "- [\(mark)] \(item.title)\(item.status == .notApplicable ? " (n/a)" : "")\n"
                let itemNotes = item.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                if !itemNotes.isEmpty { out += "    " + itemNotes.replacingOccurrences(of: "\n", with: "\n    ") + "\n" }
            }
            out += "\n"
        }

        let findings = FindingsStore.shared.findings.filter { finding in
            finding.affected.contains { $0 == host.address || $0.hasPrefix(host.address + ":") || (!host.subtitle.isEmpty && $0.hasPrefix(host.subtitle)) }
        }
        if !findings.isEmpty {
            out += "## Findings\n\n| Severity | Finding | Status |\n|---|---|---|\n"
            for finding in findings.sorted(by: { $0.severity < $1.severity }) {
                out += "| \(finding.severity.label) | \(finding.title.replacingOccurrences(of: "|", with: "\\|")) | \(finding.status.label) |\n"
            }
            out += "\n"
        }

        let entries = activity(for: host)
        if !entries.isEmpty {
            out += "## Commands and events\n\n"
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            for entry in entries {
                switch entry.kind {
                case .command, .typed:
                    out += "- `\(timeFormatter.string(from: entry.time))` \(entry.source)\n\n    ```\n    \(entry.text.replacingOccurrences(of: "\n", with: "\n    "))\n    ```\n\n"
                default:
                    out += "- `\(timeFormatter.string(from: entry.time))` **\(entry.kind.label)**: \(entry.text)\n"
                }
            }
            out += "\n"
        }

        let images = EvidenceImages.paths(in: host.notes + "\n" + ports.map { $0.notes }.joined(separator: "\n"))
        if !images.isEmpty {
            out += "## Evidence files\n\n" + images.map { "- \($0)" }.joined(separator: "\n") + "\n"
        }
        _ = store
        return out
    }

    /// Log entries about a host: tagged with it, or mentioning its address or name.
    static func activity(for host: TargetNode, limit: Int = 200) -> [ActivityEntry] {
        let address = host.address.trimmingCharacters(in: .whitespaces)
        let name = host.subtitle.trimmingCharacters(in: .whitespaces)
        guard !address.isEmpty || !name.isEmpty else { return [] }
        let entries = ActivityLog.shared.entries.filter { entry in
            if let tagged = entry.host, tagged == address { return true }
            if !address.isEmpty, entry.text.contains(address) { return true }
            if name.count >= 4, entry.text.localizedCaseInsensitiveContains(name) { return true }
            return false
        }
        return Array(entries.suffix(limit))
    }
}

/// Top-bar chip: the current `$RHOST[:$RPORT]`, coloured by scope, with a menu to switch host.
struct TargetContextChip: View {
    @Environment(SnippetStore.self) private var snippets
    @Environment(TargetStore.self) private var targets
    @Environment(EngagementStore.self) private var engagements
    @Environment(UIState.self) private var ui

    private var target: String { snippets.target.trimmingCharacters(in: .whitespaces) }

    private var scope: ScopeStatus? {
        guard !target.isEmpty, engagements.hasScope else { return nil }
        return engagements.scopeStatus(of: target)
    }

    var body: some View {
        Menu {
            if let node = targets.selectedNode, let host = targets.host(of: node), !host.address.isEmpty {
                Button("Use selected: \(host.address)\(node.kind == .port ? ":\(node.portNumber)" : "")") { TargetContext.use(node, export: true) }
                Divider()
            }
            let hosts = targets.hosts.filter { !$0.address.isEmpty }
            if hosts.isEmpty {
                Text("No hosts in Targets yet")
            } else {
                ForEach(hosts.prefix(30)) { host in
                    Button {
                        TargetContext.use(host)
                    } label: {
                        if host.address == target {
                            Label(hostLabel(host), systemImage: "checkmark")
                        } else {
                            Text(hostLabel(host))
                        }
                    }
                }
                if hosts.count > 30 { Text("… \(hosts.count - 30) more — pick them in Targets") }
            }
            if let node = TargetContext.currentHostNode {
                let ports = node.children.filter { $0.kind == .port }
                if !ports.isEmpty {
                    Menu("Port") {
                        ForEach(ports.sorted { $0.portNumber < $1.portNumber }) { port in
                            Button("\(port.portNumber)/\(port.portProtocol) \(port.subtitle)") { TargetContext.use(port) }
                        }
                    }
                }
                Button("Show in Targets") {
                    targets.selectedID = node.id
                    ui.open(.targets)
                }
                Button("Open a terminal for \(node.address)") {
                    TerminalStore.shared.newSession(boundTo: node)
                    ui.open(.terminal)
                }
            }
            if !target.isEmpty, let session = TerminalStore.shared.selected {
                Divider()
                Button("Type export RHOST=… into “\(session.title)”\(session.remote.map { " (on \($0.shortName))" } ?? "")") {
                    if !TerminalStore.shared.exportTargetToSelected(force: true) { ui.flash("Nothing to export — no current target.", seconds: 2) }
                }
            }
            Divider()
            Button("Clear") { TargetContext.clear() }
                .disabled(target.isEmpty)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: scope?.isProblem == true ? "exclamationmark.triangle.fill" : "scope")
                Text(target.isEmpty ? "no target" : target + (snippets.rport.isEmpty ? "" : ":" + snippets.rport))
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .foregroundStyle(scope?.isProblem == true ? Color.red : (target.isEmpty ? Color.secondary : Color.primary))
        .help(helpText)
    }

    private func hostLabel(_ host: TargetNode) -> String {
        let name = host.subtitle.trimmingCharacters(in: .whitespaces)
        return name.isEmpty || name == host.address ? host.address : "\(host.address)  \(name)"
    }

    private var helpText: String {
        if target.isEmpty { return "The host you are working on ($RHOST / $RPORT): pick one here or select it in Targets" }
        var text = "$RHOST = \(target)" + (snippets.rport.isEmpty ? "" : ", $RPORT = \(snippets.rport)")
        if let scope { text += " · " + scope.label }
        return text + "\nUsed by one-liners, checklists, saved connections and bound terminals; typed commands naming this host are tagged with it in the Log."
    }
}

/// The host's recent commands and events, shown on a host node in Targets.
struct HostActivityPanel: View {
    let host: TargetNode
    @Environment(UIState.self) private var ui
    @State private var expanded = false

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd-MM HH:mm"
        return formatter
    }()

    var body: some View {
        let entries = Array(TargetContext.activity(for: host).reversed())
        DisclosureGroup(isExpanded: $expanded) {
            if entries.isEmpty {
                Text("Nothing in the Log mentions this host yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(entries.prefix(40)) { entry in
                        HStack(alignment: .top, spacing: 6) {
                            Text(HostActivityPanel.timeFormatter.string(from: entry.time))
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Image(systemName: entry.kind.symbol)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(width: 12)
                            Text(entry.text)
                                .font(.system(.caption, design: entry.kind == .command || entry.kind == .typed ? .monospaced : .default))
                                .lineLimit(2)
                                .textSelection(.enabled)
                            Spacer(minLength: 0)
                            if let outputID = entry.outputID, let output = CommandOutputStore.shared.record(id: outputID) {
                                Button {
                                    let message = EvidencePin.pin(command: output.command, output: CommandOutputStore.shared.text(of: output), time: output.time, source: output.source, to: .selectedTarget)
                                    ui.flash(message)
                                } label: {
                                    Image(systemName: "pin")
                                        .font(.caption2)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                                .help("Pin this command and its output (\(output.lines) lines) into the notes of this host")
                            }
                        }
                    }
                    if entries.count > 40 {
                        Button("Show all \(entries.count) in the Log") {
                            ActivityLog.shared.search = host.address
                            ui.open(.activity)
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }
                }
                .padding(.top, 4)
            }
        } label: {
            HStack(spacing: 6) {
                Label("Activity for this host", systemImage: "clock.arrow.circlepath")
                    .font(.subheadline.weight(.semibold))
                Text("\(entries.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}
