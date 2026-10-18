import AppKit
import SwiftUI

/// Sheet: the checklists that become work-item nodes under hosts and ports.
struct ChecklistEditorView: View {
    @Environment(ChecklistStore.self) private var store
    @Environment(TargetStore.self) private var targets
    @Environment(\.dismiss) private var dismiss
    @Environment(\.luikTheme) private var theme
    @State private var selectedID: UUID?
    @State private var testService = "http"
    @State private var testPort = "8080"
    @State private var showReset = false
    @State private var message: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Checklists")
                        .font(.headline)
                    Text("Every host you add — by hand or from a scan — gets the items of **Every system** as work-item nodes. Every open port gets the first service checklist whose keys match its service name (as nmap or Nessus report it: http, ssh, microsoft-ds, ms-sql-s, …) or its port number; ports without a match get **Every port**. Each item becomes a node with a status (to do → in progress → done → N/A) and notes; the hint is written into those notes with $RHOST and $RPORT filled in — the place for your own commands, checks and reminders. Changes apply to hosts and ports added from now on; **Apply to current targets** adds what is missing to the ones you already have.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)
            Divider()

            HStack(spacing: 0) {
                sidebar
                    .frame(width: 250)
                Divider()
                if let id = selectedID, store.checklist(id: id) != nil {
                    ChecklistEditor(checklist: binding(for: id), isService: store.lists.services.contains { $0.id == id })
                        .id(id)
                } else {
                    VStack {
                        Spacer()
                        Text("Select a checklist")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            Divider()
            footer
        }
        .frame(width: 900, height: 620)
        .onAppear { selectedID = store.lists.host.id }
        .confirmationDialog("Replace all checklists with the built-in defaults?", isPresented: $showReset) {
            Button("Reset to defaults", role: .destructive) {
                store.resetToDefaults()
                selectedID = store.lists.host.id
            }
        } message: {
            Text("Your own lists, keys and hints are lost. Export first if you want to keep them.")
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selectedID) {
                Section("Always") {
                    ChecklistRowLabel(checklist: store.lists.host, icon: "desktopcomputer", subtitle: "under every host")
                        .tag(store.lists.host.id)
                    ChecklistRowLabel(checklist: store.lists.port, icon: "network", subtitle: "ports without a service match")
                        .tag(store.lists.port.id)
                }
                Section("Per service — first match wins") {
                    ForEach(store.lists.services) { checklist in
                        ChecklistRowLabel(checklist: checklist, icon: checklist.enabled ? "list.bullet.rectangle" : "list.bullet.rectangle.portrait",
                                          subtitle: checklist.keys.isEmpty ? "no keys yet — never matches" : checklist.keysText)
                            .opacity(checklist.enabled ? 1 : 0.5)
                            .tag(checklist.id)
                    }
                    .onMove { source, destination in
                        store.moveService(from: source, to: destination)
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            Divider()
            HStack(spacing: 8) {
                Button {
                    let created = store.addService()
                    selectedID = created.id
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add a service checklist")
                Button {
                    if let id = selectedID, store.lists.services.contains(where: { $0.id == id }) {
                        store.deleteService(id)
                        selectedID = store.lists.host.id
                    }
                } label: {
                    Image(systemName: "minus")
                }
                .disabled(!isServiceSelected)
                .help("Delete the selected service checklist")
                Button {
                    if let id = selectedID { store.moveService(id, up: true) }
                } label: {
                    Image(systemName: "arrow.up")
                }
                .disabled(!isServiceSelected)
                .help("Move up (earlier lists win when keys overlap)")
                Button {
                    if let id = selectedID { store.moveService(id, up: false) }
                } label: {
                    Image(systemName: "arrow.down")
                }
                .disabled(!isServiceSelected)
                .help("Move down")
                Spacer()
            }
            .padding(8)
        }
    }

    private var isServiceSelected: Bool {
        guard let id = selectedID else { return false }
        return store.lists.services.contains { $0.id == id }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text("Which list does a port get?")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("service", text: $testService)
                .textFieldStyle(.roundedBorder)
                .frame(width: 110)
            TextField("port", text: $testPort)
                .textFieldStyle(.roundedBorder)
                .frame(width: 60)
            let result = store.checklist(forService: testService, port: Int(testPort.trimmingCharacters(in: .whitespaces)) ?? 0)
            Text("→ \(result.name)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.accentColor)
                .lineLimit(1)
            Spacer()
            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Apply to current targets") {
                let added = targets.applyChecklistsEverywhere()
                message = added == 0 ? "Nothing missing on the current targets." : "\(added) node(s) added."
            }
            .help("Add missing checklist items to every host and port of the current engagement")
            Menu {
                Button("All checklists as JSON…") { message = ChecklistTransfer.exportAll(as: .json) }
                Button("All checklists as Markdown…") { message = ChecklistTransfer.exportAll(as: .markdown) }
                if let id = selectedID, let selected = store.checklist(id: id) {
                    Divider()
                    Button("Only “\(selected.name.isEmpty ? "Untitled" : selected.name)” as JSON…") { message = ChecklistTransfer.export([selected]) }
                }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .fixedSize()
            .help("Share your checklists: JSON imports back into Luik; Markdown is for a wiki or repository (and imports too)")
            Button {
                message = ChecklistTransfer.importWithPrompt()
                selectedID = store.lists.host.id
            } label: {
                Label("Import…", systemImage: "square.and.arrow.down")
            }
            .help("Import a JSON or Markdown file exported from Luik — a full set (merge or replace) or single checklists (added)")
            Menu {
                Button("Reset to defaults…", role: .destructive) { showReset = true }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .frame(width: 44)
        }
        .padding(10)
    }

    private func binding(for id: UUID) -> Binding<Checklist> {
        Binding(
            get: { store.checklist(id: id) ?? Checklist(name: "", items: []) },
            set: { store.update($0) }
        )
    }
}

struct ChecklistRowLabel: View {
    let checklist: Checklist
    let icon: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(checklist.name.isEmpty ? "Untitled" : checklist.name)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text("\(checklist.items.count)")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

/// The right-hand pane: name, keys and the items of one checklist.
struct ChecklistEditor: View {
    @Binding var checklist: Checklist
    let isService: Bool
    @State private var keysText = ""
    @State private var newItem = ""
    @FocusState private var newItemFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Name", text: $checklist.name)
                .textFieldStyle(.plain)
                .font(.title2.weight(.semibold))

            if isService {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Applies to")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Toggle("Enabled", isOn: $checklist.enabled)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                    TextField("service names and/or port numbers, comma-separated — e.g. http, https, ssl/http, 80, 443, 8080", text: $keysText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    keySummary
                }
            } else {
                Text(checklist.id == ChecklistStore.shared.lists.host.id
                     ? "These items are added under every host (system)."
                     : "These items are added under ports that match none of the service checklists.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Items — each becomes a work-item node; the hint goes into its notes")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(checklist.items.count) item\(checklist.items.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            List {
                ForEach(Array(checklist.items.enumerated()), id: \.element.id) { index, item in
                    ChecklistItemRow(item: itemBinding(index),
                                     isFirst: index == 0,
                                     isLast: index == checklist.items.count - 1,
                                     moveUp: { move(index, to: index - 1) },
                                     moveDown: { move(index, to: index + 1) },
                                     delete: { if index < checklist.items.count { checklist.items.remove(at: index) } })
                        .listRowSeparator(.visible)
                }
                .onMove { source, destination in
                    checklist.items.move(fromOffsets: source, toOffset: destination)
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)

            HStack(spacing: 8) {
                TextField("New item (e.g. Default credentials)", text: $newItem)
                    .textFieldStyle(.roundedBorder)
                    .focused($newItemFocused)
                    .onSubmit(addItem)
                Button("Add item", action: addItem)
                    .disabled(newItem.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Text("Tip: $RHOST, $RPORT, $RURL (http(s)://host:port), $LHOST and $LPORT in a hint are replaced when the node is created. Drag items to reorder, or use the arrows.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { keysText = checklist.keysText }
        .onChange(of: keysText) { _, text in
            let keys = Checklist.parseKeys(text)
            if keys != checklist.keys { checklist.keys = keys }
        }
    }

    @ViewBuilder
    private var keySummary: some View {
        let keys = Checklist.parseKeys(keysText)
        if keys.isEmpty {
            Label("Without keys this list never matches a port.", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
        } else {
            let ports = keys.filter { Int($0) != nil }
            let names = keys.filter { Int($0) == nil }
            Text((names.isEmpty ? "" : "service name\(names.count == 1 ? "" : "s") \(names.joined(separator: ", "))")
                 + (names.isEmpty || ports.isEmpty ? "" : " · ")
                 + (ports.isEmpty ? "" : "port\(ports.count == 1 ? "" : "s") \(ports.joined(separator: ", "))"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private func itemBinding(_ index: Int) -> Binding<ChecklistItem> {
        Binding(
            get: { index < checklist.items.count ? checklist.items[index] : ChecklistItem(title: "") },
            set: { newValue in
                if index < checklist.items.count { checklist.items[index] = newValue }
            }
        )
    }

    private func move(_ index: Int, to target: Int) {
        guard target >= 0, target < checklist.items.count else { return }
        checklist.items.swapAt(index, target)
    }

    private func addItem() {
        let title = newItem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        checklist.items.append(ChecklistItem(title: title))
        newItem = ""
        newItemFocused = true
    }
}

struct ChecklistItemRow: View {
    @Binding var item: ChecklistItem
    let isFirst: Bool
    let isLast: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checklist")
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 3) {
                TextField("Item title", text: $item.title)
                    .textFieldStyle(.plain)
                TextField("Hint (optional): what to check or run here — $RHOST and $RPORT are filled in", text: $item.hint, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1...4)
            }
            Spacer()
            let counts = UsageStore.shared.checklistTotals(itemTitle: item.title)
            if counts.done + counts.skipped > 0 {
                Text("\(counts.done)× done\(counts.skipped > 0 ? " · \(counts.skipped)× n/a" : "")")
                    .font(.caption2)
                    .foregroundStyle(counts.skipped > counts.done ? Color.orange : Color.secondary)
                    .monospacedDigit()
                    .help("How often this item was marked done or not applicable on ports (all engagements). Items that are mostly n/a may not belong in the template.")
            }
            Button(action: moveUp) { Image(systemName: "chevron.up") }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(isFirst)
            Button(action: moveDown) { Image(systemName: "chevron.down") }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(isLast)
            Button(role: .destructive, action: delete) { Image(systemName: "xmark") }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Remove this item")
        }
        .padding(.vertical, 3)
    }
}
