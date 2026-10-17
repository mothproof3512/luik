import AppKit
import Foundation
import Observation

/// DNS lookups through the system's dig (no third-party code, same resolver as the terminal).
enum DNS {
    /// TXT records of a name; quoted chunks of one record are joined.
    static func txt(_ name: String) -> [String] {
        dig(name, type: "TXT").compactMap { line in
            var record = ""
            var inQuotes = false
            var escaped = false
            var sawQuote = false
            for character in line {
                if escaped { record.append(character); escaped = false; continue }
                if character == "\\" && inQuotes { escaped = true; continue }
                if character == "\"" { inQuotes.toggle(); sawQuote = true; continue }
                if inQuotes { record.append(character) }
            }
            if !sawQuote { record = line.trimmingCharacters(in: .whitespaces) }
            return record.isEmpty ? nil : record
        }
    }

    /// MX hosts, by preference.
    static func mx(_ domain: String) -> [(priority: Int, host: String)] {
        dig(domain, type: "MX").compactMap { line in
            let parts = line.split(whereSeparator: { $0.isWhitespace })
            guard parts.count >= 2, let priority = Int(parts[0]) else { return nil }
            var host = String(parts[1])
            if host.hasSuffix(".") { host.removeLast() }
            return (priority, host)
        }.sorted { $0.priority < $1.priority }
    }

    static func a(_ name: String) -> [String] { dig(name, type: "A") }
    static func aaaa(_ name: String) -> [String] { dig(name, type: "AAAA") }

    static func dig(_ name: String, type: String) -> [String] {
        let tool = "/usr/bin/dig"
        guard FileManager.default.isExecutableFile(atPath: tool) else { return [] }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = ["+short", "+time=4", "+tries=1", "-t", type, name]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return []
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix(";") }
    }
}

/// One line of the verdict.
struct MailCheckItem: Identifiable, Hashable {
    enum Level: Int { case pass, info, warn, fail }

    let id = UUID()
    let level: Level
    let text: String
}

struct MailSecurityResult {
    var domain: String
    var checkedAt: Date
    var mx: [(priority: Int, host: String)] = []
    var spfRecords: [String] = []
    var spfLookups: Int = 0
    var spfExpanded: [String] = []
    var dmarcRecord: String?
    var dkim: [(selector: String, record: String, bits: Int?)] = []
    var selectorsTried: [String] = []
    var mtaSTS: String?
    var tlsRPT: String?
    var items: [MailCheckItem] = []

    var worst: MailCheckItem.Level { items.map { $0.level }.max(by: { $0.rawValue < $1.rawValue }) ?? .pass }
    var problems: [MailCheckItem] { items.filter { $0.level == .warn || $0.level == .fail } }
}

/// SPF, DKIM, DMARC (plus MX, MTA-STS and TLS-RPT) for a domain: records looked up, parsed and
/// judged, with the findings-ready explanation.
@Observable
final class MailSecurityCheck {
    static let shared = MailSecurityCheck()

    static let defaultSelectors = ["default", "selector1", "selector2", "google", "dkim", "mail", "k1", "k2", "k3", "s1", "s2", "smtp", "mx", "email", "mandrill", "mailjet", "sendgrid", "amazonses", "zendesk1", "zendesk2", "hs1", "hs2", "krs", "pm", "mimecast20230622", "everlytickey1", "fm1", "fm2", "protonmail", "protonmail2", "protonmail3"]

    var domain: String = ""
    var selectors: String = ""
    var isRunning = false
    var result: MailSecurityResult?
    var error: String?

    func run() {
        let domain = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
            .split(separator: "/").first.map(String.init) ?? ""
        guard !domain.isEmpty, domain.contains(".") else {
            error = "Enter a domain, e.g. example.com."
            return
        }
        let extraSelectors = selectors.split(whereSeparator: { $0 == "," || $0.isWhitespace }).map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        isRunning = true
        error = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let result = MailSecurityCheck.check(domain: domain, extraSelectors: extraSelectors)
            DispatchQueue.main.async {
                self.result = result
                self.isRunning = false
                ActivityLog.shared.record(.action, "Mail security check for \(domain): \(result.problems.count) issue(s)", source: "Tools")
            }
        }
    }

    // MARK: - The check

    static func check(domain: String, extraSelectors: [String]) -> MailSecurityResult {
        var result = MailSecurityResult(domain: domain, checkedAt: Date())
        var items: [MailCheckItem] = []

        // MX
        result.mx = DNS.mx(domain)
        if result.mx.isEmpty {
            items.append(MailCheckItem(level: .info, text: "No MX records: the domain does not receive mail (SPF/DMARC still matter against spoofing of the sender)."))
        } else {
            items.append(MailCheckItem(level: .pass, text: "MX: " + result.mx.map { "\($0.host) (\($0.priority))" }.joined(separator: ", ")))
        }

        // SPF
        let txt = DNS.txt(domain)
        result.spfRecords = txt.filter { $0.lowercased().hasPrefix("v=spf1") }
        if result.spfRecords.isEmpty {
            items.append(MailCheckItem(level: .fail, text: "No SPF record: anyone can send mail as @\(domain) and receivers cannot tell."))
        } else if result.spfRecords.count > 1 {
            items.append(MailCheckItem(level: .fail, text: "\(result.spfRecords.count) SPF records — more than one is a permanent error (permerror): receivers treat it as no SPF."))
        } else {
            let spf = result.spfRecords[0]
            let analysis = analyzeSPF(spf, domain: domain)
            result.spfLookups = analysis.lookups
            result.spfExpanded = analysis.expanded
            items.append(contentsOf: analysis.items)
        }

        // DMARC
        let dmarcRecords = DNS.txt("_dmarc.\(domain)").filter { $0.lowercased().hasPrefix("v=dmarc1") }
        if dmarcRecords.isEmpty {
            items.append(MailCheckItem(level: .fail, text: "No DMARC record at _dmarc.\(domain): spoofed mail is neither rejected nor reported."))
        } else if dmarcRecords.count > 1 {
            result.dmarcRecord = dmarcRecords[0]
            items.append(MailCheckItem(level: .fail, text: "\(dmarcRecords.count) DMARC records — receivers ignore DMARC when there is more than one."))
        } else {
            result.dmarcRecord = dmarcRecords[0]
            items.append(contentsOf: analyzeDMARC(dmarcRecords[0], domain: domain))
        }

        // DKIM
        var selectors = extraSelectors
        for selector in defaultSelectors where !selectors.contains(selector) { selectors.append(selector) }
        result.selectorsTried = selectors
        for selector in selectors {
            let records = DNS.txt("\(selector)._domainkey.\(domain)").filter { $0.lowercased().contains("p=") || $0.lowercased().hasPrefix("v=dkim1") }
            guard let record = records.first else { continue }
            let bits = dkimKeyBits(record)
            result.dkim.append((selector, record, bits))
        }
        if result.dkim.isEmpty {
            items.append(MailCheckItem(level: .info, text: "No DKIM key found for \(selectors.count) common selectors — the real selector may differ (look at a mail's DKIM-Signature header: s=…) or DKIM is not used."))
        } else {
            for key in result.dkim {
                let lower = key.record.lowercased().replacingOccurrences(of: " ", with: "")
                if lower.contains("p=;") || lower.hasSuffix("p=") {
                    items.append(MailCheckItem(level: .info, text: "DKIM selector \(key.selector): key revoked (empty p=)."))
                } else if let bits = key.bits, bits < 2048 {
                    items.append(MailCheckItem(level: .warn, text: "DKIM selector \(key.selector): \(bits)-bit RSA key — 1024-bit keys are considered weak; use 2048."))
                } else {
                    items.append(MailCheckItem(level: .pass, text: "DKIM selector \(key.selector): key present\(key.bits.map { " (\($0)-bit)" } ?? "")\(lower.contains("t=y") ? " — testing mode (t=y)" : "")."))
                }
                if lower.contains("t=y") {
                    items.append(MailCheckItem(level: .warn, text: "DKIM selector \(key.selector) is in testing mode (t=y): receivers may ignore failures."))
                }
            }
        }

        // MTA-STS and TLS-RPT
        let sts = DNS.txt("_mta-sts.\(domain)").first { $0.lowercased().hasPrefix("v=stsv1") }
        result.mtaSTS = sts
        items.append(MailCheckItem(level: sts == nil ? .info : .pass,
                                   text: sts == nil ? "No MTA-STS policy (_mta-sts.\(domain)): inbound TLS is opportunistic and can be downgraded." : "MTA-STS policy published (\(sts!))."))
        let tlsrpt = DNS.txt("_smtp._tls.\(domain)").first { $0.lowercased().hasPrefix("v=tlsrpt") }
        result.tlsRPT = tlsrpt
        items.append(MailCheckItem(level: tlsrpt == nil ? .info : .pass,
                                   text: tlsrpt == nil ? "No TLS-RPT record (_smtp._tls.\(domain)): no reports about TLS failures." : "TLS-RPT: \(tlsrpt!)"))

        result.items = items
        return result
    }

    // MARK: SPF

    struct SPFAnalysis {
        var items: [MailCheckItem] = []
        var lookups = 0
        var expanded: [String] = []
    }

    static func analyzeSPF(_ record: String, domain: String) -> SPFAnalysis {
        var analysis = SPFAnalysis()
        let terms = record.split(whereSeparator: { $0.isWhitespace }).map(String.init).dropFirst()
        var allQualifier: Character? = nil
        var sawAll = false
        var usesPtr = false
        var redirect: String? = nil
        var visited: Set<String> = [domain.lowercased()]
        var lookups = 0
        var expanded: [String] = []

        func count(_ record: String, for name: String, depth: Int) {
            guard depth < 10 else { return }
            let terms = record.split(whereSeparator: { $0.isWhitespace }).map(String.init).dropFirst()
            for raw in terms {
                var term = raw
                if let first = term.first, "+-~?".contains(first) { term.removeFirst() }
                let lower = term.lowercased()
                if lower.hasPrefix("include:") || lower.hasPrefix("redirect=") {
                    lookups += 1
                    let target = String(term.dropFirst(lower.hasPrefix("include:") ? 8 : 9)).lowercased()
                    guard !visited.contains(target) else { continue }
                    visited.insert(target)
                    let records = DNS.txt(target).filter { $0.lowercased().hasPrefix("v=spf1") }
                    if let child = records.first {
                        expanded.append("\(target): \(child)")
                        count(child, for: target, depth: depth + 1)
                    } else {
                        expanded.append("\(target): no SPF record (include fails → permerror)")
                        analysis.items.append(MailCheckItem(level: .fail, text: "include:\(target) has no SPF record — the whole SPF evaluation becomes a permanent error."))
                    }
                } else if lower == "a" || lower.hasPrefix("a:") || lower.hasPrefix("a/") || lower == "mx" || lower.hasPrefix("mx:") || lower.hasPrefix("mx/") || lower.hasPrefix("exists:") {
                    lookups += 1
                } else if lower == "ptr" || lower.hasPrefix("ptr:") {
                    lookups += 1
                    usesPtr = true
                }
            }
        }
        count(record, for: domain, depth: 0)

        for raw in terms {
            var term = raw
            var qualifier: Character = "+"
            if let first = term.first, "+-~?".contains(first) { qualifier = first; term.removeFirst() }
            let lower = term.lowercased()
            if lower == "all" {
                sawAll = true
                allQualifier = qualifier
            } else if lower.hasPrefix("redirect=") {
                redirect = String(term.dropFirst(9))
            }
        }

        analysis.lookups = lookups
        analysis.expanded = expanded
        analysis.items.insert(MailCheckItem(level: .pass, text: "SPF: \(record)"), at: 0)
        if lookups > 10 {
            analysis.items.append(MailCheckItem(level: .fail, text: "SPF needs \(lookups) DNS lookups — the limit is 10; receivers return permerror and ignore SPF."))
        } else if lookups >= 8 {
            analysis.items.append(MailCheckItem(level: .warn, text: "SPF uses \(lookups) of the 10 allowed DNS lookups — little room left."))
        } else {
            analysis.items.append(MailCheckItem(level: .pass, text: "SPF DNS lookups: \(lookups) of 10."))
        }
        if usesPtr {
            analysis.items.append(MailCheckItem(level: .warn, text: "SPF uses the ptr mechanism — deprecated, slow and unreliable."))
        }
        if sawAll, let qualifier = allQualifier {
            switch qualifier {
            case "-": analysis.items.append(MailCheckItem(level: .pass, text: "SPF ends in -all (hard fail): unlisted senders are rejected."))
            case "~": analysis.items.append(MailCheckItem(level: .info, text: "SPF ends in ~all (soft fail): unlisted senders are only marked; fine with DMARC p=reject, weak without."))
            case "?": analysis.items.append(MailCheckItem(level: .warn, text: "SPF ends in ?all (neutral): says nothing about unlisted senders — effectively no protection."))
            default: analysis.items.append(MailCheckItem(level: .fail, text: "SPF ends in +all: every sender on the internet passes SPF for \(domain)."))
            }
        } else if let redirect {
            analysis.items.append(MailCheckItem(level: .info, text: "SPF redirects to \(redirect); the all mechanism of that record applies."))
        } else {
            analysis.items.append(MailCheckItem(level: .warn, text: "SPF has no all mechanism: unlisted senders get a neutral result."))
        }
        if record.count > 450 {
            analysis.items.append(MailCheckItem(level: .info, text: "SPF record is \(record.count) characters long; records above 512 bytes can fail over UDP."))
        }
        return analysis
    }

    // MARK: DMARC

    static func analyzeDMARC(_ record: String, domain: String) -> [MailCheckItem] {
        var items: [MailCheckItem] = [MailCheckItem(level: .pass, text: "DMARC: \(record)")]
        var tags: [String: String] = [:]
        for part in record.split(separator: ";") {
            let pair = part.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if pair.count == 2 { tags[pair[0].lowercased()] = pair[1] }
        }
        let policy = tags["p"]?.lowercased() ?? ""
        switch policy {
        case "reject": items.append(MailCheckItem(level: .pass, text: "DMARC policy p=reject: spoofed mail is rejected."))
        case "quarantine": items.append(MailCheckItem(level: .info, text: "DMARC policy p=quarantine: spoofed mail goes to spam; reject is the stronger end state."))
        case "none": items.append(MailCheckItem(level: .fail, text: "DMARC policy p=none: monitoring only — spoofed mail is delivered as usual."))
        default: items.append(MailCheckItem(level: .fail, text: "DMARC record without a valid p= policy tag — the record is invalid."))
        }
        if let pct = tags["pct"], let value = Int(pct), value < 100 {
            items.append(MailCheckItem(level: .warn, text: "DMARC pct=\(value): the policy applies to only \(value)% of failing mail."))
        }
        if let sp = tags["sp"]?.lowercased() {
            if sp == "none" { items.append(MailCheckItem(level: .warn, text: "DMARC sp=none: subdomains of \(domain) are not protected (anything@sub.\(domain) can be spoofed).")) }
        } else if policy == "reject" || policy == "quarantine" {
            items.append(MailCheckItem(level: .pass, text: "Subdomains inherit the policy (no sp= tag)."))
        }
        if tags["rua"] == nil {
            items.append(MailCheckItem(level: .warn, text: "No rua= address: nobody receives aggregate reports, so abuse goes unnoticed."))
        } else {
            items.append(MailCheckItem(level: .pass, text: "Aggregate reports go to \(tags["rua"] ?? "")."))
        }
        if tags["adkim"]?.lowercased() == "s" || tags["aspf"]?.lowercased() == "s" {
            items.append(MailCheckItem(level: .info, text: "Strict alignment (adkim/aspf=s): subdomain senders must match exactly."))
        }
        return items
    }

    // MARK: DKIM

    /// RSA modulus size from the p= value: the SubjectPublicKeyInfo length is a reliable tell.
    static func dkimKeyBits(_ record: String) -> Int? {
        guard let range = record.range(of: "p=") else { return nil }
        var value = String(record[range.upperBound...])
        if let end = value.firstIndex(of: ";") { value = String(value[..<end]) }
        value = value.filter { !$0.isWhitespace }
        guard !value.isEmpty, let data = Base64.decodeLenient(value) else { return nil }
        // Walk the DER: SEQUENCE { SEQUENCE { OID, NULL }, BIT STRING { SEQUENCE { INTEGER modulus, INTEGER exponent } } }
        let bytes = [UInt8](data)
        func length(at index: inout Int) -> Int? {
            guard index < bytes.count else { return nil }
            let first = Int(bytes[index]); index += 1
            if first < 0x80 { return first }
            let count = first & 0x7F
            guard count <= 4, index + count <= bytes.count else { return nil }
            var value = 0
            for _ in 0..<count { value = value << 8 | Int(bytes[index]); index += 1 }
            return value
        }
        var index = 0
        guard index < bytes.count, bytes[index] == 0x30 else { return approximateBits(data.count) }
        index += 1
        _ = length(at: &index)
        // AlgorithmIdentifier
        guard index < bytes.count, bytes[index] == 0x30 else { return approximateBits(data.count) }
        index += 1
        guard let algorithmLength = length(at: &index) else { return approximateBits(data.count) }
        index += algorithmLength
        // BIT STRING
        guard index < bytes.count, bytes[index] == 0x03 else { return approximateBits(data.count) }
        index += 1
        _ = length(at: &index)
        index += 1 // unused bits
        guard index < bytes.count, bytes[index] == 0x30 else { return approximateBits(data.count) }
        index += 1
        _ = length(at: &index)
        guard index < bytes.count, bytes[index] == 0x02 else { return approximateBits(data.count) }
        index += 1
        guard var modulusLength = length(at: &index) else { return approximateBits(data.count) }
        if index < bytes.count, bytes[index] == 0 { modulusLength -= 1 }
        return modulusLength * 8
    }

    private static func approximateBits(_ byteCount: Int) -> Int? {
        switch byteCount {
        case 0..<200: return 1024
        case 200..<400: return 2048
        case 400..<700: return 4096
        default: return nil
        }
    }

    // MARK: - Report

    static func markdown(_ result: MailSecurityResult) -> String {
        var out = "## Mail security — \(result.domain)\n\n_Checked \(result.checkedAt.formatted(date: .abbreviated, time: .shortened))_\n\n"
        for item in result.items {
            let mark: String
            switch item.level {
            case .pass: mark = "✅"
            case .info: mark = "ℹ️"
            case .warn: mark = "⚠️"
            case .fail: mark = "❌"
            }
            out += "- \(mark) \(item.text)\n"
        }
        if !result.spfExpanded.isEmpty {
            out += "\n**SPF includes**\n\n" + result.spfExpanded.map { "- `\($0)`" }.joined(separator: "\n") + "\n"
        }
        if !result.dkim.isEmpty {
            out += "\n**DKIM keys**\n\n" + result.dkim.map { "- `\($0.selector)._domainkey.\(result.domain)`: \($0.bits.map { "\($0)-bit" } ?? "key present")" }.joined(separator: "\n") + "\n"
        }
        return out
    }
}
