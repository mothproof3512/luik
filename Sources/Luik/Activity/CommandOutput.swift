import AppKit
import Foundation
import Observation

/// What a command printed, kept next to its Log entry: the text lives in
/// <engagement>/outputs/<id>.txt, this record in outputs.json.
struct CommandOutput: Identifiable, Codable, Equatable {
    var id = UUID()
    /// The Log entry (Command / Typed) this output belongs to.
    var entryID: UUID
    var time = Date()
    var command: String
    var source: String
    var lines: Int
    var bytes: Int
    /// Scanner output Luik recognised (nmap, nuclei, masscan, Nessus) — raw value of ScanFormat.
    var scanFormat: String?
    /// Set once the scanner output has been imported into Targets (by hand or automatically).
    var imported = false

    var fileName: String { "\(id.uuidString).txt" }

    var format: ScanFormat? { scanFormat.flatMap { ScanFormat(rawValue: $0) } }
}

/// Keeps the output of every command run in a Luik terminal tab, so a finding can carry the exact
/// command, its output and the time as evidence, and scanner output can flow into Targets without
/// copy-and-paste. Per engagement; capped so a long engagement does not fill the disk.
@Observable
final class CommandOutputStore {
    static let shared = CommandOutputStore()

    private static let indexName = "outputs.json"
    private static let folderName = "outputs"
    static let maxRecords = 1500
    static let maxBytes = 1_000_000
    static let maxLines = 6000

    var records: [CommandOutput] = []
    @ObservationIgnored private var cache: [UUID: String] = [:]
    @ObservationIgnored private var saver = Debouncer(delay: 1.0)

    init() {
        load()
    }

    func reload() {
        saver.flush()
        cache = [:]
        load()
    }

    private func load() {
        records = Storage.load([CommandOutput].self, at: EngagementStore.shared.fileURL(CommandOutputStore.indexName)) ?? []
    }

    private var folder: URL {
        let url = EngagementStore.shared.fileURL(CommandOutputStore.folderName)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    func fileURL(of record: CommandOutput) -> URL {
        folder.appendingPathComponent(record.fileName)
    }

    // MARK: - Storing

    /// Keeps `output` for the Log entry `entryID`. Returns the record (nil for empty output).
    @discardableResult
    func store(_ rawOutput: String, for entryID: UUID, command: String, source: String) -> CommandOutput? {
        var output = CommandOutputStore.clean(rawOutput)
        guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        var lineCount = output.reduce(0) { $0 + ($1 == "\n" ? 1 : 0) } + 1
        if lineCount > CommandOutputStore.maxLines {
            output = output.split(separator: "\n", omittingEmptySubsequences: false).prefix(CommandOutputStore.maxLines).joined(separator: "\n") + "\n… (truncated)"
            lineCount = CommandOutputStore.maxLines + 1
        }
        if output.utf8.count > CommandOutputStore.maxBytes {
            output = String(output.utf8.prefix(CommandOutputStore.maxBytes)) ?? output
            output += "\n… (truncated)"
        }
        let format = ScanDetect.format(of: output, command: command)
        var record = CommandOutput(entryID: entryID, command: command, source: source, lines: lineCount, bytes: output.utf8.count, scanFormat: format?.rawValue)
        do {
            try output.write(to: fileURL(of: record), atomically: true, encoding: .utf8)
        } catch {
            NSLog("Luik: could not save command output: %@", String(describing: error))
            return nil
        }
        cache[record.id] = output
        records.append(record)
        trim()
        ActivityLog.shared.attachOutput(record.id, to: entryID, scanFormat: format)
        if let format, UserDefaults.standard.bool(forKey: SettingsKey.autoImportScans) {
            let result = TargetStore.shared.importScan(output, options: ScanImportOptions())
            if result.newHosts + result.updatedHosts + result.newPorts + result.newFindings > 0 {
                record.imported = true
                if let index = records.firstIndex(where: { $0.id == record.id }) { records[index].imported = true }
                ActivityLog.shared.record(.import, "\(format.shortName) output of “\(CommandOutputStore.shortCommand(command))” imported automatically: \(result.summary)", source: "Terminal")
            }
        }
        scheduleSave()
        return record
    }

    /// Terminal text: no trailing blank lines, no cursor-position artefacts.
    static func clean(_ text: String) -> String {
        var lines = text.components(separatedBy: "\n").map { line -> String in
            var trimmed = line
            while trimmed.hasSuffix(" ") { trimmed.removeLast() }
            return trimmed
        }
        while let last = lines.last, last.isEmpty { lines.removeLast() }
        while let first = lines.first, first.isEmpty { lines.removeFirst() }
        return lines.joined(separator: "\n")
    }

    static func shortCommand(_ command: String) -> String {
        let firstLine = command.split(separator: "\n").first.map(String.init) ?? command
        return firstLine.count > 60 ? String(firstLine.prefix(57)) + "…" : firstLine
    }

    private func trim() {
        guard records.count > CommandOutputStore.maxRecords else { return }
        let drop = records.prefix(records.count - CommandOutputStore.maxRecords)
        for old in drop {
            try? FileManager.default.removeItem(at: fileURL(of: old))
            cache[old.id] = nil
        }
        records.removeFirst(drop.count)
    }

    func markImported(_ id: UUID) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        records[index].imported = true
        scheduleSave()
    }

    func remove(_ id: UUID) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        try? FileManager.default.removeItem(at: fileURL(of: records[index]))
        cache[id] = nil
        records.remove(at: index)
        scheduleSave()
    }

    // MARK: - Reading

    func record(id: UUID?) -> CommandOutput? {
        guard let id else { return nil }
        return records.first { $0.id == id }
    }

    func record(forEntry entryID: UUID) -> CommandOutput? {
        records.last { $0.entryID == entryID }
    }

    func text(of record: CommandOutput) -> String {
        if let cached = cache[record.id] { return cached }
        let text = (try? String(contentsOf: fileURL(of: record), encoding: .utf8)) ?? ""
        cache[record.id] = text
        return text
    }

    func text(ofOutput id: UUID?) -> String? {
        guard let record = record(id: id) else { return nil }
        return text(of: record)
    }

    // MARK: - Saving

    private func scheduleSave() {
        let url = EngagementStore.shared.fileURL(CommandOutputStore.indexName)
        saver.call { [weak self] in
            guard let self else { return }
            Storage.save(self.records, at: url)
        }
    }

    func flush() {
        saver.flush()
    }
}

/// Recognises scanner output in what a command printed. Stricter than ScanImport.detect, which
/// falls back to nmap for anything: here "nothing" is a valid answer.
enum ScanDetect {
    static func format(of output: String, command: String) -> ScanFormat? {
        let head = String(output.prefix(200_000))
        if head.contains("<NessusClientData") { return .nessus }
        if head.contains("Nmap scan report for") || head.contains("<nmaprun") { return .nmap }
        if head.contains("Host: ") && head.contains("Ports: ") && (head.contains("# Nmap") || head.contains("# Masscan")) { return .nmap }
        if head.contains("\"template-id\"") || head.contains("\"templateID\"") || head.contains("\"matched-at\"") { return .nuclei }
        if ScanImport.nucleiLine.firstMatch(in: head, range: NSRange(head.startIndex..., in: head)) != nil { return .nuclei }
        let trimmed = head.trimmingCharacters(in: .whitespacesAndNewlines)
        if (trimmed.hasPrefix("[") || trimmed.hasPrefix("{")) && trimmed.contains("\"ports\"") && trimmed.contains("\"ip\"") { return .masscanJSON }
        if ScanImport.masscanListLine.firstMatch(in: head, range: NSRange(head.startIndex..., in: head)) != nil { return .masscanList }
        return nil
    }
}

extension ScanFormat {
    var shortName: String {
        switch self {
        case .nmap: return "nmap"
        case .nessus: return "Nessus"
        case .nuclei: return "nuclei"
        case .masscanList, .masscanJSON: return "masscan"
        }
    }
}

/// Puts a command and its output into a finding, a target node or a note as Markdown evidence.
enum EvidencePin {
    enum Destination: Hashable {
        case selectedFinding
        case selectedTarget
        case newNote
    }

    static func markdown(command: String, output: String, time: Date, source: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let fence = output.contains("```") ? "````" : "```"
        var text = "**\(formatter.string(from: time))** · \(source)\n\n"
        text += fence + "\n$ " + command + "\n"
        if !output.isEmpty { text += output + "\n" }
        text += fence + "\n"
        return text
    }

    /// Where the pin can go right now, in order of preference.
    static var availableDestinations: [Destination] {
        var result: [Destination] = []
        if FindingsStore.shared.selectedID != nil { result.append(.selectedFinding) }
        if TargetStore.shared.selectedNode != nil { result.append(.selectedTarget) }
        result.append(.newNote)
        return result
    }

    static func label(for destination: Destination) -> String {
        switch destination {
        case .selectedFinding:
            let title = FindingsStore.shared.findings.first { $0.id == FindingsStore.shared.selectedID }?.title ?? ""
            return "Evidence of finding “\(title.isEmpty ? "Untitled" : title)”"
        case .selectedTarget:
            return "Notes of target \(TargetStore.shared.selectedNode?.title ?? "")"
        case .newNote:
            return "New note"
        }
    }

    /// Returns a one-line description of what happened.
    @discardableResult
    static func pin(command: String, output: String, time: Date, source: String, to destination: Destination) -> String {
        let block = markdown(command: command, output: output, time: time, source: source)
        let short = CommandOutputStore.shortCommand(command)
        switch destination {
        case .selectedFinding:
            let store = FindingsStore.shared
            guard let id = store.selectedID, let index = store.findings.firstIndex(where: { $0.id == id }) else {
                return "No finding selected."
            }
            var evidence = store.findings[index].evidence
            if !evidence.isEmpty && !evidence.hasSuffix("\n") { evidence += "\n" }
            if !evidence.isEmpty { evidence += "\n" }
            evidence += block
            store.findings[index].evidence = evidence
            store.findings[index].updatedAt = Date()
            store.scheduleSave()
            ActivityLog.shared.record(.evidence, "Output of “\(short)” pinned to finding “\(store.findings[index].title)”", source: "Terminal")
            return "Pinned to finding “\(store.findings[index].title)”."
        case .selectedTarget:
            guard let node = TargetStore.shared.selectedNode else { return "No target selected." }
            var notes = node.notes
            if !notes.isEmpty && !notes.hasSuffix("\n") { notes += "\n" }
            if !notes.isEmpty { notes += "\n" }
            notes += block
            node.notes = notes
            TargetStore.shared.scheduleSave()
            ActivityLog.shared.record(.evidence, "Output of “\(short)” pinned to target \(node.title)", source: "Terminal")
            return "Pinned to \(node.title)."
        case .newNote:
            let notes = NotesStore.shared
            let note = Note(title: short, body: "# \(short)\n\n" + block)
            notes.notes.insert(note, at: 0)
            notes.scheduleSave()
            ActivityLog.shared.record(.evidence, "Output of “\(short)” saved as a note", source: "Terminal")
            return "Saved as note “\(short)”."
        }
    }
}
