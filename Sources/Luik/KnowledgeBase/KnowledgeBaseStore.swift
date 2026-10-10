import AppKit
import Foundation
import Observation
import SwiftUI

/// The imported knowledge base (findings, attack vectors, …) with full-text search over every column.
/// Stored in knowledgebase.json in the Luik data folder; nothing is bundled with the app.
@Observable
final class KnowledgeBaseStore {
    static let shared = KnowledgeBaseStore()

    private static let fileName = "knowledgebase.json"
    private static let maxResults = 500

    var knowledgeBase: KnowledgeBase?
    var search: String = ""
    var scopeFilter: String = ""      // "" = all
    var severityFilter: String = ""   // "" = all
    var phaseFilter: String = ""      // "" = all
    var selectedID: UUID? = nil
    var lastError: String? = nil

    /// Lower-cased concatenation of all values per record, for fast matching.
    @ObservationIgnored private var haystacks: [UUID: String] = [:]
    @ObservationIgnored private var tableByRecord: [UUID: KBTable] = [:]

    init() {
        knowledgeBase = Storage.load(KnowledgeBase.self, from: KnowledgeBaseStore.fileName)
        rebuildIndex()
    }

    // MARK: - Import / remove

    func importFile(at url: URL) {
        do {
            let tables = try SpreadsheetImport.importFile(at: url)
            let imported = KnowledgeBase(sourceName: url.lastPathComponent, importedAt: Date(), tables: tables)
            knowledgeBase = imported
            lastError = nil
            selectedID = nil
            scopeFilter = ""
            severityFilter = ""
            phaseFilter = ""
            rebuildIndex()
            Storage.save(imported, to: KnowledgeBaseStore.fileName)
            ActivityLog.shared.record(.import, "Knowledge base imported: \(imported.sourceName) (\(imported.recordCount) rows)", source: "Knowledge base")
        } catch {
            lastError = error.localizedDescription
        }
    }

    func remove() {
        knowledgeBase = nil
        selectedID = nil
        search = ""
        scopeFilter = ""
        severityFilter = ""
        phaseFilter = ""
        rebuildIndex()
        try? FileManager.default.removeItem(at: Storage.url(for: KnowledgeBaseStore.fileName))
    }

    private func rebuildIndex() {
        haystacks = [:]
        tableByRecord = [:]
        guard let knowledgeBase else { return }
        for table in knowledgeBase.tables {
            for record in table.records {
                let text = table.columns.compactMap { record.values[$0] }.joined(separator: "\n")
                haystacks[record.id] = text.lowercased()
                tableByRecord[record.id] = table
            }
        }
    }

    // MARK: - Column roles and filter values

    /// Roles are detected on the largest table (the main sheet).
    var roles: KBColumnRoles {
        guard let main = mainTable else { return KBColumnRoles() }
        return KBColumnRoles.detect(in: main.columns)
    }

    var mainTable: KBTable? {
        knowledgeBase?.tables.max { $0.records.count < $1.records.count }
    }

    var scopeValues: [String] {
        distinctValues(of: roles.scopeColumn)
    }

    var severityValues: [String] {
        let values = distinctValues(of: roles.severityColumn)
        let order = ["critical", "high", "medium", "low", "info", "informational"]
        return values.sorted { a, b in
            let ia = order.firstIndex(of: a.lowercased()) ?? order.count
            let ib = order.firstIndex(of: b.lowercased()) ?? order.count
            return ia != ib ? ia < ib : a < b
        }
    }

    var phaseValues: [String] {
        let values = distinctValues(of: roles.phaseColumn)
        let order = KBColumnRoles.phaseOrder
        return values.sorted { a, b in
            let ia = order.firstIndex(of: a.lowercased()) ?? order.count
            let ib = order.firstIndex(of: b.lowercased()) ?? order.count
            return ia != ib ? ia < ib : a < b
        }
    }

    private func distinctValues(of column: String?) -> [String] {
        guard let column, let knowledgeBase else { return [] }
        var seen: [String] = []
        for table in knowledgeBase.tables {
            for record in table.records {
                if let value = record.values[column], !seen.contains(value) {
                    seen.append(value)
                }
            }
        }
        return seen.count > 60 ? [] : seen.sorted()
    }

    // MARK: - Search

    /// Search terms: whitespace-separated, "quoted phrases" stay together. All terms must match.
    var terms: [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        for char in search {
            if char == "\"" {
                inQuotes.toggle()
            } else if char.isWhitespace && !inQuotes {
                if !current.isEmpty { result.append(current.lowercased()) }
                current = ""
            } else {
                current.append(char)
            }
        }
        if !current.isEmpty { result.append(current.lowercased()) }
        return result
    }

    var hits: [KBHit] {
        guard let knowledgeBase else { return [] }
        let terms = self.terms
        let roles = self.roles
        var result: [KBHit] = []

        for table in knowledgeBase.tables {
            for record in table.records {
                if let scopeColumn = roles.scopeColumn, !scopeFilter.isEmpty, record.value(scopeColumn) != scopeFilter { continue }
                if let severityColumn = roles.severityColumn, !severityFilter.isEmpty, record.value(severityColumn) != severityFilter { continue }
                if let phaseColumn = roles.phaseColumn, !phaseFilter.isEmpty, record.value(phaseColumn) != phaseFilter { continue }

                var score = 0
                if !terms.isEmpty {
                    guard let haystack = haystacks[record.id] else { continue }
                    var allMatch = true
                    for term in terms {
                        if !haystack.contains(term) { allMatch = false; break }
                        if let id = roles.idColumn, record.value(id).lowercased().contains(term) { score += 3 }
                        if let title = roles.titleColumn, record.value(title).lowercased().contains(term) { score += 2 }
                        score += 1
                    }
                    if !allMatch { continue }
                }
                result.append(KBHit(record: record, table: table, score: score))
            }
        }
        if !terms.isEmpty {
            // Stable sort by score, best first; original order otherwise.
            result = result.enumerated().sorted { a, b in
                a.element.score != b.element.score ? a.element.score > b.element.score : a.offset < b.offset
            }.map { $0.element }
        }
        return Array(result.prefix(KnowledgeBaseStore.maxResults))
    }

    /// Synchronous search with explicit terms and no filters, for the suggestions at a port node.
    func quickSearch(terms: [String], limit: Int) -> [KBHit] {
        guard let knowledgeBase, !terms.isEmpty else { return [] }
        let roles = self.roles
        var result: [KBHit] = []
        for table in knowledgeBase.tables {
            for record in table.records {
                guard let haystack = haystacks[record.id] else { continue }
                var score = 0
                var allMatch = true
                for term in terms {
                    if !haystack.contains(term) { allMatch = false; break }
                    if let id = roles.idColumn, record.value(id).lowercased().contains(term) { score += 3 }
                    if let title = roles.titleColumn, record.value(title).lowercased().contains(term) { score += 2 }
                    score += 1
                }
                if allMatch { result.append(KBHit(record: record, table: table, score: score)) }
            }
        }
        result.sort { $0.score > $1.score }
        return Array(result.prefix(limit))
    }

    /// Opens the Knowledge base tab with this search and record selected.
    func show(recordID: UUID, query: String) {
        search = query
        scopeFilter = ""
        severityFilter = ""
        phaseFilter = ""
        selectedID = recordID
        UIState.shared.module = .knowledgeBase
    }

    var totalMatching: Int {
        hits.count
    }

    func hit(for id: UUID?) -> KBHit? {
        guard let id, let table = tableByRecord[id], let record = table.records.first(where: { $0.id == id }) else { return nil }
        return KBHit(record: record, table: table, score: 0)
    }

    // MARK: - Highlighting and export

    /// The text with every search term highlighted.
    func highlighted(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        let terms = self.terms
        guard !terms.isEmpty else { return attributed }
        for term in terms where !term.isEmpty {
            var searchRange = text.startIndex..<text.endIndex
            while let found = text.range(of: term, options: [.caseInsensitive, .diacriticInsensitive], range: searchRange) {
                if let attributedRange = Range(found, in: attributed) {
                    attributed[attributedRange].backgroundColor = Color.yellow.opacity(0.45)
                    attributed[attributedRange].foregroundColor = Color.white
                }
                searchRange = found.upperBound..<text.endIndex
            }
        }
        return attributed
    }

    /// A record as Markdown, e.g. to paste into notes or a target node.
    func markdown(for hit: KBHit) -> String {
        let roles = self.roles
        let record = hit.record
        var title = roles.titleColumn.map { record.value($0) } ?? ""
        if let id = roles.idColumn, !record.value(id).isEmpty {
            title = title.isEmpty ? record.value(id) : "\(record.value(id)) — \(title)"
        }
        var out = "## \(title.isEmpty ? "Finding" : title)\n\n"
        for column in hit.table.columns where column != roles.idColumn && column != roles.titleColumn {
            let value = record.value(column)
            if value.isEmpty { continue }
            let label = column.replacingOccurrences(of: "_", with: " ")
            out += "**\(label)**: \(value)\n\n"
        }
        return out
    }

    func copyMarkdown(for hit: KBHit) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(markdown(for: hit), forType: .string)
    }
}
