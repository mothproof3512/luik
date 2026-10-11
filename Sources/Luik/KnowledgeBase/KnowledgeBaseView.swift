import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct KnowledgeBaseView: View {
    @Environment(KnowledgeBaseStore.self) private var store
    @Environment(TargetStore.self) private var targets
    @Environment(UIState.self) private var ui
    @State private var showRemoveConfirmation = false
    @State private var showGuide = false

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            toolbar
            Divider()
            if store.knowledgeBase == nil {
                emptyState
            } else {
                let hits = store.hits
                // Divider at two thirds by default (list left, finding right); draggable and remembered.
                SplitPane(storageKey: "kbSplitFraction", defaultFraction: 2.0 / 3.0, minFraction: 0.2, maxFraction: 0.85) {
                    resultList(hits)
                } trailing: {
                    if let hit = store.hit(for: store.selectedID) {
                        RecordDetailView(hit: hit)
                            .id(hit.id)
                    } else {
                        VStack {
                            Spacer()
                            Text(hits.isEmpty ? "No matches." : "Select a finding to read it.")
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .confirmationDialog("Remove the imported knowledge base?", isPresented: $showRemoveConfirmation) {
            Button("Remove", role: .destructive) {
                store.remove()
            }
        } message: {
            Text("Only the imported copy inside Luik is removed; your original file is untouched.")
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        @Bindable var store = store
        return HStack(spacing: 8) {
            TextField("Search all columns… (e.g. a product, version, CVE, CWE or technique)", text: $store.search)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 220, maxWidth: 360)
            if !store.scopeValues.isEmpty {
                Picker("", selection: $store.scopeFilter) {
                    Text("All scopes").tag("")
                    ForEach(store.scopeValues, id: \.self) { value in
                        Text(value).tag(value)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 190)
            }
            if !store.severityValues.isEmpty {
                Picker("", selection: $store.severityFilter) {
                    Text("All severities").tag("")
                    ForEach(store.severityValues, id: \.self) { value in
                        Text(value).tag(value)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 150)
            }
            if !store.phaseValues.isEmpty {
                Picker("", selection: $store.phaseFilter) {
                    Text("All phases").tag("")
                    ForEach(store.phaseValues, id: \.self) { value in
                        Text(value).tag(value)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 190)
                .help("Kill chain phase")
            }
            Spacer()
            if let kb = store.knowledgeBase {
                Text("\(store.totalMatching) of \(kb.recordCount)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .help("\(kb.sourceName), imported \(kb.importedAt.formatted(date: .abbreviated, time: .shortened))")
            }
            Menu {
                if let kb = store.knowledgeBase {
                    Text("\(kb.sourceName)\(kb.version.map { " (version \($0))" } ?? "")")
                    Text("Imported \(kb.importedAt.formatted(date: .abbreviated, time: .shortened)) · \(kb.tables.count) sheet(s), \(kb.recordCount) rows")
                    if let source = kb.sourceURL {
                        Text("From \(source)")
                    }
                    Divider()
                }
                Button("Download knowledge base…") {
                    ui.showKnowledgeBaseDownload = true
                }
                Button("Save example template…") {
                    KnowledgeBaseTemplate.save()
                }
                Button("How to prepare a sheet…") {
                    showGuide = true
                }
                Divider()
                Button("Show data folder in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([Storage.url(for: "knowledgebase.json")])
                }
                if store.knowledgeBase != nil {
                    Divider()
                    Button("Remove knowledge base…", role: .destructive) {
                        showRemoveConfirmation = true
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .frame(width: 44)
            Button {
                showGuide.toggle()
            } label: {
                Image(systemName: "questionmark.circle")
            }
            .help("How to prepare a sheet, and the example template")
            .popover(isPresented: $showGuide, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Preparing your knowledge base")
                        .font(.headline)
                    KnowledgeBaseGuide(compact: true)
                }
                .padding(14)
                .frame(width: 440)
            }
            Button {
                ui.showKnowledgeBaseDownload = true
            } label: {
                Label("Download", systemImage: "icloud.and.arrow.down")
            }
            .help("Download a ready-made knowledge base from the Luik repository (English or Dutch), or from your own repository or link")
            Button {
                chooseFile()
            } label: {
                Label(store.knowledgeBase == nil ? "Import" : "Re-import", systemImage: "square.and.arrow.down")
            }
            .help("Import an Excel (.xlsx), CSV/TSV or JSON file; a re-import replaces the previous one")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "books.vertical")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No knowledge base yet.")
                .font(.headline)
            Text("Download the attack-vectors knowledge base that comes with Luik (English or Dutch, 349 rows), or import your own findings sheet (.xlsx, .csv or .json). Every sheet becomes searchable, across all columns.\nThe data stays on this Mac, in ~/Library/Application Support/Luik/.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let error = store.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .padding(.top, 4)
            }
            HStack(spacing: 10) {
                Button {
                    ui.showKnowledgeBaseDownload = true
                } label: {
                    Label("Download from GitHub…", systemImage: "icloud.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                Button {
                    chooseFile()
                } label: {
                    Label("Import file…", systemImage: "square.and.arrow.down")
                }
            }
            .padding(.top, 4)

            ScrollView {
                KnowledgeBaseGuide()
                    .padding(14)
                    .frame(maxWidth: 640, alignment: .leading)
                    .background(Color.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
            }
            .padding(.top, 12)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }

    private func resultList(_ hits: [KBHit]) -> some View {
        @Bindable var store = store
        let roles = store.roles
        let multipleTables = (store.knowledgeBase?.tables.count ?? 0) > 1
        return List(selection: $store.selectedID) {
            if let error = store.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            ForEach(hits) { hit in
                HitRow(hit: hit, roles: roles, showTable: multipleTables)
                    .tag(hit.id)
            }
            if hits.count >= 500 {
                Text("Showing the first 500 matches; refine the search to see more.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        var types: [UTType] = [.commaSeparatedText, .tabSeparatedText, .json, .plainText]
        if let xlsx = UTType(filenameExtension: "xlsx") { types.append(xlsx) }
        if let xlsm = UTType(filenameExtension: "xlsm") { types.append(xlsm) }
        panel.allowedContentTypes = types
        panel.message = "Choose a findings sheet (.xlsx, .csv, .tsv or .json)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.importFile(at: url)
    }
}

/// One search hit in the list: ID, title, scope and severity.
struct HitRow: View {
    let hit: KBHit
    let roles: KBColumnRoles
    let showTable: Bool
    @Environment(KnowledgeBaseStore.self) private var store

    var body: some View {
        let record = hit.record
        let id = roles.idColumn.map { record.value($0) } ?? ""
        let title = roles.titleColumn.map { record.value($0) } ?? ""
        let scope = roles.scopeColumn.map { record.value($0) } ?? ""
        let severity = roles.severityColumn.map { record.value($0) } ?? ""
        let phase = roles.phaseColumn.map { record.value($0) } ?? ""
        let subtitle = [scope, phase].filter { !$0.isEmpty }.joined(separator: " · ")

        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                if !id.isEmpty {
                    Text(store.highlighted(id))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                if showTable {
                    Text(hit.table.name)
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.white.opacity(0.1), in: Capsule())
                }
                Spacer()
                if !severity.isEmpty {
                    SeverityBadge(value: severity)
                }
            }
            Text(store.highlighted(title.isEmpty ? firstValue(record) : title))
                .font(.callout.weight(.medium))
                .lineLimit(2)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    private func firstValue(_ record: KBRecord) -> String {
        for column in hit.table.columns {
            let value = record.value(column)
            if !value.isEmpty { return value }
        }
        return "(empty)"
    }
}

struct SeverityBadge: View {
    let value: String

    private var color: Color {
        switch value.lowercased() {
        case "critical", "kritiek": return .purple
        case "high", "hoog": return .red
        case "medium", "middel", "moderate": return .orange
        case "low", "laag": return .green
        case "info", "informational", "informatief": return .gray
        default:
            if let number = Double(value.replacingOccurrences(of: ",", with: ".")) {
                // CVSS-style score.
                if number >= 9 { return .purple }
                if number >= 7 { return .red }
                if number >= 4 { return .orange }
                return .green
            }
            return .blue
        }
    }

    var body: some View {
        Text(value)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.28), in: Capsule())
            .overlay(Capsule().strokeBorder(color.opacity(0.6), lineWidth: 1))
    }
}

/// The full record: every non-empty column, with search terms highlighted and URLs clickable.
struct RecordDetailView: View {
    let hit: KBHit
    @Environment(KnowledgeBaseStore.self) private var store
    @Environment(TargetStore.self) private var targets
    @Environment(FindingsStore.self) private var findings
    @Environment(UIState.self) private var ui
    @State private var copied = false
    @State private var appended = false

    var body: some View {
        let roles = store.roles
        let record = hit.record
        let id = roles.idColumn.map { record.value($0) } ?? ""
        let title = roles.titleColumn.map { record.value($0) } ?? ""
        let severity = roles.severityColumn.map { record.value($0) } ?? ""

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        if !id.isEmpty {
                            Text(store.highlighted(id))
                                .font(.system(.callout, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        if !severity.isEmpty {
                            SeverityBadge(value: severity)
                        }
                    }
                    if !title.isEmpty {
                        Text(store.highlighted(title))
                            .font(.title3.weight(.semibold))
                            .textSelection(.enabled)
                    }
                }
                Spacer()
                Button {
                    store.copyMarkdown(for: hit)
                    flash($copied)
                } label: {
                    Label(copied ? "Copied" : "Copy as Markdown", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                if let node = targets.selectedNode {
                    Button {
                        appendToTarget(node)
                        flash($appended)
                    } label: {
                        Label(appended ? "Added" : "Add to target", systemImage: appended ? "checkmark" : "arrow.turn.down.right")
                    }
                    .help("Append this finding to the notes of the selected Targets node (\(node.title))")
                }
                Button {
                    let affected = targets.selectedNode.flatMap { FindingsStore.affectedLabel(for: $0, in: targets) }.map { [$0] } ?? []
                    findings.create(fromKnowledgeBase: hit, roles: store.roles, affected: affected)
                    ui.module = .findings
                } label: {
                    Label("Create finding", systemImage: "exclamationmark.triangle")
                }
                .help("New entry in the Findings tab with the description, impact, recommendation and references from this record" + (targets.selectedNode != nil ? ", affecting the selected target" : ""))
            }
            .padding(12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(hit.table.columns, id: \.self) { column in
                        let value = record.value(column)
                        if !value.isEmpty && column != roles.idColumn && column != roles.titleColumn {
                            FieldView(label: column.replacingOccurrences(of: "_", with: " "), value: value)
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func appendToTarget(_ node: TargetNode) {
        let roles = store.roles
        let id = roles.idColumn.map { hit.record.value($0) } ?? ""
        var notes = node.notes
        if !notes.isEmpty && !notes.hasSuffix("\n") { notes += "\n" }
        if !notes.isEmpty { notes += "\n" }
        notes += store.markdown(for: hit)
        node.notes = notes
        targets.scheduleSave()
        let title = (roles.titleColumn.map { hit.record.value($0) } ?? "")
        ActivityLog.shared.record(.action, "Added finding \(id.isEmpty ? "" : id + " ")\(title) to target node \(node.title)", source: "Knowledge base")
    }

    private func flash(_ flag: Binding<Bool>) {
        flag.wrappedValue = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            flag.wrappedValue = false
        }
    }
}

/// One labelled field. Values that contain URLs are rendered with clickable links.
struct FieldView: View {
    let label: String
    let value: String
    @Environment(KnowledgeBaseStore.self) private var store
    @Environment(NotesStore.self) private var notes
    @Environment(UIState.self) private var ui

    /// A "PayloadsAllTheThings" / "InternalAllTheThings" column names a page; when that
    /// documentation is in the library, offer to open it.
    private var libraryDocument: LibraryDocument? {
        let key = label.lowercased().replacingOccurrences(of: " ", with: "")
        guard key.contains("allthethings") else { return nil }
        let library = LibraryStore.shared
        for part in value.components(separatedBy: CharacterSet(charactersIn: ";,|")) {
            if let document = library.document(topic: part) { return document }
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if let document = libraryDocument {
                Button {
                    notes.open(document)
                    ui.module = .notes
                } label: {
                    Label("Open “\(document.title)” in the library", systemImage: "books.vertical")
                        .font(.caption)
                }
                .buttonStyle(.link)
            }
            if value.contains("http://") || value.contains("https://") {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(FieldView.urlParts(value).enumerated()), id: \.offset) { _, part in
                        if let url = URL(string: part), let scheme = url.scheme, scheme.hasPrefix("http") {
                            Link(part, destination: url)
                                .font(.callout)
                        } else {
                            Text(store.highlighted(part))
                                .font(.callout)
                                .textSelection(.enabled)
                        }
                    }
                }
            } else {
                Text(store.highlighted(value))
                    .font(.callout)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Splits "a; https://x; b" into separate parts so each URL becomes one link.
    static func urlParts(_ value: String) -> [String] {
        value.components(separatedBy: CharacterSet(charactersIn: ";\n"))
            .flatMap { part -> [String] in
                let trimmed = part.trimmingCharacters(in: .whitespaces)
                if trimmed.contains("http"), trimmed.contains(" ") {
                    return trimmed.split(separator: " ").map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: ",")) }
                }
                return [trimmed]
            }
            .filter { !$0.isEmpty }
    }
}
