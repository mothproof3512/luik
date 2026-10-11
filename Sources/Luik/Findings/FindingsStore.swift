import AppKit
import Foundation
import Observation
import SwiftUI

/// Findings of the current engagement (findings.json in the engagement folder).
@Observable
final class FindingsStore {
    static let shared = FindingsStore()

    private static let fileName = "findings.json"

    var findings: [Finding] = []
    var selectedID: UUID? = nil
    var search = ""
    var severityFilter: Severity? = nil
    var statusFilter: FindingStatus? = nil
    @ObservationIgnored private var saver = Debouncer()

    init() {
        findings = Storage.load([Finding].self, at: EngagementStore.shared.fileURL(FindingsStore.fileName)) ?? []
    }

    /// Called when the engagement changes.
    func reload() {
        saver.flush()
        findings = Storage.load([Finding].self, at: EngagementStore.shared.fileURL(FindingsStore.fileName)) ?? []
        selectedID = nil
        search = ""
        severityFilter = nil
        statusFilter = nil
    }

    // MARK: - Lookup

    var selected: Finding? {
        findings.first { $0.id == selectedID }
    }

    /// Sorted by severity (critical first), then CVSS score, then title; filtered by the toolbar.
    var filtered: [Finding] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        let terms = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        return sorted.filter { finding in
            if let severityFilter, finding.severity != severityFilter { return false }
            if let statusFilter, finding.status != statusFilter { return false }
            guard !terms.isEmpty else { return true }
            let text = [finding.title, finding.description, finding.impact, finding.evidence, finding.recommendation,
                        finding.references, finding.source, finding.affected.joined(separator: " ")].joined(separator: " ").lowercased()
            return terms.allSatisfy { text.contains($0) }
        }
    }

    var sorted: [Finding] {
        findings.sorted { a, b in
            if a.severity != b.severity { return a.severity < b.severity }
            let sa = a.cvssScore ?? -1, sb = b.cvssScore ?? -1
            if sa != sb { return sa > sb }
            return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        }
    }

    var counts: [Severity: Int] {
        var result: [Severity: Int] = [:]
        for finding in findings where finding.status != .falsePositive {
            result[finding.severity, default: 0] += 1
        }
        return result
    }

    func binding(for id: UUID) -> Binding<Finding> {
        Binding(
            get: { [weak self] in
                self?.findings.first { $0.id == id } ?? Finding()
            },
            set: { [weak self] newValue in
                guard let self, let index = self.findings.firstIndex(where: { $0.id == id }) else { return }
                var updated = newValue
                updated.updatedAt = Date()
                self.findings[index] = updated
                self.scheduleSave()
            }
        )
    }

    // MARK: - Mutations

    @discardableResult
    func add(_ finding: Finding, select: Bool = true) -> Finding {
        findings.append(finding)
        if select { selectedID = finding.id }
        scheduleSave()
        return finding
    }

    @discardableResult
    func newFinding() -> Finding {
        let finding = Finding(title: "New finding")
        ActivityLog.shared.record(.action, "New finding created", source: "Findings")
        return add(finding)
    }

    func delete(_ id: UUID) {
        guard let finding = findings.first(where: { $0.id == id }) else { return }
        findings.removeAll { $0.id == id }
        if selectedID == id { selectedID = nil }
        scheduleSave()
        ActivityLog.shared.record(.action, "Deleted finding “\(finding.title)”", source: "Findings")
    }

    func duplicate(_ id: UUID) {
        guard let original = findings.first(where: { $0.id == id }) else { return }
        var copy = original
        copy.id = UUID()
        copy.title = original.title + " (copy)"
        copy.createdAt = Date()
        copy.updatedAt = Date()
        add(copy)
    }

    func deleteAll() {
        findings.removeAll()
        selectedID = nil
        scheduleSave()
    }

    /// Adds addresses to a finding's affected list without duplicates.
    func addAffected(_ addresses: [String], to id: UUID) {
        guard let index = findings.firstIndex(where: { $0.id == id }) else { return }
        for address in addresses where !findings[index].affected.contains(address) {
            findings[index].affected.append(address)
        }
        findings[index].updatedAt = Date()
        scheduleSave()
    }

    /// A finding with the same source id (e.g. "Nessus 57608") — used to merge scanner imports.
    func finding(withSource source: String) -> Finding? {
        guard !source.isEmpty else { return nil }
        return findings.first { $0.source == source }
    }

    // MARK: - Creating findings from other tabs

    /// "10.10.10.5:445/tcp" for a port node, "10.10.10.5" for a host, the host's address otherwise.
    static func affectedLabel(for node: TargetNode, in targets: TargetStore) -> String? {
        guard let host = targets.host(of: node) else { return nil }
        if node.kind == .port {
            return "\(host.address):\(node.portNumber)/\(node.portProtocol)"
        }
        if let parent = targets.parent(of: node.id), parent.kind == .port, let parentHost = targets.host(of: parent) {
            return "\(parentHost.address):\(parent.portNumber)/\(parent.portProtocol)"
        }
        return host.address
    }

    /// Finding pre-filled from a targets node: the node's notes become the evidence.
    @discardableResult
    func create(from node: TargetNode, in targets: TargetStore) -> Finding {
        var finding = Finding(title: node.kind == .host ? "Finding on \(node.title)" : node.title)
        if let host = targets.host(of: node), node.kind != .host {
            finding.title = "\(node.title) (\(host.title))"
        }
        if let label = FindingsStore.affectedLabel(for: node, in: targets) {
            finding.affected = [label]
        }
        let notes = node.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty { finding.evidence = notes }
        if node.kind == .port, !node.subtitle.isEmpty { finding.description = "Service: \(node.subtitle)\n" }
        ActivityLog.shared.record(.action, "Finding “\(finding.title)” created from target node \(node.title)", source: "Findings")
        return add(finding)
    }

    /// Finding pre-filled from a knowledge-base record, mapping columns by name.
    @discardableResult
    func create(fromKnowledgeBase hit: KBHit, roles: KBColumnRoles, affected: [String]) -> Finding {
        let record = hit.record
        let columns = hit.table.columns
        func column(matching patterns: [String], excluding: [String]) -> String? {
            for pattern in patterns {
                if let found = columns.first(where: { column in
                    !excluding.contains(column) && column.lowercased().contains(pattern)
                }) { return found }
            }
            return nil
        }
        let id = roles.idColumn.map { record.value($0) } ?? ""
        let title = roles.titleColumn.map { record.value($0) } ?? ""
        var finding = Finding(title: title.isEmpty ? (id.isEmpty ? "Finding" : id) : title)
        finding.source = id.isEmpty ? "" : "KB \(id)"
        if let severityColumn = roles.severityColumn, let severity = Severity.parse(record.value(severityColumn)) {
            finding.severity = severity
        }
        let used: [String] = [roles.idColumn, roles.titleColumn].compactMap { $0 }
        if let c = column(matching: ["cvss_vector", "cvss vector", "vector string", "cvss3"], excluding: used), CVSS31.parse(record.value(c)) != nil {
            finding.cvssVector = record.value(c)
            if let result = CVSS31.score(vector: finding.cvssVector) { finding.severity = result.severity }
        }
        var mapped: Set<String> = []
        /// The first matching column that has a value (an empty "evidence" column in a knowledge
        /// base must not hide a filled "test approach" column).
        func take(_ patterns: [String]) -> String {
            for pattern in patterns {
                for c in columns where !used.contains(c) && !mapped.contains(c) && c.lowercased().contains(pattern) {
                    let value = record.value(c)
                    if !value.isEmpty {
                        mapped.insert(c)
                        return value
                    }
                }
            }
            return ""
        }
        finding.description = take(["description", "omschrijving", "beschrijving", "details", "explanation"])
        finding.impact = take(["impact", "risk description", "consequence", "gevolg"])
        finding.recommendation = take(["recommendation", "remediation", "mitigation", "solution", "advice", "aanbeveling", "oplossing", "fix"])
        finding.references = take(["reference", "references", "link", "url", "source", "bron", "see also"])
        let evidence = take(["evidence", "proof", "bewijs", "how to test", "test", "detection", "verification"])
        if !evidence.isEmpty { finding.evidence = evidence }
        // Everything else that has a value is kept in the description, so nothing from the sheet is lost.
        var extra: [String] = []
        for c in columns where !used.contains(c) && !mapped.contains(c) && c != roles.severityColumn {
            let value = record.value(c)
            if !value.isEmpty { extra.append("**\(c.replacingOccurrences(of: "_", with: " "))**: \(value)") }
        }
        if !extra.isEmpty {
            finding.description += (finding.description.isEmpty ? "" : "\n\n") + extra.joined(separator: "\n")
        }
        finding.affected = affected
        ActivityLog.shared.record(.action, "Finding “\(finding.title)” created from the knowledge base", source: "Findings")
        return add(finding)
    }

    // MARK: - Reports

    func markdown(for finding: Finding) -> String {
        var out = "## \(finding.title)\n\n"
        var meta = ["**Severity**: \(finding.severity.label)"]
        if let score = finding.cvssScore { meta.append("**CVSS 3.1**: \(CVSS31.format(score)) (`\(finding.cvssVector)`)") }
        meta.append("**Status**: \(finding.status.label)")
        if !finding.source.isEmpty { meta.append("**Source**: \(finding.source)") }
        out += meta.joined(separator: " · ") + "\n\n"
        if !finding.affected.isEmpty {
            out += "**Affected**:\n\n" + finding.affected.map { "- \($0)" }.joined(separator: "\n") + "\n\n"
        }
        for (heading, text) in [("Description", finding.description), ("Impact", finding.impact), ("Evidence", finding.evidence),
                                ("Recommendation", finding.recommendation), ("References", finding.references)] {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { out += "### \(heading)\n\n\(trimmed)\n\n" }
        }
        return out
    }

    func markdownReport(includeFalsePositives: Bool = false) -> String {
        let engagement = EngagementStore.shared.current
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        var out = "# Findings — \(engagement.name)\n\n"
        var meta: [String] = []
        if !engagement.client.isEmpty { meta.append("**Client**: \(engagement.client)") }
        if !engagement.reference.isEmpty { meta.append("**Reference**: \(engagement.reference)") }
        if !engagement.period.isEmpty { meta.append("**Period**: \(engagement.period)") }
        meta.append("**Generated**: \(formatter.string(from: Date())) with Luik \(AppInfo.version)")
        out += meta.joined(separator: "  \n") + "\n\n"
        if !engagement.scope.isEmpty {
            out += "**Scope**: " + engagement.scope.joined(separator: ", ") + "\n\n"
        }
        let list = sorted.filter { includeFalsePositives || $0.status != .falsePositive }
        out += "## Summary\n\n| Severity | Count |\n|---|---|\n"
        for severity in Severity.allCases {
            out += "| \(severity.label) | \(list.filter { $0.severity == severity }.count) |\n"
        }
        out += "\n| # | Finding | Severity | CVSS | Affected | Status |\n|---|---|---|---|---|---|\n"
        for (index, finding) in list.enumerated() {
            let score = finding.cvssScore.map { CVSS31.format($0) } ?? ""
            let affected = finding.affected.count > 3 ? "\(finding.affected.count) hosts/services" : finding.affected.joined(separator: ", ")
            out += "| \(index + 1) | \(finding.title) | \(finding.severity.label) | \(score) | \(affected) | \(finding.status.label) |\n"
        }
        out += "\n## Findings\n\n"
        for (index, finding) in list.enumerated() {
            out += markdown(for: finding).replacingOccurrences(of: "## \(finding.title)", with: "## \(index + 1). \(finding.title)")
            out += "\n"
        }
        return out
    }

    /// Stand-alone HTML with light styling; Word opens it directly (File › Open) and pandoc turns it into .docx.
    func htmlReport(includeFalsePositives: Bool = false) -> String {
        let engagement = EngagementStore.shared.current
        let list = sorted.filter { includeFalsePositives || $0.status != .falsePositive }
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
        }
        func paragraphs(_ text: String) -> String {
            text.trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: "\n\n")
                .map { "<p>" + esc($0).replacingOccurrences(of: "\n", with: "<br>") + "</p>" }
                .joined(separator: "\n")
        }
        let colors: [Severity: String] = [.critical: "#7b1fa2", .high: "#c62828", .medium: "#ef6c00", .low: "#2e7d32", .info: "#616161"]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        var html = """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8"><title>Findings — \(esc(engagement.name))</title>
        <style>
        body { font-family: -apple-system, "Segoe UI", Helvetica, Arial, sans-serif; max-width: 900px; margin: 40px auto; color: #222; line-height: 1.45; }
        h1 { border-bottom: 2px solid #444; padding-bottom: 6px; } h2 { margin-top: 40px; } h3 { margin-bottom: 4px; color: #444; }
        table { border-collapse: collapse; width: 100%; margin: 12px 0 24px; } th, td { border: 1px solid #ccc; padding: 6px 8px; text-align: left; vertical-align: top; }
        th { background: #f0f0f0; } .sev { display: inline-block; color: #fff; padding: 2px 8px; border-radius: 4px; font-size: 0.85em; font-weight: 600; }
        .meta { color: #555; } pre, code { font-family: Menlo, Consolas, monospace; font-size: 0.9em; } .affected li { font-family: Menlo, Consolas, monospace; }
        </style></head><body>
        <h1>Findings — \(esc(engagement.name))</h1>
        <p class="meta">
        """
        var meta: [String] = []
        if !engagement.client.isEmpty { meta.append("<b>Client:</b> \(esc(engagement.client))") }
        if !engagement.reference.isEmpty { meta.append("<b>Reference:</b> \(esc(engagement.reference))") }
        if !engagement.period.isEmpty { meta.append("<b>Period:</b> \(esc(engagement.period))") }
        if !engagement.scope.isEmpty { meta.append("<b>Scope:</b> \(esc(engagement.scope.joined(separator: ", ")))") }
        meta.append("<b>Generated:</b> \(formatter.string(from: Date())) with Luik \(AppInfo.version)")
        html += meta.joined(separator: "<br>\n") + "\n</p>\n<h2>Summary</h2>\n<table><tr><th>Severity</th><th>Count</th></tr>\n"
        for severity in Severity.allCases {
            html += "<tr><td><span class=\"sev\" style=\"background:\(colors[severity]!)\">\(severity.label)</span></td><td>\(list.filter { $0.severity == severity }.count)</td></tr>\n"
        }
        html += "</table>\n<table><tr><th>#</th><th>Finding</th><th>Severity</th><th>CVSS</th><th>Affected</th><th>Status</th></tr>\n"
        for (index, finding) in list.enumerated() {
            let score = finding.cvssScore.map { CVSS31.format($0) } ?? ""
            let affected = finding.affected.count > 3 ? "\(finding.affected.count) hosts/services" : esc(finding.affected.joined(separator: ", "))
            html += "<tr><td>\(index + 1)</td><td><a href=\"#f\(index + 1)\">\(esc(finding.title))</a></td><td><span class=\"sev\" style=\"background:\(colors[finding.severity]!)\">\(finding.severity.label)</span></td><td>\(score)</td><td>\(affected)</td><td>\(finding.status.label)</td></tr>\n"
        }
        html += "</table>\n"
        for (index, finding) in list.enumerated() {
            html += "<h2 id=\"f\(index + 1)\">\(index + 1). \(esc(finding.title))</h2>\n<p class=\"meta\"><span class=\"sev\" style=\"background:\(colors[finding.severity]!)\">\(finding.severity.label)</span>"
            if let score = finding.cvssScore { html += " &nbsp; <b>CVSS 3.1:</b> \(CVSS31.format(score)) <code>\(esc(finding.cvssVector))</code>" }
            html += " &nbsp; <b>Status:</b> \(finding.status.label)"
            if !finding.source.isEmpty { html += " &nbsp; <b>Source:</b> \(esc(finding.source))" }
            html += "</p>\n"
            if !finding.affected.isEmpty {
                html += "<h3>Affected</h3>\n<ul class=\"affected\">\n" + finding.affected.map { "<li>\(esc($0))</li>" }.joined(separator: "\n") + "\n</ul>\n"
            }
            for (heading, text) in [("Description", finding.description), ("Impact", finding.impact), ("Evidence", finding.evidence),
                                    ("Recommendation", finding.recommendation), ("References", finding.references)] {
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    html += "<h3>\(heading)</h3>\n\(paragraphs(text))\n"
                }
            }
        }
        html += "</body></html>\n"
        return html
    }

    func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    // MARK: - Saving

    func scheduleSave() {
        let url = EngagementStore.shared.fileURL(FindingsStore.fileName)
        saver.call { [weak self] in
            guard let self else { return }
            Storage.save(self.findings, at: url)
        }
    }

    func flush() {
        saver.flush()
    }
}
