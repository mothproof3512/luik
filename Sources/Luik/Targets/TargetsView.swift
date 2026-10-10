import AppKit
import SwiftUI

struct TargetsView: View {
    @Environment(TargetStore.self) private var store
    @State private var showImport = false
    @State private var showNewHost = false
    @State private var showDeleteAll = false

    var body: some View {
        @Bindable var store = store
        // Fixed-fraction split (see SplitPane): HSplitView sized the detail pane from the ideal
        // width of its content, which broke the layout once the suggestions panel appeared.
        SplitPane(storageKey: "targetsSplitFraction", defaultFraction: 0.42, minFraction: 0.25, maxFraction: 0.75) {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Button {
                        showImport = true
                    } label: {
                        Label("Import scan", systemImage: "square.and.arrow.down")
                    }
                    Button {
                        showNewHost = true
                    } label: {
                        Label("Host", systemImage: "plus")
                    }
                    .popover(isPresented: $showNewHost) {
                        NewHostPopover { address in
                            _ = store.addHost(address: address)
                        }
                    }
                    Spacer()
                    Menu {
                        Button("Edit checklists…") {
                            ChecklistStore.shared.showEditor = true
                        }
                        Button("Apply checklists to all targets") {
                            store.applyChecklistsEverywhere()
                        }
                        Button("Export checklists…") {
                            ChecklistTransfer.exportAll(as: .json)
                        }
                        Button("Import checklists…") {
                            ChecklistTransfer.importWithPrompt()
                        }
                        Divider()
                        Button("Export as Markdown…") {
                            exportMarkdown()
                        }
                        Button("Show data folder in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([store.fileURL])
                        }
                        Divider()
                        Button("Delete all targets…", role: .destructive) {
                            showDeleteAll = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .frame(width: 44)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

                if store.hosts.isEmpty {
                    VStack(spacing: 10) {
                        Spacer()
                        Image(systemName: "network")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No targets yet.\nImport nmap, Nessus, nuclei or masscan output, or add a host by hand.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                } else {
                    List(store.hosts, children: \.outlineChildren, selection: $store.selectedID) { node in
                        NodeRow(node: node)
                    }
                    .listStyle(.sidebar)
                    .scrollContentBackground(.hidden)
                }
            }
        } trailing: {
            if let node = store.selectedNode {
                NodeDetailView(node: node)
                    .id(node.id)
            } else {
                VStack {
                    Spacer()
                    Text("Select a node to take notes")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .sheet(isPresented: $showImport) {
            ImportSheet()
        }
        .confirmationDialog("Delete all targets?", isPresented: $showDeleteAll) {
            Button("Delete everything", role: .destructive) {
                store.deleteAll()
            }
        } message: {
            Text("This removes all hosts, ports and their notes. Export first if you want to keep them.")
        }
    }

    private func exportMarkdown() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "targets.md"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.markdown().write(to: url, atomically: true, encoding: .utf8)
        } catch {
            NSLog("Luik: export failed: %@", String(describing: error))
        }
    }
}

struct NewHostPopover: View {
    let onAdd: (String) -> Void
    @State private var address = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add host")
                .font(.headline)
            TextField("IP address or hostname", text: $address)
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
                .onSubmit(add)
            HStack {
                Spacer()
                Button("Add", action: add)
                    .keyboardShortcut(.defaultAction)
                    .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(12)
    }

    private func add() {
        let value = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        onAdd(value)
        address = ""
        dismiss()
    }
}

/// One row in the tree.
struct NodeRow: View {
    @Bindable var node: TargetNode
    @Environment(TargetStore.self) private var store
    @Environment(EngagementStore.self) private var engagements

    var body: some View {
        let scope: ScopeStatus? = node.kind == .host && engagements.hasScope ? engagements.scopeStatus(of: node.address) : nil
        HStack(spacing: 6) {
            Button {
                node.status = node.status.next
                store.scheduleSave()
            } label: {
                Image(systemName: node.status.symbol)
                    .foregroundStyle(node.status.color)
            }
            .buttonStyle(.plain)
            .help("Status: \(node.status.label) (click to cycle)")

            Image(systemName: node.kind.symbol)
                .foregroundStyle(.secondary)
                .frame(width: 16)

            Text(node.title)
                .fontWeight(node.kind == .host ? .semibold : .regular)
                .lineLimit(1)

            if !node.subtitle.isEmpty {
                Text(node.subtitle)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let scope, scope.isProblem {
                Image(systemName: scope.symbol)
                    .foregroundStyle(.orange)
                    .help("\(scope.label) — check the engagement scope before touching this host")
            }

            Spacer()

            if node.kind == .host || node.kind == .port {
                Text(node.progressText)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .contextMenu {
            Button("Add sub-node") {
                _ = store.addChild(to: node)
            }
            if node.kind == .host || node.kind == .port {
                Button("Add missing checklist items") {
                    store.applyTemplate(to: node)
                }
            }
            Divider()
            ForEach(NodeStatus.allCases, id: \.self) { status in
                Button(status.label) {
                    node.status = status
                    store.scheduleSave()
                }
            }
            Divider()
            Button("Delete", role: .destructive) {
                store.delete(node)
            }
        }
    }
}

/// Detail pane on the right: title, status and notes of the selected node.
struct NodeDetailView: View {
    @Bindable var node: TargetNode
    @Environment(TargetStore.self) private var store
    @Environment(UIState.self) private var ui
    @Environment(FindingsStore.self) private var findings
    @Environment(EngagementStore.self) private var engagements
    @State private var showPortSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: node.kind.symbol)
                    .foregroundStyle(.secondary)
                TextField("Title", text: $node.title)
                    .textFieldStyle(.plain)
                    .font(.title2.weight(.semibold))
            }
            TextField(node.kind == .port ? "Service / version" : (node.kind == .host ? "Hostname / description" : "Description"),
                      text: $node.subtitle)
                .textFieldStyle(.plain)
                .foregroundStyle(.secondary)

            Picker("Status", selection: $node.status) {
                ForEach(NodeStatus.allCases, id: \.self) { status in
                    Text(status.label).tag(status)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if node.kind == .host, engagements.hasScope {
                let scope = engagements.scopeStatus(of: node.address)
                Label(scope.label, systemImage: scope.symbol)
                    .font(.caption)
                    .foregroundStyle(scope.isProblem ? Color.orange : Color.secondary)
            }

            HStack(spacing: 8) {
                Text("Notes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if node.kind == .host {
                    Button {
                        showPortSheet = true
                    } label: {
                        Label("Port", systemImage: "plus")
                    }
                    .popover(isPresented: $showPortSheet) {
                        NewPortPopover { number, proto in
                            _ = store.addPort(to: node, number: number, proto: proto)
                        }
                    }
                }
                Button {
                    _ = store.addChild(to: node)
                } label: {
                    Label("Sub-node", systemImage: "plus")
                }
                if node.kind == .host || node.kind == .port {
                    Button {
                        store.applyTemplate(to: node)
                    } label: {
                        Label("Checklist", systemImage: "list.bullet.rectangle")
                    }
                    .help("Add the missing work-item nodes from the checklist for this host/service")
                }
                Button {
                    findings.create(from: node, in: store)
                    ui.module = .findings
                } label: {
                    Label("Finding", systemImage: "exclamationmark.triangle")
                }
                .help("Create a finding from this node: the notes become the evidence, the host/port the affected service")
                Button {
                    AppDelegate.shared?.captureEvidenceHidingLuik()
                } label: {
                    Image(systemName: "camera")
                }
                .help("Capture an evidence screenshot and link it in these notes (⌘⇧E)")
                Button(role: .destructive) {
                    store.delete(node)
                } label: {
                    Image(systemName: "trash")
                }
                .help("Delete this node (and everything under it)")
            }

            if node.kind == .host || node.kind == .port || store.host(of: node) != nil {
                OneLinersPanel(node: node)
                    .padding(8)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            }

            if node.kind == .port {
                SuggestionsPanel(node: node)
                    .padding(8)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            }

            TextEditor(text: $node.notes)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))

            if node.kind == .host || node.kind == .port {
                let p = node.progress
                if p.total > 0 {
                    ProgressView(value: Double(p.done), total: Double(p.total)) {
                        Text("Progress: \(p.done) of \(p.total) work items handled")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: node.title) { _, _ in store.scheduleSave() }
        .onChange(of: node.subtitle) { _, _ in store.scheduleSave() }
        .onChange(of: node.notes) { _, _ in store.scheduleSave() }
        .onChange(of: node.status) { _, _ in store.scheduleSave() }
    }
}

struct NewPortPopover: View {
    let onAdd: (Int, String) -> Void
    @State private var number = ""
    @State private var proto = "tcp"
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add port")
                .font(.headline)
            HStack {
                TextField("Port number", text: $number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                    .onSubmit(add)
                Picker("", selection: $proto) {
                    Text("tcp").tag("tcp")
                    Text("udp").tag("udp")
                }
                .labelsHidden()
                .frame(width: 80)
            }
            HStack {
                Spacer()
                Button("Add", action: add)
                    .keyboardShortcut(.defaultAction)
                    .disabled(Int(number.trimmingCharacters(in: .whitespaces)) == nil)
            }
        }
        .padding(12)
    }

    private func add() {
        guard let value = Int(number.trimmingCharacters(in: .whitespaces)), value > 0, value < 65536 else { return }
        onAdd(value, proto)
        number = ""
        dismiss()
    }
}

/// Sheet for pasting scanner output or choosing files: nmap, Nessus, nuclei, masscan.
struct ImportSheet: View {
    @Environment(TargetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var includeNonOpen = false
    @State private var addNodes = true
    @State private var nodeSeverity: Severity = .low
    @State private var createFindings = true
    @State private var findingSeverity: Severity = .medium
    @State private var resultMessage: String?

    private var format: ScanFormat? {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : ScanImport.detect(text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Import scan output")
                    .font(.headline)
                Spacer()
                if let format {
                    Label("Detected: \(format.label)", systemImage: "doc.text.magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text("Paste the output or choose files: nmap (normal, -oG, -oX), Nessus (.nessus), nuclei (-json / -jsonl / -je) or masscan (-oL, -oJ, -oG). One host or many at once; existing hosts and ports are updated rather than duplicated, and work-item nodes are created for every host and open port.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(4)
                .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
                .frame(minHeight: 220)

            Toggle("Include non-open ports too (filtered, open|filtered)", isOn: $includeNonOpen)
            if format?.hasFindings ?? false {
                HStack(spacing: 8) {
                    Toggle("Add a node per scanner finding under the port, from severity", isOn: $addNodes)
                    severityPicker($nodeSeverity)
                        .disabled(!addNodes)
                }
                HStack(spacing: 8) {
                    Toggle("Also create entries in Findings (one per plugin/template), from severity", isOn: $createFindings)
                    severityPicker($findingSeverity)
                        .disabled(!createFindings)
                }
            }

            HStack {
                Button("Choose file…") {
                    chooseFiles()
                }
                Spacer()
                if let resultMessage {
                    Text(resultMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Import") {
                    let result = runImport(text)
                    if result.newHosts + result.updatedHosts > 0 {
                        text = ""
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 720, height: 560)
    }

    @discardableResult
    private func runImport(_ content: String) -> ImportResult {
        var options = ScanImportOptions(includeNonOpen: includeNonOpen)
        options.nodeSeverity = addNodes ? nodeSeverity : nil
        options.findingSeverity = createFindings ? findingSeverity : nil
        let result = store.importScan(content, options: options)
        resultMessage = result.summary
        return result
    }

    private func severityPicker(_ selection: Binding<Severity>) -> some View {
        Picker("", selection: selection) {
            ForEach(Severity.allCases, id: \.self) { severity in
                Text(severity.label).tag(severity)
            }
        }
        .labelsHidden()
        .frame(width: 110)
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Choose scanner output (.xml, .gnmap, .nmap, .txt, .nessus, .json, .jsonl, .list)"
        guard panel.runModal() == .OK else { return }
        let contents = panel.urls.compactMap { url -> String? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        }
        guard !contents.isEmpty else { return }
        // Big files (Nessus exports easily run to tens of MB) are imported straight away instead
        // of being loaded into the text editor; small ones can still be reviewed first.
        let large = contents.filter { $0.utf8.count > 512 * 1024 }
        let small = contents.filter { $0.utf8.count <= 512 * 1024 }
        var messages: [String] = []
        for content in large {
            let result = runImport(content)
            messages.append("\(result.format.label): \(result.summary)")
        }
        if !messages.isEmpty {
            resultMessage = messages.joined(separator: "\n")
        }
        guard !small.isEmpty else { return }
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            text += "\n"
        }
        text += small.joined(separator: "\n")
    }
}
