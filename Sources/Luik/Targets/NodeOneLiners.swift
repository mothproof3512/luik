import AppKit
import SwiftUI

/// The one-liners tagged for the selected host or port, with `$RHOST`, `$RPORT` and `$RURL`
/// already filled in — copy, or paste straight into the terminal. Work-item nodes show the
/// one-liners of the port (or host) they belong to.
struct OneLinersPanel: View {
    let node: TargetNode
    @Environment(SnippetStore.self) private var snippets
    @Environment(TargetStore.self) private var store
    @Environment(TerminalStore.self) private var terminals
    @Environment(UIState.self) private var ui
    @Environment(\.luikTheme) private var theme
    @AppStorage("targetsOneLinersExpanded") private var expanded = true
    @State private var copiedID: UUID?

    private static let maxRows = 8

    /// The port or host this node belongs to (itself when it is one).
    private var context: TargetNode {
        var current: TargetNode? = node
        while let candidate = current {
            if candidate.kind == .port || candidate.kind == .host { return candidate }
            current = store.parent(of: candidate.id)
        }
        return node
    }

    private var address: String {
        store.host(of: context)?.address ?? context.address
    }

    private var port: Int? {
        context.kind == .port ? context.portNumber : nil
    }

    private var service: String {
        context.kind == .port ? TargetStore.serviceName(of: context) : ""
    }

    /// Matching one-liners, the ones you used before at this service first.
    private var matching: [Snippet] {
        let base = context.kind == .port ? snippets.snippets(forService: service, port: context.portNumber) : snippets.hostSnippets
        return UsageStore.shared.ranked(base, service: service)
    }

    /// Counts a use (copy or paste) of the one-liner that owns `id` (a snippet or one of its steps).
    private func noteUse(of id: UUID) {
        let snippet = matching.first { $0.id == id } ?? matching.first { $0.steps.contains { $0.id == id } }
        guard let snippet else { return }
        UsageStore.shared.recordSnippet(snippet.id, service: service)
    }

    private var contextLabel: String {
        if let port {
            let name = service.isEmpty ? "port \(port)" : service
            return "\(name) (\(address):\(port))"
        }
        return address.isEmpty ? context.title : address
    }

    private var isCurrentTarget: Bool {
        snippets.target == address && (port == nil || snippets.rport == String(port ?? 0))
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 4) {
                targetLine
                if matching.isEmpty {
                    Text(service.isEmpty && port != nil
                         ? "No one-liners tagged for port \(port ?? 0) yet."
                         : "No one-liners tagged for \(port == nil ? "hosts" : "“\(service)”") yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Tag one in the One-liners tab: edit it and fill in “Show in Targets at” (service names, port numbers, host, port).")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(matching.prefix(OneLinersPanel.maxRows)) { snippet in
                        row(for: snippet)
                    }
                    if matching.count > OneLinersPanel.maxRows {
                        Button("… and \(matching.count - OneLinersPanel.maxRows) more in the One-liners tab") {
                            snippets.search = ""
                            ui.module = .snippets
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }
                }
            }
            .padding(.top, 4)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                Text("One-liners for \(contextLabel)")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !matching.isEmpty {
                    Text("\(matching.count)")
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.white.opacity(0.1), in: Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "$RHOST = 10.10.10.5" or a button that makes this host/port the One-liners target.
    @ViewBuilder
    private var targetLine: some View {
        if address.isEmpty {
            EmptyView()
        } else if isCurrentTarget {
            Label(port.map { "$RHOST = \(address), $RPORT = \($0)" } ?? "$RHOST = \(address)", systemImage: "checkmark.circle")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
        } else {
            Button {
                snippets.target = address
                if let port { snippets.rport = String(port) }
                snippets.saveTarget()
            } label: {
                Label(port.map { "Use \(address):\($0) as $RHOST / $RPORT" } ?? "Use \(address) as $RHOST", systemImage: "scope")
                    .font(.caption2)
            }
            .buttonStyle(.link)
            .help("Also fills the variables in the One-liners tab, for the export button and the saved connections")
        }
    }

    /// "Title · 3×" when you used it at this service before.
    private func usageTitle(_ snippet: Snippet) -> String {
        guard let record = UsageStore.shared.usage(of: snippet.id) else { return snippet.title }
        let here = record.byService[UsageStore.serviceKey(service)] ?? 0
        return here > 0 ? "\(snippet.title) · \(here)×" : snippet.title
    }

    private func row(for snippet: Snippet) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if snippet.isMultiStep {
                HStack(spacing: 6) {
                    Text(snippet.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text("\(snippet.steps.count) steps")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button {
                        let all = snippet.steps.map { resolve($0.command) }.joined(separator: "\n")
                        copy(all, id: snippet.id)
                    } label: {
                        Image(systemName: copiedID == snippet.id ? "checkmark" : "doc.on.doc.fill")
                            .foregroundStyle(copiedID == snippet.id ? Color.green : theme.accentColor)
                            .frame(width: 16)
                    }
                    .buttonStyle(.plain)
                    .help("Copy every step, one per line")
                }
                ForEach(Array(snippet.steps.enumerated()), id: \.element.id) { index, step in
                    commandLine(title: step.label.isEmpty ? "Step \(index + 1)" : "\(index + 1). \(step.label)",
                                command: resolve(step.command), id: step.id, titleIsSecondary: true)
                        .padding(.leading, 10)
                }
            } else if let step = snippet.steps.first {
                commandLine(title: usageTitle(snippet), command: resolve(step.command), id: snippet.id, titleIsSecondary: false)
            }
        }
    }

    private func resolve(_ command: String) -> String {
        snippets.resolve(command, rhost: address, rport: port, service: service)
    }

    private func copy(_ text: String, id: UUID) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        copiedID = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if copiedID == id { copiedID = nil }
        }
    }

    /// One command with its copy and paste buttons.
    private func commandLine(title: String, command: String, id: UUID, titleIsSecondary: Bool) -> some View {
        let copied = copiedID == id
        return HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(titleIsSecondary ? .caption2 : .caption.weight(.semibold))
                    .foregroundStyle(titleIsSecondary ? Color.secondary : Color.primary)
                    .lineLimit(1)
                Text(command)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                copy(command, id: id)
                noteUse(of: id)
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .foregroundStyle(copied ? Color.green : theme.accentColor)
                    .frame(width: 16)
            }
            .buttonStyle(.plain)
            .help("Copy")
            Button {
                terminals.sendToSelected(command, source: "Targets")
                noteUse(of: id)
                ui.module = .terminal
                terminals.focusSelected(afterDelay: true)
            } label: {
                Image(systemName: "terminal")
                    .frame(width: 16)
            }
            .buttonStyle(.plain)
            .help("Paste into the active terminal (without Enter)")
        }
        .help(command)
    }
}
