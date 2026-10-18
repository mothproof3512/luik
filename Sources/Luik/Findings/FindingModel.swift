import Foundation
import SwiftUI

enum Severity: String, Codable, CaseIterable, Comparable {
    case critical, high, medium, low, info

    var label: String {
        switch self {
        case .critical: return "Critical"
        case .high: return "High"
        case .medium: return "Medium"
        case .low: return "Low"
        case .info: return "Info"
        }
    }

    var color: Color {
        switch self {
        case .critical: return .purple
        case .high: return .red
        case .medium: return .orange
        case .low: return .green
        case .info: return .gray
        }
    }

    /// 0 = most severe, for sorting.
    var order: Int {
        switch self {
        case .critical: return 0
        case .high: return 1
        case .medium: return 2
        case .low: return 3
        case .info: return 4
        }
    }

    static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.order < rhs.order }

    /// CVSS qualitative rating: 0 = none/info, 0.1–3.9 low, 4–6.9 medium, 7–8.9 high, 9+ critical.
    static func from(score: Double) -> Severity {
        if score >= 9 { return .critical }
        if score >= 7 { return .high }
        if score >= 4 { return .medium }
        if score > 0 { return .low }
        return .info
    }

    /// Accepts English/Dutch words, Nessus numbers (0–4) and CVSS scores.
    static func parse(_ text: String) -> Severity? {
        let value = text.trimmingCharacters(in: .whitespaces).lowercased()
        switch value {
        case "critical", "kritiek", "crit", "4": return .critical
        case "high", "hoog", "3": return .high
        case "medium", "middel", "moderate", "gemiddeld", "2": return .medium
        case "low", "laag", "1": return .low
        case "info", "informational", "informatief", "none", "0", "unknown": return .info
        default:
            if let number = Double(value.replacingOccurrences(of: ",", with: ".")), number <= 10 {
                return from(score: number)
            }
            return nil
        }
    }
}

enum FindingStatus: String, Codable, CaseIterable {
    case open
    case confirmed
    case reported
    case resolved
    case falsePositive

    var label: String {
        switch self {
        case .open: return "Open"
        case .confirmed: return "Confirmed"
        case .reported: return "Reported"
        case .resolved: return "Resolved"
        case .falsePositive: return "False positive"
        }
    }

    var symbol: String {
        switch self {
        case .open: return "circle"
        case .confirmed: return "checkmark.circle"
        case .reported: return "doc.text"
        case .resolved: return "checkmark.circle.fill"
        case .falsePositive: return "xmark.circle"
        }
    }
}

/// Outcome of a retest of an earlier finding.
enum RetestStatus: String, Codable, CaseIterable {
    case notRetested
    case fixed
    case partiallyFixed
    case stillOpen

    var label: String {
        switch self {
        case .notRetested: return "Not retested"
        case .fixed: return "Fixed"
        case .partiallyFixed: return "Partially fixed"
        case .stillOpen: return "Still open"
        }
    }

    var symbol: String {
        switch self {
        case .notRetested: return "arrow.triangle.2.circlepath"
        case .fixed: return "checkmark.shield.fill"
        case .partiallyFixed: return "shield.lefthalf.filled"
        case .stillOpen: return "exclamationmark.shield.fill"
        }
    }
}

/// One finding for the report: what, how bad (severity + CVSS), where (affected hosts/ports),
/// and the usual report sections. Stored in findings.json of the engagement.
struct Finding: Identifiable, Codable, Equatable {
    var id = UUID()
    var title = ""
    var severity: Severity = .medium
    var cvssVector = ""             // CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H
    var affected: [String] = []     // "10.10.10.5", "10.10.10.5:445/tcp", "https://app.example.com/login"
    var description = ""
    var impact = ""
    var evidence = ""
    var recommendation = ""
    var references = ""
    var status: FindingStatus = .open
    var source = ""                 // "Nessus 57608", "nuclei http-missing-security-headers", "KB SEC-012", ""
    var createdAt = Date()
    var updatedAt = Date()
    /// Retest of an earlier finding: where it came from, what was found this time.
    var originalReference = ""      // "Acme external 2025 · F-07" or the earlier report's id
    var retestStatus: RetestStatus = .notRetested
    var retestDate: Date?
    var retestNotes = ""

    var isRetest: Bool { !originalReference.isEmpty || retestStatus != .notRetested }

    var cvssScore: Double? {
        CVSS31.score(vector: cvssVector)?.base
    }

    var affectedText: String {
        affected.joined(separator: "\n")
    }

    init(id: UUID = UUID(), title: String = "", severity: Severity = .medium) {
        self.id = id
        self.title = title
        self.severity = severity
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, severity, cvssVector, affected, description, impact, evidence, recommendation, references, status, source, createdAt, updatedAt
        case originalReference, retestStatus, retestDate, retestNotes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        severity = try c.decodeIfPresent(Severity.self, forKey: .severity) ?? .medium
        cvssVector = try c.decodeIfPresent(String.self, forKey: .cvssVector) ?? ""
        affected = try c.decodeIfPresent([String].self, forKey: .affected) ?? []
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        impact = try c.decodeIfPresent(String.self, forKey: .impact) ?? ""
        evidence = try c.decodeIfPresent(String.self, forKey: .evidence) ?? ""
        recommendation = try c.decodeIfPresent(String.self, forKey: .recommendation) ?? ""
        references = try c.decodeIfPresent(String.self, forKey: .references) ?? ""
        status = try c.decodeIfPresent(FindingStatus.self, forKey: .status) ?? .open
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? ""
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        originalReference = try c.decodeIfPresent(String.self, forKey: .originalReference) ?? ""
        retestStatus = try c.decodeIfPresent(RetestStatus.self, forKey: .retestStatus) ?? .notRetested
        retestDate = try c.decodeIfPresent(Date.self, forKey: .retestDate)
        retestNotes = try c.decodeIfPresent(String.self, forKey: .retestNotes) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(severity, forKey: .severity)
        try c.encode(cvssVector, forKey: .cvssVector)
        try c.encode(affected, forKey: .affected)
        try c.encode(description, forKey: .description)
        try c.encode(impact, forKey: .impact)
        try c.encode(evidence, forKey: .evidence)
        try c.encode(recommendation, forKey: .recommendation)
        try c.encode(references, forKey: .references)
        try c.encode(status, forKey: .status)
        try c.encode(source, forKey: .source)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        if !originalReference.isEmpty { try c.encode(originalReference, forKey: .originalReference) }
        if retestStatus != .notRetested { try c.encode(retestStatus, forKey: .retestStatus) }
        if let retestDate { try c.encode(retestDate, forKey: .retestDate) }
        if !retestNotes.isEmpty { try c.encode(retestNotes, forKey: .retestNotes) }
    }
}
