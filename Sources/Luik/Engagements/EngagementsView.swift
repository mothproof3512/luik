import AppKit
import SwiftUI

/// The engagement picker in the top bar: switch, create, manage.
struct EngagementMenu: View {
    @Environment(EngagementStore.self) private var store
    @State private var showNew = false

    var body: some View {
        HStack(spacing: 2) {
            Menu {
                ForEach(store.engagements) { engagement in
                    Button {
                        store.switchTo(engagement.id)
                    } label: {
                        if engagement.id == store.currentID {
                            Label(engagement.displayName, systemImage: "checkmark")
                        } else {
                            Text(engagement.displayName)
                        }
                    }
                }
                Divider()
                Button("New engagement…") { showNew = true }
                Button("Manage engagements…") { store.showManager = true }
            } label: {
                Label(shortName(store.current.displayName), systemImage: "briefcase")
            }
            .fixedSize()
            .help("Engagement “\(store.current.displayName)” — targets, notes, findings, log and evidence are kept per engagement")
        }
        .popover(isPresented: $showNew, arrowEdge: .bottom) {
            NewEngagementPopover()
        }
    }

    private func shortName(_ name: String) -> String {
        name.count > 28 ? String(name.prefix(26)) + "…" : name
    }
}

struct NewEngagementPopover: View {
    @Environment(EngagementStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("New engagement")
                .font(.headline)
            TextField("Client / project name", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
                .onSubmit(create)
            Text("Starts with empty targets, notes, findings and log. One-liners, the knowledge base and Exploit-DB are shared.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 260)
            HStack {
                Spacer()
                Button("Create and switch", action: create)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(12)
    }

    private func create() {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        store.create(name: value)
        name = ""
        dismiss()
    }
}

/// Sheet: list of engagements on the left, details and scope on the right.
struct EngagementsManager: View {
    @Environment(EngagementStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: UUID?
    @State private var showDelete = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Engagements")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)
            Divider()
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    List(store.engagements, selection: $selectedID) { engagement in
                        HStack(spacing: 6) {
                            Image(systemName: engagement.id == store.currentID ? "briefcase.fill" : "briefcase")
                                .foregroundStyle(engagement.id == store.currentID ? Color.accentColor : .secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(engagement.displayName)
                                    .lineLimit(1)
                                if !engagement.client.isEmpty {
                                    Text(engagement.client)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .tag(engagement.id)
                    }
                    .listStyle(.inset)
                    .scrollContentBackground(.hidden)
                    Divider()
                    HStack(spacing: 8) {
                        Button {
                            let created = store.create(name: "New engagement", switchToIt: false)
                            selectedID = created.id
                        } label: {
                            Image(systemName: "plus")
                        }
                        .help("Add an engagement")
                        Button {
                            showDelete = true
                        } label: {
                            Image(systemName: "minus")
                        }
                        .disabled(selectedID == nil || store.engagements.count < 2)
                        .help("Delete the selected engagement (its files go to the Trash)")
                        Spacer()
                    }
                    .padding(8)
                }
                .frame(width: 230)
                Divider()
                if let id = selectedID, store.engagements.contains(where: { $0.id == id }) {
                    EngagementEditor(engagement: store.binding(for: id))
                        .id(id)
                } else {
                    VStack {
                        Spacer()
                        Text("Select an engagement")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(width: 820, height: 560)
        .onAppear { selectedID = store.currentID }
        .confirmationDialog("Delete this engagement?", isPresented: $showDelete) {
            Button("Delete", role: .destructive) {
                if let id = selectedID {
                    store.delete(id)
                    selectedID = store.currentID
                }
            }
        } message: {
            Text("Its targets, notes, findings and log are moved to the Trash with the engagement folder. Evidence screenshots stay where they are.")
        }
    }
}

struct EngagementEditor: View {
    @Binding var engagement: Engagement
    @Environment(EngagementStore.self) private var store
    @State private var scopeText = ""
    @State private var exclusionsText = ""
    @State private var checkAddress = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    TextField("Name", text: $engagement.name)
                        .textFieldStyle(.plain)
                        .font(.title2.weight(.semibold))
                    if engagement.id != store.currentID {
                        Button("Switch to this engagement") { store.switchTo(engagement.id) }
                    } else {
                        Label("Current", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                }
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                    GridRow {
                        Text("Client").foregroundStyle(.secondary)
                        TextField("Company or team", text: $engagement.client).textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text("Reference").foregroundStyle(.secondary)
                        TextField("Project code, ticket, quote…", text: $engagement.reference).textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text("Period").foregroundStyle(.secondary)
                        TextField("e.g. 13–17 Oct 2026", text: $engagement.period).textFieldStyle(.roundedBorder)
                    }
                }

                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Scope (one per line)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextEditor(text: $scopeText)
                            .font(.system(.body, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .padding(4)
                            .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
                            .frame(minHeight: 120)
                        scopeSummary(scopeText)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Exclusions (one per line)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextEditor(text: $exclusionsText)
                            .font(.system(.body, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .padding(4)
                            .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
                            .frame(minHeight: 120)
                        scopeSummary(exclusionsText)
                    }
                }
                Text("Accepted: 10.0.0.0/24 · 10.0.0.5 · 10.0.0.10-10.0.0.20 · 10.0.0.10-20 · example.com (incl. subdomains) · *.example.com · 2001:db8::/32. Hosts outside the scope get a warning in Targets and in the import summary; exclusions win over scope.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Text("Check")
                        .foregroundStyle(.secondary)
                    TextField("IP or hostname", text: $checkAddress)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                    let status = ScopeMatcher.status(of: checkAddress, scope: lines(scopeText), exclusions: lines(exclusionsText))
                    if !checkAddress.trimmingCharacters(in: .whitespaces).isEmpty {
                        Label(status.label, systemImage: status.symbol)
                            .foregroundStyle(status.isProblem ? Color.orange : (status == .inScope ? Color.green : Color.secondary))
                    }
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Notes (rules of engagement, contacts, credentials location…)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextEditor(text: $engagement.notes)
                        .font(.system(.body, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(4)
                        .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
                        .frame(minHeight: 100)
                }

                HStack {
                    Button("Show engagement folder in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([EngagementStore.folder(for: engagement)])
                    }
                    Button("Show evidence folder") {
                        let folder = EvidenceCapture.rootFolder.appendingPathComponent(engagement.slug, isDirectory: true)
                        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(folder)
                    }
                    Spacer()
                }
                .font(.caption)
            }
            .padding(14)
        }
        .onAppear {
            scopeText = engagement.scope.joined(separator: "\n")
            exclusionsText = engagement.exclusions.joined(separator: "\n")
        }
        .onChange(of: scopeText) { _, text in
            let entries = lines(text)
            if entries != engagement.scope { engagement.scope = entries }
        }
        .onChange(of: exclusionsText) { _, text in
            let entries = lines(text)
            if entries != engagement.exclusions { engagement.exclusions = entries }
        }
    }

    private func lines(_ text: String) -> [String] {
        text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    @ViewBuilder
    private func scopeSummary(_ text: String) -> some View {
        let entries = lines(text)
        let invalid = entries.filter { ScopeMatcher.parse($0) == nil }
        if !invalid.isEmpty {
            Label("Not understood: " + invalid.prefix(3).joined(separator: ", ") + (invalid.count > 3 ? " …" : ""), systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
        } else if let last = entries.last, let description = ScopeMatcher.describe(last) {
            Text("\(entries.count) entr\(entries.count == 1 ? "y" : "ies") · last: \(description)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
