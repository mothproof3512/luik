import AppKit
import SwiftUI

struct ActivityView: View {
    @Environment(ActivityLog.self) private var log
    @State private var newNote = ""
    @State private var showClearConfirmation = false
    @State private var copiedID: UUID?

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE d MMMM yyyy"
        return formatter
    }()

    var body: some View {
        @Bindable var log = log
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField("Search the log…", text: $log.search)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 300)
                Picker("", selection: $log.kindFilter) {
                    Text("Everything").tag(ActivityEntry.Kind?.none)
                    ForEach(ActivityEntry.Kind.allCases, id: \.self) { kind in
                        Text(kind.label).tag(ActivityEntry.Kind?.some(kind))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 140)
                Spacer()
                Button {
                    if log.isPaused { log.resume() } else { log.pause() }
                } label: {
                    Label(log.isPaused ? "Resume logging" : "Pause logging", systemImage: log.isPaused ? "record.circle" : "pause.circle")
                }
                .tint(log.isPaused ? Color.red : nil)
                .buttonStyle(.bordered)
                .help(log.isPaused
                      ? "Logging is paused: nothing is recorded. Click to resume."
                      : "Stop recording commands, imports and actions for a while (client data, secrets); a marker is written now and when you resume")
                Text("\(log.filtered.count) of \(log.entries.count)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Menu {
                    Button("Copy as Markdown (filtered)") { log.copy(log.markdown(filteredOnly: true)) }
                    Button("Export everything as Markdown…") { exportMarkdown() }
                    Button("Show data folder in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([log.fileURL])
                    }
                    Divider()
                    Button("Clear log…", role: .destructive) { showClearConfirmation = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .frame(width: 44)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            HStack(spacing: 8) {
                TextField("Add a note to the log (what you found, what you decided, what you are about to do)…", text: $newNote)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addNote)
                Button("Add", action: addNote)
                    .disabled(newNote.trimmingCharacters(in: .whitespaces).isEmpty)
                Button {
                    AppDelegate.shared?.captureEvidenceHidingLuik()
                } label: {
                    Label("Evidence", systemImage: "camera")
                }
                .help("Capture an evidence screenshot (⌘⇧E)")
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            Divider()

            if log.entries.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Nothing logged yet.")
                        .font(.headline)
                    Text("Commands pasted from One-liners or Searchsploit, commands typed in Luik's terminal tabs, imports and your own notes end up here with a timestamp — handy for the report and for \"what did I do at 14:32?\".")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                .padding(24)
                .frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach(groupedByDay(log.filtered), id: \.day) { group in
                        Section(group.day) {
                            ForEach(group.entries) { entry in
                                ActivityRow(entry: entry,
                                            time: ActivityView.timeFormatter.string(from: entry.time),
                                            isCopied: copiedID == entry.id,
                                            copy: {
                                                log.copy(entry.text)
                                                copiedID = entry.id
                                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                                    if copiedID == entry.id { copiedID = nil }
                                                }
                                            },
                                            delete: { log.delete(entry) })
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .confirmationDialog("Clear the whole activity log?", isPresented: $showClearConfirmation) {
            Button("Clear", role: .destructive) { log.clear() }
        } message: {
            Text("Export it first if you still need it for the report.")
        }
    }

    private struct DayGroup {
        let day: String
        let entries: [ActivityEntry]
    }

    private func groupedByDay(_ entries: [ActivityEntry]) -> [DayGroup] {
        var groups: [DayGroup] = []
        for entry in entries {
            let day = ActivityView.dayFormatter.string(from: entry.time)
            if let last = groups.last, last.day == day {
                groups[groups.count - 1] = DayGroup(day: day, entries: last.entries + [entry])
            } else {
                groups.append(DayGroup(day: day, entries: [entry]))
            }
        }
        return groups
    }

    private func addNote() {
        let text = newNote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        log.record(.note, text, source: "Log")
        newNote = ""
    }

    private func exportMarkdown() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "activity-log.md"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? log.markdown(filteredOnly: false).write(to: url, atomically: true, encoding: .utf8)
    }
}

struct ActivityRow: View {
    let entry: ActivityEntry
    let time: String
    let isCopied: Bool
    let copy: () -> Void
    let delete: () -> Void
    @Environment(UIState.self) private var ui
    @State private var showOutput = false
    @State private var fullOutput = false

    private var isCommand: Bool { entry.kind == .command || entry.kind == .typed }
    private var output: CommandOutput? { CommandOutputStore.shared.record(id: entry.outputID) }

    private static let previewLines = 60

    /// Hands the command to the One-liners editor, with the current $RHOST/$RPORT/$LHOST/$LPORT
    /// values turned back into placeholders so the one-liner works on the next target.
    private func saveAsOneLiner() {
        let snippets = SnippetStore.shared
        var command = entry.text
        let substitutions: [(String, String)] = [
            (snippets.target, "$RHOST"), (snippets.lhost, "$LHOST"), (snippets.rport, "$RPORT"), (snippets.lport, "$LPORT"),
        ]
        for (value, placeholder) in substitutions {
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            guard trimmed.count >= 2 else { continue }
            command = command.replacingOccurrences(of: trimmed, with: placeholder)
        }
        let firstLine = command.split(separator: "\n").first.map(String.init) ?? command
        let title = firstLine.split(separator: " ").prefix(4).joined(separator: " ")
        ui.pendingSnippet = Snippet(title: title, command: command, category: "From log")
        ui.open(.snippets)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(time)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            Image(systemName: entry.kind.symbol)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                if entry.kind == .command || entry.kind == .typed {
                    Text(entry.text)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                } else {
                    Text(entry.text)
                        .font(.callout)
                        .textSelection(.enabled)
                }
                HStack(spacing: 8) {
                    Text("\(entry.kind.label) · \(entry.source)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let code = entry.exitCode, code != 0 {
                        Text("exit \(code)")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.red.opacity(0.25), in: Capsule())
                            .help("The command ended with exit status \(code)")
                    }
                    if let output {
                        Button {
                            showOutput.toggle()
                        } label: {
                            Label("Output · \(output.lines) line\(output.lines == 1 ? "" : "s")", systemImage: showOutput ? "chevron.down" : "chevron.right")
                                .font(.caption2)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        if let format = output.format {
                            Text(output.imported ? "\(format.shortName) · imported" : format.shortName)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background((output.imported ? Color.green : Color.orange).opacity(0.25), in: Capsule())
                        }
                    }
                }
                if showOutput, let output {
                    outputView(output)
                }
            }
            Spacer()
            if let output {
                Menu {
                    pinMenu(output)
                } label: {
                    Image(systemName: "pin")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .foregroundStyle(.secondary)
                .help("Pin the command and its output as evidence")
                if let format = output.format {
                    Button {
                        importScan(output, format: format)
                    } label: {
                        Image(systemName: output.imported ? "checkmark.circle" : "square.and.arrow.down.on.square")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(output.imported ? Color.green : Color.orange)
                    .help(output.imported ? "\(format.shortName) output was imported into Targets (click to import again)" : "Import this \(format.shortName) output into Targets")
                }
            }
            if isCommand {
                Button(action: saveAsOneLiner) {
                    Image(systemName: "bookmark")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Save as one-liner — opens the One-liners editor with this command ($RHOST etc. put back)")
            }
            Button(action: copy) {
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Copy")
            Button(role: .destructive, action: delete) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Delete this entry")
        }
        .padding(.vertical, 2)
        .contextMenu {
            if isCommand {
                Button("Save as one-liner…") { saveAsOneLiner() }
            }
            if let output {
                Menu("Pin as evidence") { pinMenu(output) }
                Button("Copy output") { ActivityLog.shared.copy(CommandOutputStore.shared.text(of: output)) }
                Button("Copy command and output as Markdown") {
                    ActivityLog.shared.copy(EvidencePin.markdown(command: output.command, output: CommandOutputStore.shared.text(of: output), time: output.time, source: output.source))
                }
                if let format = output.format {
                    Button("Import \(format.shortName) output into Targets") { importScan(output, format: format) }
                }
                Button("Show output file in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([CommandOutputStore.shared.fileURL(of: output)])
                }
            }
            Button("Copy") { copy() }
            Button("Delete", role: .destructive) { delete() }
        }
    }

    @ViewBuilder
    private func pinMenu(_ output: CommandOutput) -> some View {
        ForEach(EvidencePin.availableDestinations, id: \.self) { destination in
            Button(EvidencePin.label(for: destination)) {
                let message = EvidencePin.pin(command: output.command, output: CommandOutputStore.shared.text(of: output), time: output.time, source: output.source, to: destination)
                ui.flash(message)
            }
        }
    }

    private func importScan(_ output: CommandOutput, format: ScanFormat) {
        let result = TargetStore.shared.importScan(CommandOutputStore.shared.text(of: output), options: ScanImportOptions())
        CommandOutputStore.shared.markImported(output.id)
        ui.flash("\(format.shortName): \(result.summary)")
    }

    private func outputView(_ output: CommandOutput) -> some View {
        let text = CommandOutputStore.shared.text(of: output)
        let lines = text.components(separatedBy: "\n")
        let shown = fullOutput || lines.count <= ActivityRow.previewLines ? text : lines.prefix(ActivityRow.previewLines).joined(separator: "\n")
        return VStack(alignment: .leading, spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                Text(shown)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: true)
            }
            .padding(6)
            .background(Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
            if lines.count > ActivityRow.previewLines {
                Button(fullOutput ? "Show the first \(ActivityRow.previewLines) lines" : "Show all \(lines.count) lines") { fullOutput.toggle() }
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
        .padding(.top, 4)
    }
}
