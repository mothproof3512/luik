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
    private static let mineFileName = "my-knowledge.json"
    private static let maxResults = 500

    var knowledgeBase: KnowledgeBase?
    /// Your own records — findings saved from the Findings tab, edited by hand. Kept in a separate
    /// file (my-knowledge.json), so re-importing or removing the downloaded knowledge base never
    /// touches them.
    var mine: KBTable
    var search: String = ""
    var scopeFilter: String = ""      // "" = all
    var severityFilter: String = ""   // "" = all
    var phaseFilter: String = ""      // "" = all
    /// Only your own records (My findings).
    var onlyMine = false
    var selectedID: UUID? = nil
    var lastError: String? = nil

    /// Lower-cased concatenation of all values per record, for fast matching.
    @ObservationIgnored private var haystacks: [UUID: String] = [:]
    @ObservationIgnored private var tableByRecord: [UUID: KBTable] = [:]
    @ObservationIgnored private var rolesByTable: [UUID: KBColumnRoles] = [:]

    init() {
        knowledgeBase = Storage.load(KnowledgeBase.self, from: KnowledgeBaseStore.fileName)
        mine = Storage.load(KBTable.self, from: KnowledgeBaseStore.mineFileName) ?? KBTable.myFindings()
        rebuildIndex()
    }

    /// Imported tables plus your own records (when there are any).
    var allTables: [KBTable] {
        (knowledgeBase?.tables ?? []) + (mine.records.isEmpty ? [] : [mine])
    }

    var isEmpty: Bool { knowledgeBase == nil && mine.records.isEmpty }

    var recordCount: Int { (knowledgeBase?.recordCount ?? 0) + mine.records.count }

    func isMine(_ table: KBTable) -> Bool { table.id == mine.id }

    // MARK: - Own records

    private func saveMine() {
        Storage.save(mine, to: KnowledgeBaseStore.mineFileName)
        rebuildIndex()
    }

    private func nextMyID() -> String {
        let numbers = mine.records.compactMap { Int($0.value(KBTable.myIDColumn).replacingOccurrences(of: "MY-", with: "")) }
        return String(format: "MY-%03d", (numbers.max() ?? 0) + 1)
    }

    /// Saves a finding as a record of your own. A finding that came from one of your records
    /// (source "KB MY-…") updates that record instead of adding a second one. Returns the record id.
    @discardableResult
    func save(_ finding: Finding) -> String {
        let existing = finding.source.hasPrefix("KB MY-") ? String(finding.source.dropFirst(3)) : nil
        let index = existing.flatMap { id in mine.records.firstIndex { $0.value(KBTable.myIDColumn) == id } }
        let id = index.map { mine.records[$0].value(KBTable.myIDColumn) } ?? nextMyID()
        var values = index.map { mine.records[$0].values } ?? [:]
        values[KBTable.myIDColumn] = id
        values["Title"] = finding.title
        values["Severity"] = finding.severity.label
        values["CVSS_Vector"] = finding.cvssVector
        values["Description"] = finding.description
        values["Impact"] = finding.impact
        values["Recommendation"] = finding.recommendation
        values["References"] = finding.references
        if existing == nil {
            values["Origin"] = [finding.source, EngagementStore.shared.current.name].filter { !$0.isEmpty }.joined(separator: " · ")
            values["Added"] = ISO8601DateFormatter().string(from: Date())
        }
        values["Updated"] = ISO8601DateFormatter().string(from: Date())
        if let index {
            mine.records[index].values = values
        } else {
            mine.records.append(KBRecord(values: values))
        }
        saveMine()
        ActivityLog.shared.record(.action, "\(index == nil ? "Saved" : "Updated") knowledge-base record \(id): \(finding.title)", source: "Findings")
        return id
    }

    func update(_ record: KBRecord) {
        guard let index = mine.records.firstIndex(where: { $0.id == record.id }) else { return }
        mine.records[index] = record
        saveMine()
    }

    func removeMine(_ id: UUID) {
        mine.records.removeAll { $0.id == id }
        if selectedID == id { selectedID = nil }
        saveMine()
    }

    var mineFileURL: URL { Storage.url(for: KnowledgeBaseStore.mineFileName) }

    // MARK: - Import / remove

    /// Imports a local file. A download passes its name and origin, so the ⋯ menu can show where
    /// the knowledge base came from and the download sheet can offer a newer version.
    func importFile(at url: URL, sourceName: String? = nil, sourceURL: String? = nil, catalogID: String? = nil, version: String? = nil) {
        do {
            let tables = try SpreadsheetImport.importFile(at: url)
            var imported = KnowledgeBase(sourceName: sourceName ?? url.lastPathComponent, importedAt: Date(), tables: tables)
            imported.sourceURL = sourceURL
            imported.catalogID = catalogID
            imported.version = version
            knowledgeBase = imported
            lastError = nil
            selectedID = nil
            scopeFilter = ""
            severityFilter = ""
            phaseFilter = ""
            rebuildIndex()
            Storage.save(imported, to: KnowledgeBaseStore.fileName)
            let origin = sourceURL.map { " from \($0)" } ?? ""
            ActivityLog.shared.record(.import, "Knowledge base imported: \(imported.sourceName) (\(imported.recordCount) rows)\(origin)", source: "Knowledge base")
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
        rolesByTable = [:]
        for table in allTables {
            rolesByTable[table.id] = KBColumnRoles.detect(in: table.columns)
            for record in table.records {
                let text = table.columns.compactMap { record.values[$0] }.joined(separator: "\n")
                haystacks[record.id] = text.lowercased()
                tableByRecord[record.id] = table
            }
        }
    }

    // MARK: - Column roles and filter values

    /// Roles are detected on the largest table (the main sheet); the filter menus use these.
    var roles: KBColumnRoles {
        guard let main = mainTable else { return KBColumnRoles() }
        return KBColumnRoles.detect(in: main.columns)
    }

    /// Roles of one table — your own records have different headers than an imported sheet.
    func roles(for table: KBTable) -> KBColumnRoles {
        rolesByTable[table.id] ?? KBColumnRoles.detect(in: table.columns)
    }

    var mainTable: KBTable? {
        allTables.max { $0.records.count < $1.records.count }
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
        guard let column else { return [] }
        var seen: [String] = []
        for table in allTables {
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
        let terms = self.terms
        var result: [KBHit] = []

        for table in allTables {
            if onlyMine && !isMine(table) { continue }
            let roles = self.roles(for: table)
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
        guard !terms.isEmpty else { return [] }
        var result: [KBHit] = []
        for table in allTables {
            let roles = self.roles(for: table)
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
        onlyMine = false
        selectedID = recordID
        UIState.shared.open(.knowledgeBase)
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
        let roles = self.roles(for: hit.table)
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
