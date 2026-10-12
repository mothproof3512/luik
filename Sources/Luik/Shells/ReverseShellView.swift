import AppKit
import SwiftUI

/// Reverse shell generator: a template from the cheat sheet in the library (or one of your own
/// one-liners), your address and port, the shell to spawn and an encoding — plus the listener to
/// start first and the TTY upgrade for afterwards. Save the three as one multi-step one-liner.
struct ReverseShellView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.luikTheme) private var theme
    @Environment(SnippetStore.self) private var snippets
    @Environment(LibraryStore.self) private var library
    @Environment(TerminalStore.self) private var terminals
    @Environment(UIState.self) private var ui
    @Environment(NotesStore.self) private var notes

    @State private var catalog = ReverseShellCatalog.Catalog(templates: [], ttyUpgrades: [], source: nil)
    @State private var search = ""
    @State private var selectedID: String?
    @AppStorage("reverseShellShell") private var shell = "/bin/bash"
    @AppStorage("reverseShellListener") private var listenerIndex = 1
    @AppStorage("reverseShellEncoding") private var encodingRaw = ReverseShellCatalog.Encoding.none.rawValue
    @State private var ttyIndex = 0
    @State private var copied: String?
    @State private var saved = false

    private var encoding: ReverseShellCatalog.Encoding {
        ReverseShellCatalog.Encoding(rawValue: encodingRaw) ?? .none
    }

    private var selected: ShellTemplate? {
        catalog.templates.first { $0.id == selectedID }
    }

    private var filteredTemplates: [ShellTemplate] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return catalog.templates }
        return catalog.templates.filter { ($0.name + " " + ($0.language ?? "") + " " + $0.code).lowercased().contains(query) }
    }

    private var groups: [String] {
        var seen: [String] = []
        for template in filteredTemplates where !seen.contains(template.group) { seen.append(template.group) }
        return seen
    }

    private var listener: String {
        let entry = ReverseShellCatalog.listeners[min(max(listenerIndex, 0), ReverseShellCatalog.listeners.count - 1)]
        return ReverseShellCatalog.listener(entry.command, lhost: snippets.lhost, lport: snippets.lport)
    }

    private var payload: String {
        guard let selected else { return "" }
        let plain = ReverseShellCatalog.fill(selected, lhost: snippets.lhost, lport: snippets.lport, shell: shell)
        let effective: ReverseShellCatalog.Encoding = (encoding == .powershellBase64 && !selected.isPowerShell) ? .base64 : encoding
        return ReverseShellCatalog.encode(plain, as: effective, shell: shell)
    }

    private var ttyUpgrade: String? {
        guard !catalog.ttyUpgrades.isEmpty else { return nil }
        return catalog.ttyUpgrades[min(max(ttyIndex, 0), catalog.ttyUpgrades.count - 1)]
    }

    var body: some View {
        @Bindable var snippets = snippets
        VStack(spacing: 0) {
            HStack {
                Text("Reverse shell")
                    .font(.headline)
                if let source = catalog.source {
                    Button {
                        notes.open(source)
                        ui.module = .notes
                        dismiss()
                    } label: {
                        Label("from \(source.collection) › \(source.title)", systemImage: "books.vertical")
                            .font(.caption)
                    }
                    .buttonStyle(.link)
                    .help("Open the cheat sheet in the library")
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)
            Divider()
            if catalog.templates.isEmpty {
                emptyState
            } else {
                HSplitView {
                    templateList
                        .frame(minWidth: 200, idealWidth: 240, maxWidth: 320)
                    generator(snippets: $snippets)
                        .frame(minWidth: 420)
                }
            }
        }
        .frame(width: 900, height: 600)
        .onAppear(perform: reload)
    }

    private func reload() {
        library.scanIfNeeded()
        catalog = ReverseShellCatalog.load(from: library, snippets: snippets)
        if selectedID == nil || !catalog.templates.contains(where: { $0.id == selectedID }) {
            selectedID = catalog.templates.first { $0.name.lowercased().hasPrefix("bash") }?.id ?? catalog.templates.first?.id
        }
    }

    // MARK: Empty

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "terminal")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No reverse shell templates in the library yet.")
                .font(.headline)
            Text("The generator reads the Reverse Shell Cheat Sheet from the documentation you download into the library — InternalAllTheThings (where the sheet lives now) or PayloadsAllTheThings — and your own one-liners in a category named “Reverse shells”. Nothing is bundled with Luik, so the templates update with the documentation.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 560)
            HStack {
                Button {
                    dismiss()
                    ui.module = .notes
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { ui.showLibrarySources = true }
                } label: {
                    Label("Download documentation…", systemImage: "icloud.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                Button("Rescan library") {
                    library.rescan()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: reload)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    // MARK: Templates

    private var templateList: some View {
        VStack(spacing: 0) {
            TextField("Filter (python, powershell, …)", text: $search)
                .textFieldStyle(.roundedBorder)
                .padding(8)
            List(selection: $selectedID) {
                ForEach(groups, id: \.self) { group in
                    Section(group) {
                        ForEach(filteredTemplates.filter { $0.group == group }) { template in
                            HStack(spacing: 6) {
                                Text(template.name)
                                    .lineLimit(1)
                                Spacer()
                                if let language = template.language {
                                    Text(language)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .tag(template.id)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
    }

    // MARK: Generator

    private func generator(snippets store: Bindable<SnippetStore>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                labelled("$LHOST") {
                    TextField("your IP", text: store.lhost)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                        .onChange(of: store.wrappedValue.lhost) { _, _ in store.wrappedValue.saveTarget() }
                }
                Button {
                    store.wrappedValue.detectLHost()
                } label: {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                }
                .help("Detect your own IP address (VPN tunnels preferred)")
                labelled("$LPORT") {
                    TextField("4444", text: store.lport)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                        .onChange(of: store.wrappedValue.lport) { _, _ in store.wrappedValue.saveTarget() }
                }
                labelled("Shell") {
                    Picker("", selection: $shell) {
                        ForEach(ReverseShellCatalog.shells, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }
                .help("Replaces /bin/sh and /bin/bash in the template")
                Spacer()
            }
            HStack(spacing: 8) {
                labelled("Listener") {
                    Picker("", selection: $listenerIndex) {
                        ForEach(Array(ReverseShellCatalog.listeners.enumerated()), id: \.offset) { index, entry in
                            Text(entry.name).tag(index)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 260)
                }
                labelled("Encoding") {
                    Picker("", selection: $encodingRaw) {
                        ForEach(ReverseShellCatalog.Encoding.allCases) { option in
                            Text(option.label).tag(option.rawValue)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 300)
                }
                Spacer()
            }
            if let selected, !selected.note.isEmpty {
                Text(selected.note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    step(number: 1, title: "Listener — on your machine, first", text: listener, id: "listener", pasteable: true)
                    step(number: 2, title: "Payload — on the target", text: payload, id: "payload", pasteable: false)
                    if let hint = selected?.listenerHint {
                        Text("The sheet pairs this template with its own listener:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(ReverseShellCatalog.fill(ShellTemplate(id: "hint", name: "", group: "", language: nil, code: hint, note: ""), lhost: snippets.lhost, lport: snippets.lport, shell: shell))
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
                    }
                    if let ttyUpgrade {
                        VStack(alignment: .leading, spacing: 4) {
                            step(number: 3, title: "Upgrade to a full TTY — in the shell you got", text: ttyUpgrade, id: "tty", pasteable: true)
                            if catalog.ttyUpgrades.count > 1 {
                                Picker("", selection: $ttyIndex) {
                                    ForEach(Array(catalog.ttyUpgrades.enumerated()), id: \.offset) { index, line in
                                        Text(line).tag(index)
                                    }
                                }
                                .labelsHidden()
                                .frame(maxWidth: 420)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            Divider()
            HStack(spacing: 8) {
                Button {
                    saveAsOneLiner()
                } label: {
                    Label(saved ? "Saved" : "Save as one-liner", systemImage: saved ? "checkmark" : "plus.rectangle.on.rectangle")
                }
                .disabled(selected == nil)
                .help("Adds a multi-step one-liner (listener, payload with $LHOST/$LPORT, TTY upgrade) to the Reverse shells category")
                Button {
                    let all = [listener, payload, ttyUpgrade].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
                    copy(all, id: "all")
                } label: {
                    Label(copied == "all" ? "Copied" : "Copy all steps", systemImage: copied == "all" ? "checkmark" : "doc.on.doc")
                }
                Spacer()
                Text("Only for systems you are authorised to test.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
    }

    private func labelled<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func step(number: Int, title: String, text: String, id: String, pasteable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("\(number)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(theme.accentColor)
                Text(title)
                    .font(.caption.weight(.semibold))
                Spacer()
                Button {
                    copy(text, id: id)
                } label: {
                    Label(copied == id ? "Copied" : "Copy", systemImage: copied == id ? "checkmark" : "doc.on.doc")
                        .frame(width: 84)
                }
                .buttonStyle(.borderedProminent)
                .tint(copied == id ? Color.green : theme.accentColor)
                .disabled(text.isEmpty)
                if pasteable {
                    Button {
                        terminals.sendToSelected(text, source: "Reverse shell")
                        ui.module = .terminal
                        dismiss()
                        terminals.focusSelected(afterDelay: true)
                    } label: {
                        Image(systemName: "terminal")
                    }
                    .disabled(text.isEmpty)
                    .help("Paste into the active terminal (without Enter)")
                }
            }
            Text(text.isEmpty ? "—" : text)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private func copy(_ text: String, id: String) {
        guard !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        copied = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if copied == id { copied = nil }
        }
    }

    /// A multi-step one-liner with the placeholders kept, so it follows $LHOST / $LPORT later.
    private func saveAsOneLiner() {
        guard let selected else { return }
        let entry = ReverseShellCatalog.listeners[min(max(listenerIndex, 0), ReverseShellCatalog.listeners.count - 1)]
        var steps = [
            SnippetStep(label: "Listener (your machine)", command: entry.command),
            SnippetStep(label: "On the target", command: ReverseShellCatalog.fill(selected, lhost: "$LHOST", lport: "$LPORT", shell: shell)),
        ]
        if let ttyUpgrade {
            steps.append(SnippetStep(label: "Upgrade to a TTY", command: ttyUpgrade))
        }
        let title = "Reverse shell: \(selected.name)\(shell == "/bin/bash" ? "" : " (\(shell))")"
        snippets.upsert(Snippet(title: title, steps: steps, category: "Reverse shells"))
        ActivityLog.shared.record(.action, "One-liner saved from the reverse shell generator: \(title)", source: "Reverse shell")
        saved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { saved = false }
    }
}
