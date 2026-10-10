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

    func record(_ kind: ActivityEntry.Kind, _ text: String, source: String) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        let work = {
            self.entries.append(ActivityEntry(kind: kind, text: cleaned, source: source))
            if self.entries.count > ActivityLog.maxEntries {
                self.entries.removeFirst(self.entries.count - ActivityLog.maxEntries)
            }
            self.scheduleSave()
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
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
    func markdown(filteredOnly: Bool) -> String {
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

/// Rebuilds the line a user is typing from the raw bytes a terminal sends to its shell, so a
/// finished command can be logged. Handles backspace, Ctrl-C/Ctrl-U and skips escape sequences.
final class TypedLineRecorder {
    private var line: [UInt8] = []
    private var escape: [UInt8] = []
    private var inEscape = false

    /// Feeds bytes; returns a completed line when Enter was pressed.
    func feed(_ bytes: ArraySlice<UInt8>) -> String? {
        var completed: String? = nil
        for byte in bytes {
            if inEscape {
                escape.append(byte)
                // CSI sequences end with a byte in 0x40–0x7E (after the '[' + params); other escapes end after one byte.
                if escape.count == 1 {
                    if byte != 0x5B && byte != 0x4F { inEscape = false; escape.removeAll() }
                } else if byte >= 0x40 && byte <= 0x7E {
                    inEscape = false
                    escape.removeAll()
                }
                continue
            }
            switch byte {
            case 0x1B:
                inEscape = true
                escape.removeAll()
            case 0x0D, 0x0A:
                if !line.isEmpty {
                    completed = String(decoding: line, as: UTF8.self)
                }
                line.removeAll()
            case 0x7F, 0x08:
                if !line.isEmpty { line.removeLast() }
            case 0x03, 0x15: // Ctrl-C, Ctrl-U
                line.removeAll()
            case 0x09: // Tab completion: unknown result, keep what we have
                break
            default:
                if byte >= 0x20 || byte >= 0x80 {
                    line.append(byte)
                }
            }
        }
        return completed
    }

    func reset() {
        line.removeAll()
        escape.removeAll()
        inEscape = false
    }
}
