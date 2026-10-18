import AppKit
import SwiftUI

struct SnippetsView: View {
    @Environment(SnippetStore.self) private var store
    @Environment(TerminalStore.self) private var terminals
    @Environment(UIState.self) private var ui
    @State private var editing: Snippet?
    @State private var copiedID: UUID?
    @State private var exported = false

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField("Search…", text: $store.search)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 120, maxWidth: 200)
                HStack(spacing: 4) {
                    variableField("$RHOST", text: $store.target, placeholder: "10.10.10.5", width: 130)
                    variableField("$RPORT", text: $store.rport, placeholder: "port", width: 52)
                    variableField("$LHOST", text: $store.lhost, placeholder: "your IP", width: 120)
                    Button {
                        store.detectLHost()
                    } label: {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                    }
                    .help(lhostHelp)
                    variableField("$LPORT", text: $store.lport, placeholder: "4444", width: 64)
                    Button {
                        guard let line = store.exportLine else { return }
                        terminals.sendToSelected(line + "\n", source: "One-liners (export)")
                        flashExported()
                    } label: {
                        Label(exported ? "Set" : "export", systemImage: exported ? "checkmark" : "arrow.right.square")
                    }
                    .disabled(store.exportLine == nil)
                    .help("Runs `export RHOST=… RPORT=… RURL=… LHOST=… LPORT=…` in the active terminal tab, so the variables work there as well")
                }
                Spacer()
                Button {
                    ui.showReverseShell = true
                } label: {
                    Label("Reverse shell", systemImage: "arrow.uturn.backward.circle")
                }
                .help("Reverse shell generator: a template from the cheat sheet in the library, $LHOST/$LPORT, shell and encoding, with the listener and the TTY upgrade")
                Menu {
                    Button("Add missing defaults") {
                        store.addMissingDefaults()
                    }
                    Button("Show data folder in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([Storage.url(for: "snippets.json")])
                    }
                    Divider()
                    Text("Drag a row to reorder it within its category; right-click a row or a category heading for more.")
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .frame(width: 44)
                Button {
                    editing = Snippet(title: "", command: "", category: store.allCategories.first ?? "General")
                } label: {
                    Label("New", systemImage: "plus")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if store.filtered.isEmpty {
                VStack {
                    Spacer()
                    Text(store.snippets.isEmpty ? "No one-liners yet. Add one with New." : "No results for this search.")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                let searching = !store.search.trimmingCharacters(in: .whitespaces).isEmpty
                let categories = store.filteredCategories
                List {
                    if !searching {
                        let frequent = UsageStore.shared.mostUsed(from: store.snippets)
                        if !frequent.isEmpty {
                            Section("Most used") {
                                ForEach(frequent) { snippet in
                                    HStack(spacing: 8) {
                                        Text(snippet.title)
                                            .lineLimit(1)
                                        Text("\(UsageStore.shared.usage(of: snippet.id)?.count ?? 0)×")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .monospacedDigit()
                                        Spacer()
                                        Text(store.resolve(snippet.command))
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                            .frame(maxWidth: 360, alignment: .trailing)
                                        Button {
                                            store.copyToClipboard(snippet)
                                            flashCopied(snippet.id)
                                            UsageStore.shared.recordSnippet(snippet.id, service: currentService)
                                        } label: {
                                            Image(systemName: copiedID == snippet.id ? "checkmark" : "doc.on.doc")
                                        }
                                        .buttonStyle(.plain)
                                        .help("Copy")
                                        Button {
                                            terminals.sendToSelected(store.resolve(snippet.command), source: "One-liners")
                                            UsageStore.shared.recordSnippet(snippet.id, service: currentService)
                                            ui.module = .terminal
                                            terminals.focusSelected(afterDelay: true)
                                        } label: {
                                            Image(systemName: "terminal")
                                        }
                                        .buttonStyle(.plain)
                                        .help("Paste into the active terminal")
                                    }
                                    .contextMenu {
                                        Button("Edit…") { editing = snippet }
                                    }
                                }
                            }
                        }
                    }
                    ForEach(categories, id: \.self) { category in
                        Section {
                            ForEach(store.filtered.filter { $0.category == category }) { snippet in
                                SnippetRow(snippet: snippet,
                                           isCopied: copiedID == snippet.id,
                                           copyAll: {
                                               store.copyToClipboard(snippet)
                                               flashCopied(snippet.id)
                                               UsageStore.shared.recordSnippet(snippet.id, service: currentService)
                                           },
                                           copyStep: { step in
                                               store.copyToClipboard(text: store.resolve(step.command))
                                               flashCopied(step.id)
                                               UsageStore.shared.recordSnippet(snippet.id, service: currentService)
                                           },
                                           stepCopied: { step in copiedID == step.id },
                                           paste: { step in
                                               terminals.sendToSelected(store.resolve(step.command), source: "One-liners")
                                               UsageStore.shared.recordSnippet(snippet.id, service: currentService)
                                               ui.module = .terminal
                                               terminals.focusSelected(afterDelay: true)
                                           },
                                           edit: { editing = snippet },
                                           delete: { store.delete(snippet.id) })
                                    .contextMenu {
                                        Button("Edit…") { editing = snippet }
                                        Button("Duplicate") { store.duplicate(snippet.id) }
                                        Divider()
                                        Button("Move up") { store.move(snippet.id, .up) }
                                        Button("Move down") { store.move(snippet.id, .down) }
                                        Button("Move to top") { store.move(snippet.id, .top) }
                                        Button("Move to bottom") { store.move(snippet.id, .bottom) }
                                        Divider()
                                        Button("Delete", role: .destructive) { store.delete(snippet.id) }
                                    }
                            }
                            .onMove { source, destination in
                                guard !searching else { return }
                                store.move(inCategory: category, from: source, to: destination)
                            }
                        } header: {
                            HStack(spacing: 6) {
                                Text(category)
                                Spacer()
                                if !searching, categories.count > 1 {
                                    Button {
                                        store.moveCategory(category, up: true)
                                    } label: {
                                        Image(systemName: "chevron.up")
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.secondary)
                                    .disabled(categories.first == category)
                                    .help("Move this category up")
                                    Button {
                                        store.moveCategory(category, up: false)
                                    } label: {
                                        Image(systemName: "chevron.down")
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.secondary)
                                    .disabled(categories.last == category)
                                    .help("Move this category down")
                                }
                            }
                            .contextMenu {
                                Button("Move category up") { store.moveCategory(category, up: true) }
                                Button("Move category down") { store.moveCategory(category, up: false) }
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .sheet(item: $editing) { snippet in
            SnippetEditor(snippet: snippet, categories: store.allCategories) { saved in
                store.upsert(saved)
            }
        }
        .onAppear(perform: takePendingSnippet)
        .onChange(of: ui.pendingSnippet) { _, _ in takePendingSnippet() }
    }

    /// A one-liner another tab handed over (Log › Save as one-liner) opens in the editor.
    private func takePendingSnippet() {
        guard let pending = ui.pendingSnippet else { return }
        ui.pendingSnippet = nil
        editing = pending
    }

    /// Service of the selected port in Targets (what a use is counted against).
    private var currentService: String {
        guard let node = TargetStore.shared.selectedNode, node.kind == .port else { return "" }
        return TargetStore.serviceName(of: node)
    }

    /// "$NAME = [field]" with autosave.
    private func variableField(_ name: String, text: Binding<String>, placeholder: String, width: CGFloat) -> some View {
        HStack(spacing: 3) {
            Text("\(name) =")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .frame(width: width)
                .onChange(of: text.wrappedValue) { _, _ in
                    store.saveTarget()
                }
        }
    }

    private var lhostHelp: String {
        let interfaces = LocalAddress.interfaces()
        guard !interfaces.isEmpty else { return "Detect your own IP address (no interfaces found)" }
        let list = interfaces.map { "\($0.name): \($0.address)\($0.isTunnel ? " (VPN)" : "")" }.joined(separator: "\n")
        return "Detect your own IP address — VPN tunnels (utun/tun) are preferred:\n\(list)"
    }

    private func flashCopied(_ id: UUID) {
        copiedID = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if copiedID == id {
                copiedID = nil
            }
        }
    }

    private func flashExported() {
        exported = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            exported = false
        }
    }
}

/// One one-liner: a single command on one line, or its numbered steps with their own buttons.
struct SnippetRow: View {
    let snippet: Snippet
    let isCopied: Bool
    let copyAll: () -> Void
    let copyStep: (SnippetStep) -> Void
    let stepCopied: (SnippetStep) -> Bool
    let paste: (SnippetStep) -> Void
    let edit: () -> Void
    let delete: () -> Void
    @Environment(SnippetStore.self) private var store
    @Environment(\.luikTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(snippet.title)
                            .font(.callout.weight(.semibold))
                        if snippet.isMultiStep {
                            Text("\(snippet.steps.count) steps")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.white.opacity(0.1), in: Capsule())
                        }
                        if !snippet.services.isEmpty {
                            Text(snippet.servicesText)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.white.opacity(0.1), in: Capsule())
                                .help("Shown in Targets under: \(snippet.servicesText)")
                        }
                        if let document = LibraryLink.document(for: snippet) {
                            LibraryLinkButton(document: document, compact: true)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !snippet.isMultiStep, let step = snippet.steps.first {
                        Text(store.resolve(step.command))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }
                }
                Spacer()
                Button(action: copyAll) {
                    Label(isCopied ? "Copied" : (snippet.isMultiStep ? "Copy all" : "Copy"), systemImage: isCopied ? "checkmark" : "doc.on.doc")
                        .frame(width: 96)
                }
                .buttonStyle(.borderedProminent)
                .tint(isCopied ? Color.green : theme.accentColor)
                .help(snippet.isMultiStep ? "Copy every step, one per line" : "Copy")
                if !snippet.isMultiStep, let step = snippet.steps.first {
                    Button {
                        paste(step)
                    } label: {
                        Image(systemName: "terminal")
                    }
                    .help("Paste into the active terminal")
                }
                Button(action: edit) {
                    Image(systemName: "pencil")
                }
                .help("Edit")
                Button(role: .destructive, action: delete) {
                    Image(systemName: "trash")
                }
                .help("Delete")
            }
            if snippet.isMultiStep {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(snippet.steps.enumerated()), id: \.element.id) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(index + 1)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(theme.accentColor)
                                .frame(width: 16, alignment: .trailing)
                            VStack(alignment: .leading, spacing: 1) {
                                if !step.label.isEmpty {
                                    Text(step.label)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text(store.resolve(step.command))
                                    .font(.system(.caption, design: .monospaced))
                                    .lineLimit(3)
                                    .textSelection(.enabled)
                            }
                            Spacer(minLength: 0)
                            Button {
                                copyStep(step)
                            } label: {
                                Image(systemName: stepCopied(step) ? "checkmark" : "doc.on.doc")
                                    .foregroundStyle(stepCopied(step) ? Color.green : theme.accentColor)
                                    .frame(width: 16)
                            }
                            .buttonStyle(.plain)
                            .help("Copy this step")
                            Button {
                                paste(step)
                            } label: {
                                Image(systemName: "terminal")
                                    .frame(width: 16)
                            }
                            .buttonStyle(.plain)
                            .help("Paste this step into the active terminal")
                        }
                    }
                }
                .padding(.leading, 2)
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Add / edit a one-liner: title, category, its steps (one is enough) and where Targets shows it.
struct SnippetEditor: View {
    @State var snippet: Snippet
    var categories: [String] = []
    let onSave: (Snippet) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var servicesText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("One-liner")
                .font(.headline)
            TextField("Title", text: $snippet.title)
                .textFieldStyle(.roundedBorder)
            HStack(spacing: 6) {
                TextField("Category", text: $snippet.category)
                    .textFieldStyle(.roundedBorder)
                if !categories.isEmpty {
                    Menu {
                        ForEach(categories, id: \.self) { category in
                            Button(category) { snippet.category = category }
                        }
                    } label: {
                        Image(systemName: "chevron.down.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Pick an existing category")
                }
            }
            Text("Steps — one command, or several that belong together (listener, payload, upgrade). Placeholders: $RHOST (target), $RPORT (port), $RURL (http(s)://target:port), $LHOST (your IP), $LPORT (your port)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(snippet.steps.enumerated()), id: \.element.id) { index, step in
                        stepEditor(index: index, step: step)
                    }
                    Button {
                        snippet.steps.append(SnippetStep(command: ""))
                    } label: {
                        Label("Add step", systemImage: "plus")
                    }
                    .buttonStyle(.link)
                }
            }
            .frame(minHeight: 150, maxHeight: 360)
            Text("Show in Targets at — service names or port numbers (http, microsoft-ds, 445, …), \"host\" for every host, \"port\" for every port; empty = only here")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("http, https, 80, 443, 8080", text: $servicesText)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .onChange(of: servicesText) { _, text in
                    snippet.services = Snippet.parseServices(text)
                }
            Text("Read more — a library page (picked with the book, or a topic such as “SMB”) or a URL; empty = Luik looks for a page named after the service")
                .font(.caption)
                .foregroundStyle(.secondary)
            LibraryLinkField(link: $snippet.link)
            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Save") {
                    var saved = snippet
                    saved.steps = saved.steps.filter { !$0.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    if saved.steps.isEmpty { return }
                    if saved.title.trimmingCharacters(in: .whitespaces).isEmpty {
                        saved.title = String(saved.command.prefix(40))
                    }
                    if saved.category.trimmingCharacters(in: .whitespaces).isEmpty {
                        saved.category = "General"
                    }
                    onSave(saved)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!snippet.steps.contains { !$0.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            }
        }
        .padding(16)
        .frame(width: 600)
        .onAppear {
            servicesText = snippet.servicesText
        }
    }

    private func stepEditor(index: Int, step: SnippetStep) -> some View {
        let binding = Binding<SnippetStep>(
            get: { snippet.steps.first { $0.id == step.id } ?? step },
            set: { newValue in
                if let position = snippet.steps.firstIndex(where: { $0.id == step.id }) {
                    snippet.steps[position] = newValue
                }
            }
        )
        return HStack(alignment: .top, spacing: 6) {
            Text("\(index + 1)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .trailing)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 4) {
                if snippet.steps.count > 1 {
                    TextField("Label (optional): On the target, Listener, …", text: binding.label)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                }
                TextEditor(text: binding.command)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: snippet.steps.count > 1 ? 44 : 100)
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
            }
            if snippet.steps.count > 1 {
                VStack(spacing: 2) {
                    Button {
                        SnippetStore.reorder(&snippet.steps, from: IndexSet(integer: index), to: max(index - 1, 0))
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .buttonStyle(.plain)
                    .disabled(index == 0)
                    Button {
                        SnippetStore.reorder(&snippet.steps, from: IndexSet(integer: index), to: min(index + 2, snippet.steps.count))
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .buttonStyle(.plain)
                    .disabled(index == snippet.steps.count - 1)
                    Button(role: .destructive) {
                        snippet.steps.remove(at: index)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                }
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            }
        }
    }
}
