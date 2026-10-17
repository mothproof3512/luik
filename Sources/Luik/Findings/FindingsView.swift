import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct FindingsView: View {
    @Environment(FindingsStore.self) private var store
    @Environment(EngagementStore.self) private var engagements
    @State private var showDeleteAll = false

    var body: some View {
        @Bindable var store = store
        SplitPane(storageKey: "findingsSplitFraction", defaultFraction: 0.38, minFraction: 0.25, maxFraction: 0.7) {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Button {
                        store.newFinding()
                    } label: {
                        Label("Finding", systemImage: "plus")
                    }
                    .help("New empty finding (⌘K → \"New finding\" works too)")
                    Spacer()
                    Menu {
                        Button("Export report as Markdown…") { exportReport(html: false) }
                        Button("Export report as HTML (opens in Word)…") { exportReport(html: true) }
                        Button("Copy report as Markdown") { store.copy(store.markdownReport()) }
                        Divider()
                        Button("Show data folder in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([engagements.fileURL("findings.json")])
                        }
                        Divider()
                        Button("Delete all findings…", role: .destructive) { showDeleteAll = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .frame(width: 44)
                }
                .padding(.horizontal, 10)
                .padding(.top, 8)

                HStack(spacing: 8) {
                    TextField("Search findings…", text: $store.search)
                        .textFieldStyle(.roundedBorder)
                    Picker("", selection: $store.severityFilter) {
                        Text("Any severity").tag(Severity?.none)
                        ForEach(Severity.allCases, id: \.self) { severity in
                            Text(severity.label).tag(Severity?.some(severity))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 120)
                    Picker("", selection: $store.statusFilter) {
                        Text("Any status").tag(FindingStatus?.none)
                        ForEach(FindingStatus.allCases, id: \.self) { status in
                            Text(status.label).tag(FindingStatus?.some(status))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

                SeveritySummary(counts: store.counts)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)

                Divider()

                if store.findings.isEmpty {
                    VStack(spacing: 10) {
                        Spacer()
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No findings yet for \(engagements.current.displayName).")
                            .font(.headline)
                        Text("Add one with the + button, from a target node (Finding button), from a knowledge-base record (Create finding), or import Nessus/nuclei output with \"also create findings\".")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity)
                } else {
                    List(store.filtered, selection: $store.selectedID) { finding in
                        FindingRow(finding: finding)
                            .tag(finding.id)
                            .contextMenu {
                                Button("Duplicate") { store.duplicate(finding.id) }
                                Button("Copy as Markdown") { store.copy(store.markdown(for: finding)) }
                                Divider()
                                Button("Delete", role: .destructive) { store.delete(finding.id) }
                            }
                    }
                    .listStyle(.inset)
                    .scrollContentBackground(.hidden)
                }
            }
        } trailing: {
            if let id = store.selectedID, store.findings.contains(where: { $0.id == id }) {
                FindingDetailView(finding: store.binding(for: id))
                    .id(id)
            } else {
                VStack {
                    Spacer()
                    Text("Select a finding")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .confirmationDialog("Delete all findings of this engagement?", isPresented: $showDeleteAll) {
            Button("Delete everything", role: .destructive) { store.deleteAll() }
        } message: {
            Text("Export the report first if you still need them.")
        }
    }

    private func exportReport(html: Bool) {
        let panel = NSSavePanel()
        let slug = engagements.current.slug
        panel.nameFieldStringValue = html ? "findings-\(slug).html" : "findings-\(slug).md"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let text = html ? store.htmlReport() : store.markdownReport()
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            ActivityLog.shared.record(.action, "Exported findings report to \(url.path)", source: "Findings")
        } catch {
            NSLog("Luik: export failed: %@", String(describing: error))
        }
    }
}

/// Counts per severity, as small coloured chips.
struct SeveritySummary: View {
    let counts: [Severity: Int]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Severity.allCases, id: \.self) { severity in
                let count = counts[severity] ?? 0
                HStack(spacing: 4) {
                    Circle()
                        .fill(severity.color)
                        .frame(width: 8, height: 8)
                    Text("\(count)")
                        .monospacedDigit()
                    Text(severity.label)
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                .opacity(count == 0 ? 0.45 : 1)
            }
            Spacer()
        }
    }
}

struct SeverityPill: View {
    let severity: Severity
    var score: Double? = nil

    var body: some View {
        Text(score.map { "\(severity.label) \(CVSS31.format($0))" } ?? severity.label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(severity.color.opacity(0.25), in: Capsule())
            .foregroundStyle(severity.color)
    }
}

struct FindingRow: View {
    let finding: Finding

    var body: some View {
        HStack(spacing: 8) {
            SeverityPill(severity: finding.severity)
                .frame(width: 64, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(finding.title.isEmpty ? "Untitled finding" : finding.title)
                    .lineLimit(1)
                    .strikethrough(finding.status == .falsePositive || finding.status == .resolved)
                HStack(spacing: 6) {
                    if let score = finding.cvssScore {
                        Text("CVSS \(CVSS31.format(score))")
                    }
                    Text(finding.affected.isEmpty ? "no affected hosts yet" : (finding.affected.count == 1 ? finding.affected[0] : "\(finding.affected.count) affected"))
                        .lineLimit(1)
                    if !finding.source.isEmpty {
                        Text(finding.source)
                            .lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: finding.status.symbol)
                .foregroundStyle(.secondary)
                .help(finding.status.label)
        }
        .padding(.vertical, 2)
    }
}

/// The editor on the right: title, severity/status, CVSS calculator, affected hosts and the report sections.
struct FindingDetailView: View {
    @Binding var finding: Finding
    @Environment(FindingsStore.self) private var store
    @Environment(TargetStore.self) private var targets
    @State private var affectedText = ""
    @State private var showCVSS = false
    @State private var copied = false
    @State private var savedToKB = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                TextField("Title", text: $finding.title)
                    .textFieldStyle(.plain)
                    .font(.title2.weight(.semibold))
                Button {
                    store.copy(store.markdown(for: finding))
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                } label: {
                    Label(copied ? "Copied" : "Markdown", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .help("Copy this finding as Markdown")
                Button {
                    let id = KnowledgeBaseStore.shared.save(finding)
                    if finding.source.isEmpty || !finding.source.hasPrefix("KB MY-") {
                        finding.source = "KB \(id)"
                    }
                    savedToKB = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { savedToKB = false }
                } label: {
                    Image(systemName: savedToKB ? "checkmark" : "books.vertical")
                }
                .disabled(finding.title.trimmingCharacters(in: .whitespaces).isEmpty)
                .help(finding.source.hasPrefix("KB MY-")
                      ? "Update record \(finding.source.dropFirst(3)) in your own knowledge base with this finding's text"
                      : "Save this finding (title, severity, CVSS, description, impact, recommendation, references — not the evidence or affected hosts) as a record of your own in the Knowledge base, so it is there for the next engagement")
                Button {
                    AppDelegate.shared?.captureEvidence(hideLuik: UserDefaults.standard.bool(forKey: SettingsKey.hideWhileCapturing)) { url in
                        var evidence = finding.evidence
                        if !evidence.isEmpty && !evidence.hasSuffix("\n") { evidence += "\n" }
                        evidence += "![evidence](\(url.path))\n"
                        finding.evidence = evidence
                    }
                } label: {
                    Image(systemName: "camera")
                }
                .help("Capture an evidence screenshot and link it under Evidence (⌘⇧E)")
                Button(role: .destructive) {
                    store.delete(finding.id)
                } label: {
                    Image(systemName: "trash")
                }
                .help("Delete this finding")
            }
            .padding(12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Picker("Severity", selection: $finding.severity) {
                            ForEach(Severity.allCases, id: \.self) { severity in
                                Text(severity.label).tag(severity)
                            }
                        }
                        .frame(width: 170)
                        Picker("Status", selection: $finding.status) {
                            ForEach(FindingStatus.allCases, id: \.self) { status in
                                Text(status.label).tag(status)
                            }
                        }
                        .frame(width: 190)
                        Spacer()
                        if let result = CVSS31.score(vector: finding.cvssVector) {
                            SeverityPill(severity: result.severity, score: result.effective)
                                .help(finding.cvssVector)
                        }
                    }
                    HStack(spacing: 8) {
                        Text("Source")
                            .foregroundStyle(.secondary)
                        TextField("Nessus plugin, nuclei template, KB id, manual…", text: $finding.source)
                            .textFieldStyle(.roundedBorder)
                    }

                    DisclosureGroup(isExpanded: $showCVSS) {
                        CVSSEditor(vector: $finding.cvssVector) { result in
                            if let result { finding.severity = result.severity }
                        }
                        .padding(.top, 6)
                    } label: {
                        HStack {
                            Text("CVSS 3.1")
                                .font(.subheadline.weight(.semibold))
                            if let score = finding.cvssScore {
                                Text("\(CVSS31.format(score)) · \(finding.cvssVector)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            } else {
                                Text("not set")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Affected hosts / services (one per line)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            if let node = targets.selectedNode, let label = FindingsStore.affectedLabel(for: node, in: targets) {
                                Button {
                                    if !finding.affected.contains(label) {
                                        finding.affected.append(label)
                                        affectedText = finding.affectedText
                                    }
                                } label: {
                                    Label("Add \(label)", systemImage: "plus")
                                }
                                .controlSize(.small)
                                .help("Add the selected Targets node")
                            }
                        }
                        TextEditor(text: $affectedText)
                            .font(.system(.body, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .padding(4)
                            .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
                            .frame(minHeight: 56, maxHeight: 120)
                    }

                    section("Description", text: $finding.description, prompt: "What is wrong and where.")
                    section("Impact", text: $finding.impact, prompt: "What an attacker can do with it.")
                    section("Evidence", text: $finding.evidence, prompt: "Commands, output, request/response, screenshots (Markdown links).")
                    HStack(alignment: .top, spacing: 8) {
                        EvidenceImageStrip(evidence: $finding.evidence)
                        Spacer(minLength: 0)
                        Button {
                            addImages()
                        } label: {
                            Label("Add image…", systemImage: "photo.badge.plus")
                        }
                        .controlSize(.small)
                        .help("Link an existing screenshot or image under Evidence; click a thumbnail to annotate, blur or redact it")
                    }
                    section("Recommendation", text: $finding.recommendation, prompt: "How to fix it.")
                    section("References", text: $finding.references, prompt: "CVE, advisories, documentation (one per line).")
                }
                .padding(12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            affectedText = finding.affectedText
            showCVSS = !finding.cvssVector.isEmpty
        }
        .onChange(of: affectedText) { _, text in
            let entries = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if entries != finding.affected { finding.affected = entries }
        }
    }

    private func addImages() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.png, .jpeg, .gif, .tiff, .heic, .webP]
        panel.message = "Choose screenshots to link under Evidence"
        guard panel.runModal() == .OK else { return }
        var evidence = finding.evidence
        for url in panel.urls {
            if evidence.contains(url.path) { continue }
            if !evidence.isEmpty && !evidence.hasSuffix("\n") { evidence += "\n" }
            evidence += "![evidence](\(url.path))\n"
        }
        finding.evidence = evidence
    }

    private func section(_ title: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ZStack(alignment: .topLeading) {
                if text.wrappedValue.isEmpty {
                    Text(prompt)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
                TextEditor(text: text)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .frame(minHeight: title == "Evidence" ? 120 : 72)
            }
            .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
        }
    }
}

/// CVSS 3.1 base (+ temporal) metrics as pickers, kept in sync with the vector string.
struct CVSSEditor: View {
    @Binding var vector: String
    var onChange: ((CVSS31.Result?) -> Void)? = nil

    @State private var values: [String: String] = CVSS31.defaultValues
    @State private var text = ""
    @State private var showTemporal = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit(applyText)
                Button("Apply", action: applyText)
                    .disabled(CVSS31.parse(text) == nil)
                    .help("Paste a vector from an advisory or NVD and apply it")
                Button("Clear") {
                    values = CVSS31.defaultValues
                    text = ""
                    vector = ""
                    onChange?(nil)
                }
            }
            if !text.isEmpty, CVSS31.parse(text) == nil {
                Label("Not a valid CVSS 3.x vector (all eight base metrics are needed).", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            ForEach(CVSS31.base) { metric in
                metricRow(metric)
            }
            DisclosureGroup("Temporal metrics", isExpanded: $showTemporal) {
                ForEach(CVSS31.temporal) { metric in
                    metricRow(metric)
                }
            }
            .font(.caption)
            if let result = CVSS31.score(values: values), !vector.isEmpty {
                HStack(spacing: 10) {
                    SeverityPill(severity: result.severity, score: result.effective)
                    Text("base \(CVSS31.format(result.base))" + (result.temporal.map { " · temporal \(CVSS31.format($0))" } ?? "")
                         + " · impact \(String(format: "%.1f", result.impact)) · exploitability \(String(format: "%.1f", result.exploitability))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Choose the metrics (or paste a vector) to get a score; the finding's severity follows the score.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear(perform: load)
        .onChange(of: vector) { _, newValue in
            if newValue != text { load() }
        }
    }

    private func metricRow(_ metric: CVSS31.Metric) -> some View {
        HStack(spacing: 8) {
            Text(metric.name)
                .font(.caption)
                .frame(width: 140, alignment: .leading)
            Picker("", selection: binding(for: metric.key)) {
                ForEach(metric.options) { option in
                    Text(option.label).tag(option.value)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private func binding(for key: String) -> Binding<String> {
        Binding(
            get: { values[key] ?? CVSS31.defaultValues[key] ?? "" },
            set: { newValue in
                values[key] = newValue
                commit()
            }
        )
    }

    private func load() {
        if let parsed = CVSS31.parse(vector) {
            values = CVSS31.defaultValues.merging(parsed) { _, new in new }
            text = vector
            showTemporal = CVSS31.temporal.contains { (parsed[$0.key] ?? "X") != "X" }
        } else {
            values = CVSS31.defaultValues
            text = vector
        }
    }

    private func applyText() {
        guard let parsed = CVSS31.parse(text) else { return }
        values = CVSS31.defaultValues.merging(parsed) { _, new in new }
        commit()
    }

    private func commit() {
        let built = CVSS31.vector(from: values)
        text = built
        vector = built
        onChange?(CVSS31.score(values: values))
    }
}
