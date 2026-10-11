import Foundation

/// One row of an imported table. Values are keyed by column name.
struct KBRecord: Identifiable, Codable {
    var id = UUID()
    var values: [String: String]

    func value(_ column: String) -> String {
        values[column] ?? ""
    }
}

/// One imported sheet (or CSV/JSON file) with its columns in original order.
struct KBTable: Identifiable, Codable {
    var id = UUID()
    var name: String
    var columns: [String]
    var records: [KBRecord]
}

/// Everything imported, stored in knowledgebase.json.
struct KnowledgeBase: Codable {
    var sourceName: String
    var importedAt: Date
    var tables: [KBTable]
    /// Where a downloaded knowledge base came from (nil for a local file).
    var sourceURL: String?
    /// Catalogue entry id and version, so the download sheet can offer an update.
    var catalogID: String?
    var version: String?

    var recordCount: Int {
        tables.reduce(0) { $0 + $1.records.count }
    }
}

/// A search hit: the record plus the table it came from and a relevance score.
struct KBHit: Identifiable {
    let record: KBRecord
    let table: KBTable
    let score: Int

    var id: UUID { record.id }
}

/// Which columns play a special role in the UI, detected from the headers.
struct KBColumnRoles {
    var idColumn: String?
    var titleColumn: String?
    var scopeColumn: String?
    var severityColumn: String?
    var phaseColumn: String?   // kill chain phase / ATT&CK tactic

    static func detect(in columns: [String]) -> KBColumnRoles {
        func first(matching patterns: [String], excluding: [String] = []) -> String? {
            for pattern in patterns {
                if let column = columns.first(where: { column in
                    let lower = column.lowercased()
                    return lower.contains(pattern) && !excluding.contains { lower.contains($0) }
                }) {
                    return column
                }
            }
            return nil
        }
        var roles = KBColumnRoles()
        roles.idColumn = columns.first { $0.lowercased() == "id" } ?? first(matching: ["id"])
        // "attack vector" is the title in some sheets; a "cvss_vector" column is not.
        roles.titleColumn = first(matching: ["vector", "title", "name", "finding", "bevinding", "vulnerability", "summary"], excluding: ["cvss"])
        if roles.titleColumn == nil || roles.titleColumn == roles.idColumn {
            roles.titleColumn = columns.first { $0 != roles.idColumn }
        }
        roles.scopeColumn = first(matching: ["scope", "category", "categorie"])
        roles.severityColumn = first(matching: ["severity", "risk", "ernst", "cvss_score", "cvss"])
        roles.phaseColumn = first(matching: ["kill_chain", "kill chain", "killchain", "phase", "fase", "tactic"])
        return roles
    }

    /// Kill chain / ATT&CK tactics in attack order, for sorting the filter menu.
    static let phaseOrder: [String] = [
        "reconnaissance", "resource development", "weaponization", "delivery", "initial access",
        "execution", "persistence", "privilege escalation", "defense evasion", "credential access",
        "discovery", "lateral movement", "collection", "command and control", "exfiltration",
        "actions on objectives", "impact",
    ]
}
