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
                Text("\(entry.kind.label) · \(entry.source)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
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
    }
}
