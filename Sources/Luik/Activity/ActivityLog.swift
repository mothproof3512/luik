import AppKit
import Foundation
import Observation

/// One line in the activity log.
struct ActivityEntry: Identifiable, Codable, Equatable {
    enum Kind: String, Codable, CaseIterable {
        case command   // pasted into the terminal by Luik (one-liners, Searchsploit, …)
        case typed     // typed by hand in a Luik terminal tab
        case note      // added by hand in the Log tab
        case `import`  // nmap / knowledge base / exploit-db imports
        case action    // other things Luik did (export, add finding to target, …)
        case evidence  // screenshot captured

        var label: String {
            switch self {
            case .command: return "Command"
            case .typed: return "Typed"
            case .note: return "Note"
            case .import: return "Import"
            case .action: return "Action"
            case .evidence: return "Evidence"
            }
        }

        var symbol: String {
            switch self {
            case .command: return "terminal"
            case .typed: return "keyboard"
            case .note: return "note.text"
            case .import: return "square.and.arrow.down"
            case .action: return "bolt"
            case .evidence: return "camera"
            }
        }
    }

    var id = UUID()
    var time = Date()
    var kind: Kind
    var text: String
    var source: String      // e.g. "One-liners", "Terminal: Shell", "Targets"
    /// The captured output of this command (CommandOutputStore), when there is one.
    var outputID: UUID? = nil
    /// Scanner output recognised in that output (ScanFormat raw value).
    var scanFormat: String? = nil
    /// The host this line is about (bound terminal, or the $RHOST the command names).
    var host: String? = nil
    /// Exit status of the command (shell integration).
    var exitCode: Int32? = nil
}

/// Timestamped record of what happened during an engagement: commands Luik pasted into the
/// terminal, commands typed in Luik's terminal tabs, imports, and notes you add yourself.
/// Stored in activity.json of the engagement; exportable as Markdown for the report.
@Observable
final class ActivityLog {
    static let shared = ActivityLog()

    private static let fileName = "activity.json"
    private static let maxEntries = 20_000

    var entries: [ActivityEntry] = []
    var search: String = ""
    var kindFilter: ActivityEntry.Kind? = nil
    /// Paused: nothing is recorded (commands, imports, actions) until you resume — for the moments
    /// client data or secrets go over the screen. Not remembered across launches.
    var isPaused = false
    var pausedAt: Date? = nil
    @ObservationIgnored private var saver = Debouncer(delay: 1.0)

    init() {
        entries = Storage.load([ActivityEntry].self, at: EngagementStore.shared.fileURL(ActivityLog.fileName)) ?? []
    }

    /// Called when the engagement changes.
    func reload() {
        saver.flush()
        entries = Storage.load([ActivityEntry].self, at: EngagementStore.shared.fileURL(ActivityLog.fileName)) ?? []
        search = ""
        kindFilter = nil
    }

    /// Where the current engagement's log lives (for "Show in Finder").
    var fileURL: URL { EngagementStore.shared.fileURL(ActivityLog.fileName) }

    var filtered: [ActivityEntry] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        return entries.reversed().filter { entry in
            if let kindFilter, entry.kind != kindFilter { return false }
            if query.isEmpty { return true }
            return entry.text.lowercased().contains(query) || entry.source.lowercased().contains(query)
        }
    }

    func pause() {
        guard !isPaused else { return }
        record(.action, "Logging paused — nothing is recorded until you resume", source: "Log")
        isPaused = true
        pausedAt = Date()
    }

    func resume() {
        guard isPaused else { return }
        isPaused = false
        let since = pausedAt.map { " (paused \(Int(Date().timeIntervalSince($0) / 60)) min)" } ?? ""
        pausedAt = nil
        record(.action, "Logging resumed\(since)", source: "Log")
    }

    /// Returns the new entry's id (nil when paused or empty), so a command's output can be attached later.
    @discardableResult
    func record(_ kind: ActivityEntry.Kind, _ text: String, source: String, host: String? = nil) -> UUID? {
        guard !isPaused else { return nil }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        var entry = ActivityEntry(kind: kind, text: cleaned, source: source)
        entry.host = host
        let work = {
            self.entries.append(entry)
            if self.entries.count > ActivityLog.maxEntries {
                self.entries.removeFirst(self.entries.count - ActivityLog.maxEntries)
            }
            self.scheduleSave()
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
        return entry.id
    }

    func entry(id: UUID) -> ActivityEntry? {
        entries.first { $0.id == id }
    }

    func attachExitCode(_ code: Int32, to entryID: UUID) {
        guard let index = entries.lastIndex(where: { $0.id == entryID }) else { return }
        entries[index].exitCode = code
        scheduleSave()
    }

    /// Links a captured output to its command entry.
    func attachOutput(_ outputID: UUID, to entryID: UUID, scanFormat: ScanFormat?) {
        guard let index = entries.lastIndex(where: { $0.id == entryID }) else { return }
        entries[index].outputID = outputID
        entries[index].scanFormat = scanFormat?.rawValue
        scheduleSave()
    }

    func delete(_ entry: ActivityEntry) {
        entries.removeAll { $0.id == entry.id }
        scheduleSave()
    }

    func clear() {
        entries.removeAll()
        scheduleSave()
    }

    /// The log as Markdown (oldest first), optionally only the filtered entries.
    func markdown(filteredOnly: Bool, includeOutput: Bool = false) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let list = filteredOnly ? Array(filtered.reversed()) : entries
        var out = "# Activity log\n\n"
        var currentDay = ""
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        for entry in list {
            let day = dayFormatter.string(from: entry.time)
            if day != currentDay {
                currentDay = day
                out += "\n## \(day)\n\n"
            }
            let time = formatter.string(from: entry.time)
            switch entry.kind {
            case .command, .typed:
                out += "- `\(time)` **\(entry.kind.label)** (\(entry.source))\n\n    ```\n    \(entry.text.replacingOccurrences(of: "\n", with: "\n    "))\n    ```\n\n"
                if includeOutput, let output = CommandOutputStore.shared.text(ofOutput: entry.outputID), !output.isEmpty {
                    out += "    Output:\n\n    ```\n    \(output.replacingOccurrences(of: "\n", with: "\n    "))\n    ```\n\n"
                }
            default:
                out += "- `\(time)` **\(entry.kind.label)** (\(entry.source)): \(entry.text)\n"
            }
        }
        return out
    }

    func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func scheduleSave() {
        let url = EngagementStore.shared.fileURL(ActivityLog.fileName)
        saver.call { [weak self] in
            guard let self else { return }
            Storage.save(self.entries, at: url)
        }
    }

    func flush() {
        saver.flush()
    }
}
