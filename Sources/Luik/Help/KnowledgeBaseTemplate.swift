import AppKit
import Foundation
import SwiftUI

/// An example knowledge-base sheet with the columns Luik recognises, plus the guide that explains
/// how to prepare your own.
enum KnowledgeBaseTemplate {
    static let columns = ["id", "title", "scope", "severity", "cvss_vector", "kill_chain_phase", "description",
                          "impact", "recommendation", "references", "how_to_test", "tags"]

    /// Two example rows that show what goes where; delete them once you have your own findings.
    static let exampleRows: [[String]] = [
        ["KB-001", "Example: outdated web server version", "Web", "Medium",
         "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:L/I:N/A:N", "Reconnaissance",
         "The web server reports a version that is no longer supported by the vendor and has publicly known weaknesses.",
         "An attacker can look up the public weaknesses of this exact version, which may lead to access to the server or disruption of the service.",
         "Update the web server to a supported version and stop publishing the version in the server banner.",
         "https://owasp.org/www-project-web-security-testing-guide/",
         "Read the Server header of a response and compare the version with the vendor's support policy.",
         "web, patching, example row - delete me"],
        ["KB-002", "Example: SMB signing not required", "Infrastructure", "Medium",
         "CVSS:3.1/AV:A/AC:H/PR:N/UI:N/S:U/C:H/I:H/A:N", "Lateral Movement",
         "The SMB service accepts connections without message signing.",
         "Network traffic can be relayed to other systems, which may give an attacker the rights of the relayed user on those systems.",
         "Require SMB signing on all servers and clients, for example through group policy.",
         "https://learn.microsoft.com/windows/security/",
         "Check the signing requirement with your port scanner's SMB security-mode script.",
         "smb, active directory, example row - delete me"],
    ]

    /// CSV with a UTF-8 byte-order mark, so Excel and Numbers open it with the right encoding.
    static var csv: String {
        func field(_ value: String) -> String {
            if value.contains(",") || value.contains("\"") || value.contains("\n") {
                return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            }
            return value
        }
        var lines = [columns.map(field).joined(separator: ",")]
        for row in exampleRows {
            lines.append(row.map(field).joined(separator: ","))
        }
        return "\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n"
    }

    /// Asks where to save the template; returns the file when it was written.
    @discardableResult
    static func save() -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "luik-knowledge-base-template.csv"
        panel.canCreateDirectories = true
        panel.message = "Open the file in Excel or Numbers, replace the example rows with your findings, save as .xlsx or .csv and import it in Luik."
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            ActivityLog.shared.record(.action, "Saved the knowledge-base template to \(url.path)", source: "Knowledge base")
            return url
        } catch {
            NSLog("Luik: could not save the template: %@", String(describing: error))
            return nil
        }
    }

    /// The guide shown in the Knowledge base tab.
    static let guide: [(title: String, text: String)] = [
        ("Start with a ready-made knowledge base",
         "Download… fetches the attack-vectors knowledge base from the Luik repository — 349 attack vectors and CVEs across web, API, network, Active Directory, cloud, mobile, wireless, social engineering, physical, endpoint and AI/LLM, mapped to OWASP, WSTG, ASVS, MITRE ATT&CK, CWE and CISA KEV — in English or Dutch. The same sheet also takes a link to your own file (GitHub, GitLab, a web server; a token for private repositories) or to a catalogue of your team's knowledge bases."),
        ("One row per finding, one column per field",
         "The header is the first row with at least two filled cells, so a title row above it is fine. Every sheet of an .xlsx workbook is imported; .csv/.tsv and .json (an array of objects) work too. Any column is searchable — a product, version, CVE, CWE or technique typed in the search box is matched against every cell."),
        ("Columns Luik recognises by name",
         "id — the finding's code (KB-001). A title: title, name, finding, vulnerability, summary or (attack) vector. scope or category — drives the scope filter. severity, risk or cvss — drives the severity filter and the coloured badge (Critical/High/Medium/Low/Info or a score). kill_chain_phase, phase or tactic — drives the phase filter, sorted in attack order."),
        ("Columns used by “Create finding”",
         "description, impact, recommendation (or remediation, solution, mitigation), references (or links, urls), how_to_test (or evidence, proof) and cvss_vector with a CVSS 3.x vector string fill the matching fields of a new finding; every other filled column is appended to the description, so nothing from your sheet is lost."),
        ("Start from the template",
         "“Save example template…” writes a CSV with these columns and two example rows. Open it in Excel or Numbers, replace the examples with your own findings, save as .xlsx or .csv and import it here. Re-importing replaces the previous copy; your original file is never changed."),
    ]
}

/// The guide as a view, used in the empty state and in the help popover.
struct KnowledgeBaseGuide: View {
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(KnowledgeBaseTemplate.guide.enumerated()), id: \.offset) { _, entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                        .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                    Text(entry.text)
                        .font(compact ? .caption : .callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Button {
                KnowledgeBaseTemplate.save()
            } label: {
                Label("Save example template…", systemImage: "square.and.arrow.down.on.square")
            }
        }
    }
}
