import AppKit
import Foundation
import SwiftUI

/// Everything of the current engagement into one folder (and a zip): the report material as
/// Markdown and HTML, a dossier per host, the plans, the log with outputs, the notes, the
/// diagrams as PNG and JSON, the evidence files and the raw JSON — so the engagement can leave
/// Luik complete, be archived or handed over.
enum CloseOut {
    struct Options {
        var findings = true
        var targets = true
        var hostDossiers = true
        var plans = true
        var log = true
        var logOutputs = true
        var notes = true
        var diagrams = true
        var evidence = true
        var rawData = true
        var zip = true
    }

    struct Result {
        var folder: URL
        var zip: URL?
        var files: Int
        var warnings: [String]
    }

    /// Writes the package into `destination/<engagement slug>-closeout-<date>/`.
    @MainActor
    static func export(to destination: URL, options: Options, accent: Color) -> Result {
        let fm = FileManager.default
        let engagement = EngagementStore.shared.current
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyy-MM-dd"
        let folder = destination.appendingPathComponent("\(engagement.slug)-closeout-\(stamp.string(from: Date()))", isDirectory: true)
        var files = 0
        var warnings: [String] = []

        func write(_ text: String, to relative: String) {
            let url = folder.appendingPathComponent(relative)
            do {
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try text.write(to: url, atomically: true, encoding: .utf8)
                files += 1
            } catch {
                warnings.append("\(relative): \(error.localizedDescription)")
            }
        }
        func writeData(_ data: Data, to relative: String) {
            let url = folder.appendingPathComponent(relative)
            do {
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
                files += 1
            } catch {
                warnings.append("\(relative): \(error.localizedDescription)")
            }
        }
        func copyItem(_ source: URL, to relative: String) {
            let url = folder.appendingPathComponent(relative)
            guard fm.fileExists(atPath: source.path) else { return }
            do {
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
                try fm.copyItem(at: source, to: url)
                files += 1
            } catch {
                warnings.append("\(relative): \(error.localizedDescription)")
            }
        }
        func safeName(_ text: String) -> String {
            let cleaned = text.map { $0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-" ? $0 : "-" }
            return String(cleaned).replacingOccurrences(of: "-+", with: "-", options: .regularExpression).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        }

        AppDelegate.shared?.flushAllStores()
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)

        // README
        let findings = FindingsStore.shared.findings
        let targets = TargetStore.shared
        var readme = "# \(engagement.displayName) — close-out\n\n"
        readme += "Exported from Luik \(AppInfo.version) on \(Date().formatted(date: .long, time: .shortened)).\n\n"
        if !engagement.client.isEmpty { readme += "- Client: \(engagement.client)\n" }
        if !engagement.reference.isEmpty { readme += "- Reference: \(engagement.reference)\n" }
        if !engagement.period.isEmpty { readme += "- Period: \(engagement.period)\n" }
        if !engagement.scope.isEmpty { readme += "- Scope: \(engagement.scope.joined(separator: ", "))\n" }
        if !engagement.exclusions.isEmpty { readme += "- Exclusions: \(engagement.exclusions.joined(separator: ", "))\n" }
        let open = findings.filter { $0.status != .falsePositive }
        readme += "\n## Contents\n\n"
        readme += "- `findings.md`, `findings.html` — \(open.count) finding\(open.count == 1 ? "" : "s") (\(Severity.allCases.map { severity in "\(open.filter { $0.severity == severity }.count) \(severity.label.lowercased())" }.joined(separator: ", ")))\n"
        readme += "- `targets.md` — \(targets.hosts.count) host\(targets.hosts.count == 1 ? "" : "s"); `hosts/` — one dossier per host\n"
        readme += "- `plans/` — the test plan(s) with status per item\n"
        readme += "- `activity-log.md` — every command and event\(options.logOutputs ? ", with the captured outputs" : "")\n"
        readme += "- `notes/` — the notes of the engagement\n"
        readme += "- `diagrams/` — network and application diagrams (PNG + Luik JSON)\n"
        readme += "- `evidence/` — screenshots and other evidence files\n"
        readme += "- `data/` — the raw JSON Luik keeps (import again via the data folder)\n"
        write(readme, to: "README.md")

        if options.findings {
            write(FindingsStore.shared.markdownReport(), to: "findings.md")
            write(FindingsStore.shared.htmlReport(), to: "findings.html")
            if !FindingsStore.shared.retestFindings.isEmpty { write(FindingsStore.shared.retestMarkdown(), to: "retest.md") }
        }
        if options.targets {
            write(targets.markdown(), to: "targets.md")
        }
        if options.hostDossiers {
            for host in targets.hosts {
                let name = safeName(host.address.isEmpty ? host.title : host.address)
                write(TargetContext.dossier(for: host), to: "hosts/\(name.isEmpty ? host.id.uuidString : name).md")
            }
        }
        if options.plans {
            for plan in PlanStore.shared.plans {
                write(PlanStore.shared.markdown(for: plan), to: "plans/\(safeName(plan.name)).md")
            }
        }
        if options.log {
            write(ActivityLog.shared.markdown(filteredOnly: false, includeOutput: options.logOutputs), to: "activity-log.md")
        }
        if options.notes {
            for note in NotesStore.shared.notes {
                write(note.body, to: "notes/\(safeName(note.title.isEmpty ? "note" : note.title)).md")
            }
        }
        if options.diagrams {
            for diagram in DiagramStore.shared.diagrams {
                let name = safeName(diagram.name)
                if let png = DiagramTransfer.png(diagram, palette: .light(accent: accent)) { writeData(png, to: "diagrams/\(name).png") }
                if let json = try? JSONEncoder.iso.encode(diagram) { writeData(json, to: "diagrams/\(name).luik.json") }
            }
        }
        if options.evidence {
            let evidenceFolder = EvidenceCapture.folder
            if let items = try? fm.contentsOfDirectory(at: evidenceFolder, includingPropertiesForKeys: nil) {
                for item in items { copyItem(item, to: "evidence/\(item.lastPathComponent)") }
            }
            // Images linked from findings or nodes that live elsewhere.
            var linked = Set<String>()
            for finding in findings { EvidenceImages.paths(in: finding.evidence).forEach { linked.insert($0) } }
            func collect(_ node: TargetNode) {
                EvidenceImages.paths(in: node.notes).forEach { linked.insert($0) }
                node.children.forEach(collect)
            }
            targets.hosts.forEach(collect)
            for path in linked where !path.hasPrefix(evidenceFolder.path) {
                copyItem(URL(fileURLWithPath: path), to: "evidence/linked/\((path as NSString).lastPathComponent)")
            }
        }
        if options.rawData {
            let dataFolder = EngagementStore.shared.currentFolder
            if let items = try? fm.contentsOfDirectory(at: dataFolder, includingPropertiesForKeys: nil) {
                for item in items { copyItem(item, to: "data/\(item.lastPathComponent)") }
            }
        }

        var zipURL: URL?
        if options.zip {
            let target = destination.appendingPathComponent(folder.lastPathComponent + ".zip")
            try? fm.removeItem(at: target)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            process.currentDirectoryURL = destination
            process.arguments = ["-qr", target.path, folder.lastPathComponent]
            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus == 0 { zipURL = target } else { warnings.append("zip exited with status \(process.terminationStatus)") }
            } catch {
                warnings.append("Could not run zip: \(error.localizedDescription)")
            }
        }

        ActivityLog.shared.record(.action, "Close-out exported: \(files) file(s) → \(folder.lastPathComponent)\(zipURL != nil ? " (+ zip)" : "")", source: "Engagements")
        return Result(folder: folder, zip: zipURL, files: files, warnings: warnings)
    }
}

/// Sheet: tick what goes into the close-out package and pick a destination folder.
struct CloseOutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.luikTheme) private var theme
    @Environment(EngagementStore.self) private var engagements
    @Environment(UIState.self) private var ui
    @State private var options = CloseOut.Options()
    @State private var result: CloseOut.Result?
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Close-out export — \(engagements.current.displayName)")
                .font(.headline)
            Text("Everything of this engagement into one folder (and a zip): report material, a dossier per host, plans, the log, notes, diagrams, evidence and the raw data. Nothing is deleted from Luik.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
                GridRow {
                    Toggle("Findings report (Markdown + HTML)", isOn: $options.findings)
                    Toggle("Notes", isOn: $options.notes)
                }
                GridRow {
                    Toggle("Targets overview", isOn: $options.targets)
                    Toggle("Diagrams (PNG + JSON)", isOn: $options.diagrams)
                }
                GridRow {
                    Toggle("Dossier per host", isOn: $options.hostDossiers)
                    Toggle("Evidence files", isOn: $options.evidence)
                }
                GridRow {
                    Toggle("Plans", isOn: $options.plans)
                    Toggle("Raw data (JSON)", isOn: $options.rawData)
                }
                GridRow {
                    Toggle("Activity log", isOn: $options.log)
                    Toggle("Zip the folder", isOn: $options.zip)
                }
                GridRow {
                    Toggle("…with captured command outputs", isOn: $options.logOutputs)
                        .disabled(!options.log)
                        .padding(.leading, 18)
                    Color.clear.frame(height: 1)
                }
            }
            if let result {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Label("\(result.files) file(s) written to \(result.folder.lastPathComponent)\(result.zip != nil ? " and zipped" : "")", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    ForEach(result.warnings, id: \.self) { warning in
                        Text(warning)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    HStack {
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([result.zip ?? result.folder]) }
                        Button("Open folder") { NSWorkspace.shared.open(result.folder) }
                    }
                    .controlSize(.small)
                }
            }
            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(working ? "Exporting…" : "Choose folder and export…") { run() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(working)
            }
        }
        .padding(16)
        .frame(width: 560)
    }

    private func run() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Export here"
        panel.message = "Choose the folder that will hold the close-out package"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        working = true
        let accent = theme.accentColor
        DispatchQueue.main.async {
            result = CloseOut.export(to: destination, options: options, accent: accent)
            working = false
            if let result { ui.flash("Close-out: \(result.files) file(s) exported.") }
        }
    }
}
