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
                    .help("Runs `export RHOST=… LHOST=… LPORT=…` in the active terminal tab, so the variables work there as well")
                }
                Spacer()
                Menu {
                    Button("Add missing defaults") {
                        store.addMissingDefaults()
                    }
                    Button("Show data folder in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([Storage.url(for: "snippets.json")])
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .frame(width: 44)
                Button {
                    editing = Snippet(title: "", command: "", category: "General")
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
                List {
                    ForEach(store.filteredCategories, id: \.self) { category in
                        Section(category) {
                            ForEach(store.filtered.filter { $0.category == category }) { snippet in
                                SnippetRow(snippet: snippet,
                                           resolved: store.resolve(snippet.command),
                                           isCopied: copiedID == snippet.id,
                                           copy: {
                                               store.copyToClipboard(snippet)
                                               flashCopied(snippet.id)
                                           },
                                           paste: {
                                               terminals.sendToSelected(store.resolve(snippet.command), source: "One-liners")
                                               ui.module = .terminal
                                               terminals.focusSelected(afterDelay: true)
                                           },
                                           edit: { editing = snippet },
                                           delete: { store.delete(snippet.id) })
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .sheet(item: $editing) { snippet in
            SnippetEditor(snippet: snippet) { saved in
                store.upsert(saved)
            }
        }
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

struct SnippetRow: View {
    let snippet: Snippet
    let resolved: String
    let isCopied: Bool
    let copy: () -> Void
    let paste: () -> Void
    let edit: () -> Void
    let delete: () -> Void
    @Environment(\.luikTheme) private var theme

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(snippet.title)
                    .font(.callout.weight(.semibold))
                Text(resolved)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
            Spacer()
            Button(action: copy) {
                Label(isCopied ? "Copied" : "Copy", systemImage: isCopied ? "checkmark" : "doc.on.doc")
                    .frame(width: 96)
            }
            .buttonStyle(.borderedProminent)
            .tint(isCopied ? Color.green : theme.accentColor)
            Button(action: paste) {
                Image(systemName: "terminal")
            }
            .help("Paste into the active terminal")
            Button(action: edit) {
                Image(systemName: "pencil")
            }
            .help("Edit")
            Button(role: .destructive, action: delete) {
                Image(systemName: "trash")
            }
            .help("Delete")
        }
        .padding(.vertical, 4)
    }
}

struct SnippetEditor: View {
    @State var snippet: Snippet
    let onSave: (Snippet) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("One-liner")
                .font(.headline)
            TextField("Title", text: $snippet.title)
                .textFieldStyle(.roundedBorder)
            TextField("Category", text: $snippet.category)
                .textFieldStyle(.roundedBorder)
            Text("Command — placeholders: $RHOST (target), $LHOST (your IP), $LPORT (your port)")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: $snippet.command)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 110)
                .scrollContentBackground(.hidden)
                .padding(4)
                .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Save") {
                    var saved = snippet
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
                .disabled(snippet.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 540)
    }
}
