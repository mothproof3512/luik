import Foundation
import Observation

/// How often a one-liner or checklist item was actually used, per service — the memory that lets
/// Luik rank suggestions by what you did before instead of by the order of a list. Global
/// (usage.json in the data folder), never part of an engagement, never exported with a playbook.
struct UsageRecord: Codable, Equatable {
    var count = 0
    var lastUsed: Date?
    /// Uses per service name ("http", "microsoft-ds", "" for a host-level use).
    var byService: [String: Int] = [:]
}

@Observable
final class UsageStore {
    static let shared = UsageStore()

    private static let fileName = "usage.json"

    struct Stats: Codable {
        var snippets: [String: UsageRecord] = [:]
        /// Key: "<service>|<item title lower-cased>" → done / n/a counts.
        var checklistDone: [String: Int] = [:]
        var checklistSkipped: [String: Int] = [:]
    }

    var data = Stats()
    @ObservationIgnored private var saver = Debouncer(delay: 2.0)

    init() {
        data = Storage.load(Stats.self, from: UsageStore.fileName) ?? Stats()
    }

    // MARK: - One-liners

    func recordSnippet(_ id: UUID, service: String) {
        var record = data.snippets[id.uuidString] ?? UsageRecord()
        record.count += 1
        record.lastUsed = Date()
        let key = UsageStore.serviceKey(service)
        record.byService[key, default: 0] += 1
        data.snippets[id.uuidString] = record
        scheduleSave()
    }

    func usage(of id: UUID) -> UsageRecord? {
        data.snippets[id.uuidString]
    }

    /// Ranking score at a service: uses on this service weigh most, total use a little, recency a bit.
    func score(of id: UUID, service: String) -> Int {
        guard let record = data.snippets[id.uuidString] else { return 0 }
        let here = record.byService[UsageStore.serviceKey(service)] ?? 0
        let recent = record.lastUsed.map { Date().timeIntervalSince($0) < 14 * 86_400 ? 1 : 0 } ?? 0
        return here * 10 + min(record.count, 20) + recent
    }

    /// Snippets ordered by what you used before at this service; untouched ones keep their order.
    func ranked(_ snippets: [Snippet], service: String) -> [Snippet] {
        let scored = snippets.enumerated().map { (index: $0.offset, snippet: $0.element, score: score(of: $0.element.id, service: service)) }
        return scored.sorted { a, b in
            if a.score != b.score { return a.score > b.score }
            return a.index < b.index
        }.map { $0.snippet }
    }

    /// The one-liners used most, overall.
    func mostUsed(from snippets: [Snippet], limit: Int = 8) -> [Snippet] {
        snippets
            .compactMap { snippet -> (Snippet, UsageRecord)? in usage(of: snippet.id).map { (snippet, $0) } }
            .sorted { a, b in a.1.count != b.1.count ? a.1.count > b.1.count : (a.1.lastUsed ?? .distantPast) > (b.1.lastUsed ?? .distantPast) }
            .prefix(limit)
            .map { $0.0 }
    }

    // MARK: - Checklist items

    func recordChecklist(itemTitle: String, service: String, status: NodeStatus) {
        let key = UsageStore.serviceKey(service) + "|" + itemTitle.trimmingCharacters(in: .whitespaces).lowercased()
        switch status {
        case .done: data.checklistDone[key, default: 0] += 1
        case .notApplicable: data.checklistSkipped[key, default: 0] += 1
        default: return
        }
        scheduleSave()
    }

    func checklistCounts(itemTitle: String, service: String) -> (done: Int, skipped: Int) {
        let key = UsageStore.serviceKey(service) + "|" + itemTitle.trimmingCharacters(in: .whitespaces).lowercased()
        return (data.checklistDone[key] ?? 0, data.checklistSkipped[key] ?? 0)
    }

    /// Across all services, for the checklist editor.
    func checklistTotals(itemTitle: String) -> (done: Int, skipped: Int) {
        let suffix = "|" + itemTitle.trimmingCharacters(in: .whitespaces).lowercased()
        let done = data.checklistDone.filter { $0.key.hasSuffix(suffix) }.values.reduce(0, +)
        let skipped = data.checklistSkipped.filter { $0.key.hasSuffix(suffix) }.values.reduce(0, +)
        return (done, skipped)
    }

    static func serviceKey(_ service: String) -> String {
        service.lowercased().components(separatedBy: CharacterSet(charactersIn: "?/ ")).first ?? ""
    }

    var isEmpty: Bool { data.snippets.isEmpty && data.checklistDone.isEmpty && data.checklistSkipped.isEmpty }

    func reset() {
        data = Stats()
        scheduleSave()
    }

    private func scheduleSave() {
        saver.call { [weak self] in
            guard let self else { return }
            Storage.save(self.data, to: UsageStore.fileName)
        }
    }

    func flush() {
        saver.flush()
    }
}
