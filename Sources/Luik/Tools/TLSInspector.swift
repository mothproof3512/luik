import AppKit
import Foundation
import Observation
import SwiftUI

/// Tools › Certificates: everything a TLS endpoint's certificate chain tells you — names,
/// organisation, issuer, validity, serials, fingerprints, key usage, OCSP/CRL/CA URLs,
/// policies (DV/OV/EV), CT timestamps — plus the handshake facts (negotiated version and
/// cipher) as information, and the names that Certificate Transparency logs know for the
/// domain. It is an OSINT and documentation tool: it does not probe for weak protocols or
/// ciphers (testssl.sh does that properly); one handshake with the system's openssl.
struct TLSCertificate: Identifiable {
    let id = UUID()
    var subject = ""
    var issuer = ""
    var serial = ""
    var version = ""
    var notBefore: Date?
    var notAfter: Date?
    var sans: [String] = []
    var keyBits: Int?
    var keyType = ""
    var signatureAlgorithm = ""
    var fingerprintSHA256 = ""
    var fingerprintSHA1 = ""
    var keyUsage = ""
    var extendedKeyUsage = ""
    var ocspURLs: [String] = []
    var caIssuerURLs: [String] = []
    var crlURLs: [String] = []
    var policies: [String] = []
    var sctCount = 0
    var subjectKeyID = ""
    var authorityKeyID = ""
    var isCA = false
    var pem = ""

    /// One field of a distinguished name ("CN", "O", "OU", "L", "ST", "C").
    static func field(_ name: String, in dn: String) -> String? {
        for part in dn.components(separatedBy: ", ") {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(name + " = ") { return String(trimmed.dropFirst(name.count + 3)) }
            if trimmed.hasPrefix(name + "=") { return String(trimmed.dropFirst(name.count + 1)) }
        }
        return nil
    }

    var commonName: String { TLSCertificate.field("CN", in: subject) ?? subject }
    var organisation: String? { TLSCertificate.field("O", in: subject) }
    var issuerName: String { TLSCertificate.field("CN", in: issuer) ?? issuer }
    var issuerOrganisation: String? { TLSCertificate.field("O", in: issuer) }
    var isSelfSigned: Bool { !subject.isEmpty && subject == issuer }
    var daysLeft: Int? { notAfter.map { Int($0.timeIntervalSinceNow / 86400) } }
    var lifetimeDays: Int? {
        guard let notBefore, let notAfter else { return nil }
        return Int(notAfter.timeIntervalSince(notBefore) / 86400)
    }

    /// DV / OV / EV / IV from the CA/Browser Forum policy OIDs, when present.
    var validationLevel: String? {
        for policy in policies {
            if policy.hasPrefix("2.23.140.1.1") { return "EV (extended validation)" }
            if policy.hasPrefix("2.23.140.1.2.1") { return "DV (domain validated)" }
            if policy.hasPrefix("2.23.140.1.2.2") { return "OV (organisation validated)" }
            if policy.hasPrefix("2.23.140.1.2.3") { return "IV (individual validated)" }
            if policy.hasPrefix("2.23.140.1.3") { return "EV code signing" }
        }
        if !policies.isEmpty && organisation == nil { return "DV (no organisation in the subject)" }
        if !policies.isEmpty && organisation != nil { return "OV/EV (organisation in the subject)" }
        return nil
    }

    var wildcardNames: [String] { sans.filter { $0.hasPrefix("*.") } }
}

/// A name seen in Certificate Transparency logs for the domain.
struct CTEntry: Identifiable, Hashable {
    var id: String { name }
    var name: String
    var issuers: Set<String>
    var first: String
    var last: String
    var count: Int
}

struct TLSResult {
    var host: String
    var port: Int
    var starttls: String
    var checkedAt: Date
    var reachable = true
    var negotiatedProtocol = ""
    var negotiatedCipher = ""
    var tempKey = ""
    var verifyCode = ""
    var alpn = ""
    var chain: [TLSCertificate] = []
    var items: [CheckItem] = []
    var raw = ""
    /// All DNS names in the chain's leaf (SANs), de-duplicated, wildcards last.
    var names: [String] {
        guard let leaf = chain.first else { return [] }
        let plain = leaf.sans.filter { !$0.hasPrefix("*.") }
        return Array(NSOrderedSet(array: plain + leaf.wildcardNames)) as? [String] ?? leaf.sans
    }
    /// The registrable-ish domain for the CT search (last two labels; three for co.uk-style).
    var baseDomain: String? {
        guard let leaf = chain.first else { return nil }
        let candidates = leaf.sans.map { $0.hasPrefix("*.") ? String($0.dropFirst(2)) : $0 } + [host]
        for name in candidates where !DNSLookup.isIPAddress(name) {
            let labels = name.split(separator: ".").map(String.init)
            guard labels.count >= 2 else { continue }
            let secondLevel = ["co", "com", "org", "net", "gov", "ac", "edu"]
            if labels.count >= 3, secondLevel.contains(labels[labels.count - 2]), labels.last!.count == 2 {
                return labels.suffix(3).joined(separator: ".")
            }
            return labels.suffix(2).joined(separator: ".")
        }
        return nil
    }
    var problems: [CheckItem] { items.filter { $0.level == .warn || $0.level == .fail } }
    var endpoint: String { "\(host):\(port)" }
}

@Observable
final class TLSInspector {
    static let shared = TLSInspector()

    static let starttlsOptions = ["none", "smtp", "imap", "pop3", "ftp", "ldap", "postgres", "mysql", "xmpp"]
    static let openssl = "/usr/bin/openssl"

    var target = ""
    var starttls = "none"
    var isRunning = false
    var result: TLSResult?
    var error: String?
    /// Certificate Transparency (crt.sh) — on request only, it is a query to a third party.
    var ctEntries: [CTEntry] = []
    var ctDomain = ""
    var ctLoading = false
    var ctError: String?

    func run() {
        var text = target.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["https://", "http://", "ldaps://", "smtps://"] where text.lowercased().hasPrefix(prefix) { text = String(text.dropFirst(prefix.count)) }
        text = text.split(separator: "/").first.map(String.init) ?? text
        var host = text
        var port = starttls == "none" ? 443 : (["smtp": 25, "imap": 143, "pop3": 110, "ftp": 21, "ldap": 389, "postgres": 5432, "mysql": 3306, "xmpp": 5222][starttls] ?? 443)
        if let colon = text.lastIndex(of: ":"), !text.hasPrefix("[") || text.contains("]:") {
            let portText = text[text.index(after: colon)...]
            if let number = Int(portText) { port = number; host = String(text[..<colon]) }
        }
        host = host.replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "")
        guard !host.isEmpty else { error = "Enter a host, e.g. www.example.com or 203.0.113.10:8443."; return }
        guard FileManager.default.isExecutableFile(atPath: TLSInspector.openssl) else { error = "\(TLSInspector.openssl) is not available."; return }
        isRunning = true
        error = nil
        ctEntries = []
        ctError = nil
        let starttls = self.starttls
        DispatchQueue.global(qos: .userInitiated).async {
            let result = TLSInspector.inspect(host: host, port: port, starttls: starttls)
            DispatchQueue.main.async {
                self.result = result
                self.isRunning = false
                if !result.reachable { self.error = "No TLS handshake with \(result.endpoint) — closed port, no TLS there, or a timeout." }
                ActivityLog.shared.record(.action, "Certificate read from \(result.endpoint): \(result.chain.first?.commonName ?? "—"), \(result.chain.count) certificate(s), \(result.names.count) name(s)", source: "Tools", host: host)
            }
        }
    }

    /// crt.sh: every certificate CT logs hold for `%.domain` → the names, with issuer and dates.
    func queryCertificateTransparency(domain: String) {
        let domain = domain.trimmingCharacters(in: .whitespaces).lowercased()
        guard !domain.isEmpty, let url = URL(string: "https://crt.sh/?q=%25.\(domain)&output=json") else { return }
        ctLoading = true
        ctError = nil
        ctDomain = domain
        var request = URLRequest(url: url)
        request.timeoutInterval = 40
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { data, response, error in
            var entries: [CTEntry] = []
            var failure: String?
            if let error {
                failure = error.localizedDescription
            } else if let data, let rows = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] {
                var byName: [String: CTEntry] = [:]
                for row in rows {
                    let issuer = (row["issuer_name"] as? String).flatMap { TLSCertificate.field("O", in: $0) ?? TLSCertificate.field("CN", in: $0) } ?? "?"
                    let before = String(((row["not_before"] as? String) ?? "").prefix(10))
                    let after = String(((row["not_after"] as? String) ?? "").prefix(10))
                    let names = ((row["name_value"] as? String) ?? "").components(separatedBy: "\n")
                    for raw in names {
                        let name = raw.trimmingCharacters(in: .whitespaces).lowercased()
                        guard !name.isEmpty else { continue }
                        if var entry = byName[name] {
                            entry.issuers.insert(issuer)
                            entry.first = min(entry.first, before)
                            entry.last = max(entry.last, after)
                            entry.count += 1
                            byName[name] = entry
                        } else {
                            byName[name] = CTEntry(name: name, issuers: [issuer], first: before, last: after, count: 1)
                        }
                    }
                }
                entries = byName.values.sorted { $0.name.split(separator: ".").reversed().joined(separator: ".") < $1.name.split(separator: ".").reversed().joined(separator: ".") }
            } else if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                failure = "crt.sh answered HTTP \(http.statusCode) (it rate-limits; try again in a minute)."
            } else {
                failure = "crt.sh gave no usable answer (it is often slow; try again)."
            }
            DispatchQueue.main.async {
                self.ctEntries = entries
                self.ctError = failure
                self.ctLoading = false
                if failure == nil { ActivityLog.shared.record(.action, "Certificate Transparency: \(entries.count) name(s) for %.\(domain) (crt.sh)", source: "Tools") }
            }
        }.resume()
    }

    // MARK: - Reading the chain

    private static func sclient(host: String, port: Int, starttls: String, extra: [String]) -> String {
        var arguments = ["s_client", "-connect", "\(host):\(port)", "-servername", host, "-showcerts"]
        if starttls != "none" { arguments += ["-starttls", starttls] }
        if starttls == "none" { arguments += ["-alpn", "h2,http/1.1"] }
        arguments += extra
        return ShellTool.run(openssl, arguments, input: "", timeout: 12)
    }

    static func value(_ label: String, in text: String) -> String {
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(label) {
                let rest = trimmed.dropFirst(label.count)
                if let colon = rest.firstIndex(of: ":") { return rest[rest.index(after: colon)...].trimmingCharacters(in: .whitespaces) }
                return rest.trimmingCharacters(in: .whitespaces)
            }
        }
        return ""
    }

    static func pemBlocks(in text: String) -> [String] {
        var blocks: [String] = []
        var current: [String] = []
        var inside = false
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("-----BEGIN CERTIFICATE-----") { inside = true; current = [line]; continue }
            if line.hasPrefix("-----END CERTIFICATE-----") { current.append(line); blocks.append(current.joined(separator: "\n")); inside = false; continue }
            if inside { current.append(line) }
        }
        return blocks
    }

    /// Parses `openssl x509 -text` output (plus the two fingerprint runs) into a TLSCertificate.
    static func parseCertificate(pem: String) -> TLSCertificate {
        let text = ShellTool.run(openssl, ["x509", "-noout", "-text", "-fingerprint", "-sha256"], input: pem + "\n", timeout: 6)
        var cert = parseCertificateText(text)
        cert.pem = pem
        let sha1 = ShellTool.run(openssl, ["x509", "-noout", "-fingerprint", "-sha1"], input: pem + "\n", timeout: 6)
        if let line = sha1.components(separatedBy: "\n").first(where: { $0.lowercased().contains("fingerprint=") }), let equals = line.firstIndex(of: "=") {
            cert.fingerprintSHA1 = String(line[line.index(after: equals)...])
        }
        return cert
    }

    /// Pure parser for `x509 -text` output; testable with captured text.
    static func parseCertificateText(_ text: String) -> TLSCertificate {
        var cert = TLSCertificate()
        let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "MMM d HH:mm:ss yyyy zzz"
        func date(_ text: String) -> Date? {
            formatter.date(from: text.replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespaces))
        }
        func after(_ label: String, _ line: String) -> String { String(line.dropFirst(label.count)).trimmingCharacters(in: .whitespaces) }
        var sawSignatureAlgorithm = false
        var section = ""   // which multi-line extension we are inside
        for (index, line) in lines.enumerated() {
            if line.hasPrefix("X509v3 ") || line.hasPrefix("CT Precertificate") || line.hasPrefix("Authority Information Access") || line.hasPrefix("Signature Algorithm") || line.hasPrefix("Signature Value") {
                section = line
            }
            if line.hasPrefix("Version:") { cert.version = after("Version:", line) }
            else if line.hasPrefix("Serial Number:") {
                let inline = after("Serial Number:", line)
                cert.serial = inline.isEmpty && index + 1 < lines.count ? lines[index + 1] : inline
            }
            else if line.hasPrefix("Subject:") { cert.subject = after("Subject:", line) }
            else if line.hasPrefix("Issuer:") { cert.issuer = after("Issuer:", line) }
            else if line.hasPrefix("Not Before:") { cert.notBefore = date(after("Not Before:", line)) }
            else if line.hasPrefix("Not After") { cert.notAfter = date(String(line.drop(while: { $0 != ":" }).dropFirst())) }
            else if line.hasPrefix("Public-Key:") || line.hasPrefix("RSA Public-Key:") || line.hasPrefix("Public Key:") { cert.keyBits = Int(line.filter { $0.isNumber }) }
            else if line.hasPrefix("Public Key Algorithm:") { cert.keyType = after("Public Key Algorithm:", line) }
            else if line.hasPrefix("ASN1 OID:") || line.hasPrefix("NIST CURVE:") { cert.keyType += " " + String(line.drop(while: { $0 != ":" }).dropFirst()).trimmingCharacters(in: .whitespaces) }
            else if line.hasPrefix("Signature Algorithm:") && !sawSignatureAlgorithm { cert.signatureAlgorithm = after("Signature Algorithm:", line); sawSignatureAlgorithm = true }
            else if line.hasPrefix("X509v3 Subject Alternative Name"), index + 1 < lines.count {
                cert.sans = lines[index + 1].components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    .compactMap { $0.hasPrefix("DNS:") ? String($0.dropFirst(4)) : ($0.hasPrefix("IP Address:") ? String($0.dropFirst(11)) : nil) }
            }
            else if line.hasPrefix("X509v3 Key Usage"), index + 1 < lines.count { cert.keyUsage = lines[index + 1] }
            else if line.hasPrefix("X509v3 Extended Key Usage"), index + 1 < lines.count { cert.extendedKeyUsage = lines[index + 1] }
            else if line.hasPrefix("X509v3 Subject Key Identifier"), index + 1 < lines.count { cert.subjectKeyID = lines[index + 1] }
            else if line.hasPrefix("X509v3 Authority Key Identifier"), index + 1 < lines.count { cert.authorityKeyID = lines[index + 1].replacingOccurrences(of: "keyid:", with: "") }
            else if line.hasPrefix("X509v3 Basic Constraints"), index + 1 < lines.count { cert.isCA = lines[index + 1].contains("CA:TRUE") }
            else if line.hasPrefix("OCSP - URI:") { cert.ocspURLs.append(after("OCSP - URI:", line)) }
            else if line.hasPrefix("CA Issuers - URI:") { cert.caIssuerURLs.append(after("CA Issuers - URI:", line)) }
            else if line.hasPrefix("URI:"), section.hasPrefix("X509v3 CRL Distribution Points") { cert.crlURLs.append(after("URI:", line)) }
            else if line.hasPrefix("Policy:"), section.hasPrefix("X509v3 Certificate Policies") { cert.policies.append(after("Policy:", line)) }
            else if line.hasPrefix("Signed Certificate Timestamp"), section.hasPrefix("CT Precertificate") { cert.sctCount += 1 }
            else if line.hasPrefix("SHA256 Fingerprint=") || line.hasPrefix("sha256 Fingerprint=") { cert.fingerprintSHA256 = String(line.drop(while: { $0 != "=" }).dropFirst()) }
        }
        if cert.keyType.isEmpty, let bits = cert.keyBits { cert.keyType = "\(bits)-bit" }
        return cert
    }

    static func matches(host: String, san: String) -> Bool {
        let host = host.lowercased()
        let san = san.lowercased()
        if san == host { return true }
        if san.hasPrefix("*.") {
            let suffix = san.dropFirst(1)
            guard host.hasSuffix(suffix) else { return false }
            let label = host.dropLast(suffix.count)
            return !label.isEmpty && !label.contains(".")
        }
        return false
    }

    static func inspect(host: String, port: Int, starttls: String) -> TLSResult {
        var result = TLSResult(host: host, port: port, starttls: starttls, checkedAt: Date())
        var items: [CheckItem] = []
        let main = sclient(host: host, port: port, starttls: starttls, extra: [])
        result.raw = main
        guard TLSProbe.localProblem(main) == nil, TLSProbe.negotiatedCipher(main) != nil else {
            result.reachable = false
            result.items = [CheckItem(level: .info, text: "No TLS handshake with \(host):\(port).")]
            return result
        }
        result.negotiatedProtocol = TLSProbe.negotiatedProtocol(main) ?? ""
        result.negotiatedCipher = TLSProbe.negotiatedCipher(main) ?? ""
        result.tempKey = value("Server Temp Key", in: main)
        result.verifyCode = value("Verify return code", in: main)
        result.alpn = value("ALPN protocol", in: main)
        result.chain = pemBlocks(in: main).map(parseCertificate)

        guard let leaf = result.chain.first else {
            result.items = [CheckItem(level: .warn, text: "No certificate could be read from the handshake.")]
            return result
        }
        let isIP = DNSLookup.isIPAddress(host)

        // Facts that are findings on their own (no probing involved).
        let nameOK = leaf.sans.contains { matches(host: host, san: $0) } || (leaf.sans.isEmpty && matches(host: host, san: leaf.commonName))
        if isIP {
            items.append(CheckItem(level: .info, text: "Connected by address; the certificate is issued for \(leaf.sans.prefix(5).joined(separator: ", "))\(leaf.sans.count > 5 ? " (+\(leaf.sans.count - 5))" : "") — that is the name the service is meant to be reached by."))
        } else if nameOK {
            items.append(CheckItem(level: .pass, text: "Certificate covers \(host) (\(leaf.sans.count) name\(leaf.sans.count == 1 ? "" : "s") in total)."))
        } else {
            items.append(CheckItem(level: .fail, text: "Name mismatch: \(host) is not among the certificate's names (\(leaf.sans.isEmpty ? leaf.commonName : leaf.sans.prefix(5).joined(separator: ", "))) — wrong vhost, default certificate, or a reused one."))
        }
        if let days = leaf.daysLeft, let notAfter = leaf.notAfter {
            if days < 0 {
                items.append(CheckItem(level: .fail, text: "Expired \(-days) day(s) ago (\(notAfter.formatted(date: .abbreviated, time: .omitted)))."))
            } else if days < 30 {
                items.append(CheckItem(level: .warn, text: "Expires in \(days) day(s) (\(notAfter.formatted(date: .abbreviated, time: .omitted)))."))
            } else {
                items.append(CheckItem(level: .pass, text: "Valid until \(notAfter.formatted(date: .abbreviated, time: .omitted)) (\(days) days)\(leaf.lifetimeDays.map { " · lifetime \($0) days" } ?? "")."))
            }
        }
        if leaf.isSelfSigned {
            items.append(CheckItem(level: .warn, text: "Self-signed certificate (\(leaf.commonName)) — internal or forgotten system; users click through warnings here."))
        } else if result.verifyCode.hasPrefix("0") {
            items.append(CheckItem(level: .pass, text: "Chain verifies against this Mac's trust store · issued by \(leaf.issuerOrganisation ?? leaf.issuerName) (\(leaf.issuerName))."))
        } else if !result.verifyCode.isEmpty {
            items.append(CheckItem(level: .warn, text: "Chain does not verify here: \(result.verifyCode) — internal CA, untrusted root or an incomplete chain (\(result.chain.count) certificate(s) sent)."))
        }
        if result.chain.count > 1, let last = result.chain.last, last.isSelfSigned {
            items.append(CheckItem(level: .info, text: "Root CA included in the chain (\(last.commonName)) — unnecessary; some Java clients reject chains that end in the root."))
        }
        if let level = leaf.validationLevel { items.append(CheckItem(level: .info, text: "Validation level: \(level)\(leaf.organisation.map { " · organisation “\($0)”" } ?? "").")) }
        if let org = leaf.organisation, !org.isEmpty {
            items.append(CheckItem(level: .info, text: "Subject organisation “\(org)”\(TLSCertificate.field("L", in: leaf.subject).map { ", \($0)" } ?? "")\(TLSCertificate.field("C", in: leaf.subject).map { " (\($0))" } ?? "") — confirms who operates the service."))
        }
        if !leaf.wildcardNames.isEmpty {
            items.append(CheckItem(level: .info, text: "Wildcard name\(leaf.wildcardNames.count == 1 ? "" : "s") \(leaf.wildcardNames.joined(separator: ", ")) — one key for every subdomain; worth noting for the report."))
        }
        let otherNames = leaf.sans.filter { !matches(host: host, san: $0) && $0 != host }
        if otherNames.count >= 1 {
            items.append(CheckItem(level: .info, text: "\(otherNames.count) other name\(otherNames.count == 1 ? "" : "s") on this certificate (\(otherNames.prefix(6).joined(separator: ", "))\(otherNames.count > 6 ? ", …" : "")) — related hosts, often on the same system; Add names to Targets below."))
        }
        if leaf.sctCount > 0 {
            items.append(CheckItem(level: .info, text: "\(leaf.sctCount) Certificate Transparency timestamp\(leaf.sctCount == 1 ? "" : "s") embedded — the certificate is public; crt.sh lists the siblings (button below)."))
        } else if !leaf.isSelfSigned && result.verifyCode.hasPrefix("0") {
            items.append(CheckItem(level: .info, text: "No CT timestamps embedded (older or privately logged certificate)."))
        }
        if let bits = leaf.keyBits {
            let rsa = leaf.keyType.lowercased().contains("rsa")
            if rsa && bits < 2048 {
                items.append(CheckItem(level: .fail, text: "\(bits)-bit RSA key — below the 2048-bit minimum."))
            } else {
                items.append(CheckItem(level: .pass, text: "Key \(leaf.keyType), \(bits) bit · signature \(leaf.signatureAlgorithm)."))
            }
        }
        let signature = leaf.signatureAlgorithm.lowercased()
        if signature.contains("sha1") || signature.contains("md5") {
            items.append(CheckItem(level: .fail, text: "Signed with \(leaf.signatureAlgorithm) — SHA-1/MD5 signatures are deprecated."))
        }
        if leaf.ocspURLs.isEmpty && leaf.crlURLs.isEmpty && !leaf.isSelfSigned {
            items.append(CheckItem(level: .info, text: "No OCSP or CRL URL: revocation cannot be checked."))
        }
        if leaf.isCA {
            items.append(CheckItem(level: .warn, text: "The server certificate is a CA certificate (CA:TRUE) — misissued or a test setup."))
        }
        let lowerIssuer = (leaf.issuerOrganisation ?? leaf.issuerName).lowercased()
        if lowerIssuer.contains("let's encrypt") || lowerIssuer.contains("zerossl") || lowerIssuer.contains("buypass") || lowerIssuer.contains("google trust services") {
            items.append(CheckItem(level: .info, text: "Automated (ACME) certificate from \(leaf.issuerOrganisation ?? leaf.issuerName) — DV, renewed every ~60–90 days; CT history shows how long the name has existed."))
        }
        items.append(CheckItem(level: .info, text: "Handshake: \(result.negotiatedProtocol) · \(result.negotiatedCipher)\(result.tempKey.isEmpty ? "" : " · key exchange \(result.tempKey)")\(result.alpn.isEmpty ? "" : " · ALPN \(result.alpn)") — one handshake with this openssl; for protocol and cipher weaknesses run testssl.sh."))
        result.items = items.sorted { $0.level.rawValue > $1.level.rawValue }
        return result
    }

    static func markdown(_ result: TLSResult) -> String {
        var out = "## Certificate — \(result.endpoint)\(result.starttls == "none" ? "" : " (STARTTLS \(result.starttls))")\n\n_Read \(result.checkedAt.formatted(date: .abbreviated, time: .shortened)) · handshake \(result.negotiatedProtocol) \(result.negotiatedCipher)_\n\n"
        out += ShellTool.markdownList(result.items) + "\n\n"
        for (index, cert) in result.chain.enumerated() {
            out += "### \(index + 1). \(cert.commonName)\(cert.isCA ? " (CA)" : "")\n\n"
            out += "- Subject: \(cert.subject)\n- Issuer: \(cert.issuer)\n- Serial: \(cert.serial)\n"
            if let before = cert.notBefore, let after = cert.notAfter { out += "- Valid: \(before.formatted(date: .abbreviated, time: .omitted)) – \(after.formatted(date: .abbreviated, time: .omitted))\(cert.lifetimeDays.map { " (\($0) days)" } ?? "")\n" }
            if !cert.sans.isEmpty { out += "- Names (\(cert.sans.count)): \(cert.sans.joined(separator: ", "))\n" }
            out += "- Key: \(cert.keyType)\(cert.keyBits.map { " \($0) bit" } ?? "") · signature \(cert.signatureAlgorithm)\n"
            if !cert.keyUsage.isEmpty { out += "- Key usage: \(cert.keyUsage)\(cert.extendedKeyUsage.isEmpty ? "" : " · extended: \(cert.extendedKeyUsage)")\n" }
            if let level = cert.validationLevel { out += "- Validation: \(level)\n" }
            if !cert.policies.isEmpty { out += "- Policies: \(cert.policies.joined(separator: ", "))\n" }
            if !cert.ocspURLs.isEmpty { out += "- OCSP: \(cert.ocspURLs.joined(separator: ", "))\n" }
            if !cert.caIssuerURLs.isEmpty { out += "- CA issuers: \(cert.caIssuerURLs.joined(separator: ", "))\n" }
            if !cert.crlURLs.isEmpty { out += "- CRL: \(cert.crlURLs.joined(separator: ", "))\n" }
            if cert.sctCount > 0 { out += "- CT timestamps: \(cert.sctCount)\n" }
            out += "- SHA-256: \(cert.fingerprintSHA256)\n- SHA-1: \(cert.fingerprintSHA1)\n"
            if !cert.subjectKeyID.isEmpty { out += "- Subject key id: \(cert.subjectKeyID)\n" }
            if !cert.authorityKeyID.isEmpty { out += "- Authority key id: \(cert.authorityKeyID)\n" }
            out += "\n"
        }
        return out
    }

    static func ctMarkdown(_ entries: [CTEntry], domain: String) -> String {
        var out = "### Certificate Transparency — %.\(domain) (crt.sh, \(entries.count) names)\n\n| Name | Certificates | First | Last | Issuers |\n|---|---|---|---|---|\n"
        for entry in entries { out += "| \(entry.name) | \(entry.count) | \(entry.first) | \(entry.last) | \(entry.issuers.sorted().joined(separator: ", ")) |\n" }
        return out + "\n"
    }
}

struct TLSInspectorView: View {
    @Environment(FindingsStore.self) private var findings
    @Environment(TargetStore.self) private var targets
    @Environment(UIState.self) private var ui
    @Environment(\.luikTheme) private var theme
    @State private var showRaw = false
    @State private var expandedCerts: Set<UUID> = []

    var body: some View {
        @Bindable var inspector = TLSInspector.shared
        VStack(spacing: 0) {
            CheckToolbar(text: $inspector.target, placeholder: "host or host:port (www.example.com, 203.0.113.10:8443)", isRunning: inspector.isRunning, hasOptions: true, optionsHelp: "STARTTLS", run: { inspector.run() }) {
                Picker("STARTTLS", selection: $inspector.starttls) {
                    ForEach(TLSInspector.starttlsOptions, id: \.self) { Text($0).tag($0) }
                }
                Text("For mail, FTP, LDAP and database ports that upgrade to TLS after a plain-text greeting. The port follows the choice unless you give one.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } trailing: {
                if let result = inspector.result, result.reachable {
                    CheckResultButtons(markdown: { TLSInspector.markdown(result) + (inspector.ctEntries.isEmpty ? "" : TLSInspector.ctMarkdown(inspector.ctEntries, domain: inspector.ctDomain)) },
                                       findingTitle: result.problems.isEmpty ? nil : "Certificate problem on \(result.endpoint)",
                                       createFinding: { createFinding(result) },
                                       addToTargets: { addToTargets(result) })
                }
            }
            Divider()
            if let error = inspector.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .padding()
            }
            if let result = inspector.result, result.reachable {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Text(result.chain.first?.commonName ?? result.endpoint)
                                .font(.title2.weight(.semibold))
                            Text("\(result.endpoint) · \(result.chain.count) certificate\(result.chain.count == 1 ? "" : "s") · \(result.names.count) name\(result.names.count == 1 ? "" : "s") · \(result.problems.count) issue\(result.problems.count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(result.items) { CheckItemRow(item: $0) }

                        if !result.names.isEmpty {
                            HStack(spacing: 8) {
                                Text("Names on the certificate")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Button("Add names to Targets") { addNames(result.names, hostname: nil) }
                                    .help("One host per name that resolves; wildcards are skipped")
                                Button("Copy names") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(result.names.joined(separator: "\n"), forType: .string)
                                }
                            }
                            .controlSize(.small)
                            nameGrid(result.names)
                        }

                        certificateTransparency(result, inspector: inspector)

                        Text("Chain")
                            .font(.subheadline.weight(.semibold))
                        ForEach(Array(result.chain.enumerated()), id: \.element.id) { index, cert in
                            certificateCard(index: index, cert: cert, host: result.host)
                        }

                        DisclosureGroup(isExpanded: $showRaw) {
                            Text(result.raw)
                                .font(.system(.caption2, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(Color.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                        } label: {
                            Text("openssl s_client output")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if inspector.error == nil {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "checkmark.seal")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Enter a host (and port) and press Read: the certificate chain as OSINT — every name, organisation, issuer, validity, serials and fingerprints, key usage, OCSP/CRL/CA URLs, validation level, CT timestamps — and the names Certificate Transparency logs know for the domain.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Text("One handshake with the system's openssl. Protocol and cipher weaknesses are testssl.sh's job; this tool documents what the certificate reveals.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
        }
    }

    private func nameGrid(_ names: [String]) -> some View {
        let columns = [GridItem(.adaptive(minimum: 220), alignment: .leading)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
            ForEach(names, id: \.self) { name in
                Text(name)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(name.hasPrefix("*.") ? Color.orange : Color.primary)
                    .textSelection(.enabled)
                    .contextMenu {
                        Button("Look up in DNS & RDAP") {
                            DNSLookup.shared.query = name.hasPrefix("*.") ? String(name.dropFirst(2)) : name
                            ui.open(.dnsLookup)
                            DNSLookup.shared.run()
                        }
                        Button("Read certificate of \(name)") {
                            TLSInspector.shared.target = name.hasPrefix("*.") ? String(name.dropFirst(2)) : name
                            TLSInspector.shared.run()
                        }
                        Button("Add to Targets") { addNames([name], hostname: nil) }
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(name, forType: .string)
                        }
                    }
            }
        }
    }

    @ViewBuilder
    private func certificateTransparency(_ result: TLSResult, inspector: TLSInspector) -> some View {
        if let domain = result.baseDomain {
            HStack(spacing: 8) {
                Text("Certificate Transparency")
                    .font(.subheadline.weight(.semibold))
                Text(inspector.ctEntries.isEmpty ? "names that CT logs hold for %.\(domain)" : "\(inspector.ctEntries.count) names for %.\(inspector.ctDomain)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if inspector.ctLoading {
                    ProgressView().controlSize(.small)
                }
                Button(inspector.ctEntries.isEmpty ? "Query crt.sh" : "Query again") { inspector.queryCertificateTransparency(domain: domain) }
                    .disabled(inspector.ctLoading)
                    .help("One request to crt.sh (a third party) for every certificate ever logged for the domain — the classic subdomain-discovery source")
                if !inspector.ctEntries.isEmpty {
                    Button("Add all to Targets") { addNames(inspector.ctEntries.map { $0.name }, hostname: nil) }
                    Button("Copy names") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(inspector.ctEntries.map { $0.name }.joined(separator: "\n"), forType: .string)
                    }
                }
            }
            .controlSize(.small)
            if let error = inspector.ctError {
                Text(error).font(.caption).foregroundStyle(.orange)
            }
            if !inspector.ctEntries.isEmpty {
                VStack(spacing: 0) {
                    ForEach(inspector.ctEntries) { entry in
                        HStack(spacing: 8) {
                            Text(entry.name)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(entry.name.hasPrefix("*.") ? Color.orange : Color.primary)
                                .frame(minWidth: 260, alignment: .leading)
                                .textSelection(.enabled)
                            Text("\(entry.count)×")
                                .font(.caption2).foregroundStyle(.secondary).frame(width: 36, alignment: .trailing)
                            Text("\(entry.first) → \(entry.last)")
                                .font(.caption2).foregroundStyle(.secondary).frame(width: 170, alignment: .leading)
                            Text(entry.issuers.sorted().joined(separator: ", "))
                                .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                            Spacer()
                        }
                        .padding(.vertical, 2)
                        .contextMenu {
                            Button("Look up in DNS & RDAP") {
                                DNSLookup.shared.query = entry.name.hasPrefix("*.") ? String(entry.name.dropFirst(2)) : entry.name
                                ui.open(.dnsLookup)
                                DNSLookup.shared.run()
                            }
                            Button("Read certificate") {
                                TLSInspector.shared.target = entry.name.hasPrefix("*.") ? String(entry.name.dropFirst(2)) : entry.name
                                TLSInspector.shared.run()
                            }
                            Button("Add to Targets") { addNames([entry.name], hostname: nil) }
                        }
                    }
                }
                .padding(8)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private func certificateCard(index: Int, cert: TLSCertificate, host: String) -> some View {
        let expanded = expandedCerts.contains(cert.id) || index == 0
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Image(systemName: cert.isSelfSigned ? "seal" : (cert.isCA ? "building.columns" : "checkmark.seal"))
                    .foregroundStyle(cert.isSelfSigned ? Color.orange : Color.secondary)
                Text("\(index + 1). \(cert.commonName)")
                    .font(.callout.weight(.semibold))
                if cert.isCA { Text("CA").font(.caption2).padding(.horizontal, 5).background(Color.white.opacity(0.12), in: Capsule()) }
                if cert.isSelfSigned { Text("self-signed").font(.caption2).padding(.horizontal, 5).background(Color.orange.opacity(0.25), in: Capsule()) }
                if let days = cert.daysLeft {
                    Text(days < 0 ? "expired" : "\(days) d left")
                        .font(.caption2)
                        .foregroundStyle(days < 30 ? Color.orange : Color.secondary)
                }
                Spacer()
                Button(expanded ? "Less" : "More") {
                    if expandedCerts.contains(cert.id) { expandedCerts.remove(cert.id) } else { expandedCerts.insert(cert.id) }
                }
                .controlSize(.mini)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .opacity(index == 0 ? 0 : 1)
            }
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 2) {
                row("Subject", cert.subject)
                row("Issuer", cert.issuer)
                if expanded {
                    if let before = cert.notBefore, let after = cert.notAfter {
                        row("Valid", "\(before.formatted(date: .abbreviated, time: .shortened)) – \(after.formatted(date: .abbreviated, time: .shortened))\(cert.lifetimeDays.map { " (\($0) days)" } ?? "")")
                    }
                    row("Serial", cert.serial)
                    if !cert.sans.isEmpty { row("Names", "\(cert.sans.count): \(cert.sans.joined(separator: ", "))") }
                    row("Key", "\(cert.keyType)\(cert.keyBits.map { " \($0) bit" } ?? "") · \(cert.signatureAlgorithm)")
                    if !cert.keyUsage.isEmpty { row("Key usage", cert.keyUsage + (cert.extendedKeyUsage.isEmpty ? "" : " · " + cert.extendedKeyUsage)) }
                    if let level = cert.validationLevel { row("Validation", level) }
                    if !cert.policies.isEmpty { row("Policies", cert.policies.joined(separator: ", ")) }
                    if !cert.ocspURLs.isEmpty { row("OCSP", cert.ocspURLs.joined(separator: ", ")) }
                    if !cert.caIssuerURLs.isEmpty { row("CA issuers", cert.caIssuerURLs.joined(separator: ", ")) }
                    if !cert.crlURLs.isEmpty { row("CRL", cert.crlURLs.joined(separator: ", ")) }
                    if cert.sctCount > 0 { row("CT", "\(cert.sctCount) signed certificate timestamps") }
                    row("SHA-256", cert.fingerprintSHA256)
                    if !cert.fingerprintSHA1.isEmpty { row("SHA-1", cert.fingerprintSHA1) }
                    if !cert.subjectKeyID.isEmpty { row("Subject key id", cert.subjectKeyID) }
                    if !cert.authorityKeyID.isEmpty { row("Authority key id", cert.authorityKeyID) }
                }
            }
            .font(.caption)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
        .contextMenu {
            Button("Copy PEM") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(cert.pem, forType: .string)
            }
            Button("Save PEM…") { savePEM(cert) }
            Button("Copy SHA-256 fingerprint") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(cert.fingerprintSHA256, forType: .string)
            }
            if !cert.ocspURLs.isEmpty || !cert.crlURLs.isEmpty {
                Divider()
                ForEach(cert.ocspURLs + cert.crlURLs + cert.caIssuerURLs, id: \.self) { url in
                    Button("Open \(url)") { if let u = URL(string: url) { NSWorkspace.shared.open(u) } }
                }
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            Text(value).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func savePEM(_ cert: TLSCertificate) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = cert.commonName.replacingOccurrences(of: "*", with: "wildcard").replacingOccurrences(of: " ", with: "_") + ".pem"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? cert.pem.write(to: url, atomically: true, encoding: .utf8)
    }

    private func createFinding(_ result: TLSResult) {
        var finding = Finding(title: "Certificate problem on \(result.endpoint)")
        let fails = result.problems.filter { $0.level == .fail }
        finding.severity = fails.isEmpty ? .low : .medium
        finding.description = "Issues:\n" + result.problems.map { "- \($0.text)" }.joined(separator: "\n")
            + (result.chain.first.map { "\n\nCertificate: \($0.commonName), issuer \($0.issuer)\($0.notAfter.map { ", valid until \($0.formatted(date: .abbreviated, time: .omitted))" } ?? ""), SHA-256 \($0.fingerprintSHA256)" } ?? "")
        finding.impact = "An expired, mismatched or self-signed certificate lets an attacker on the network path impersonate the service, and trains users to click through certificate warnings."
        finding.recommendation = "Serve a certificate from a trusted CA that covers the host name, with a complete chain, ≥ 2048-bit RSA or P-256 keys, renewed before expiry (automate with ACME where possible)."
        finding.affected = [result.endpoint]
        finding.references = "https://cwe.mitre.org/data/definitions/295.html"
        finding.source = "Certificates"
        _ = findings.add(finding)
        ActivityLog.shared.record(.action, "Finding “\(finding.title)” created from the certificate tool", source: "Tools", host: result.host)
    }

    private func addToTargets(_ result: TLSResult) {
        let isIP = DNSLookup.isIPAddress(result.host)
        let address = isIP ? result.host : (DNS.a(result.host).first ?? result.host)
        let host = targets.addHost(address: address, hostname: isIP ? "" : result.host)
        let service = result.starttls == "none" ? (result.port == 443 ? "https" : "ssl/\(result.port)") : result.starttls
        let port = targets.addPort(to: host, number: result.port, proto: "tcp", description: "\(service) — \(result.negotiatedProtocol)")
        var note = "Certificate (\(result.checkedAt.formatted(date: .abbreviated, time: .shortened))): "
        if let leaf = result.chain.first {
            note += "\(leaf.commonName), issuer \(leaf.issuerOrganisation ?? leaf.issuerName)\(leaf.notAfter.map { ", until \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "")\(leaf.organisation.map { ", O=\($0)" } ?? "")\n"
            if !leaf.sans.isEmpty { note += "Names: \(leaf.sans.joined(separator: ", "))\n" }
            note += "SHA-256: \(leaf.fingerprintSHA256)\n"
        }
        note += result.problems.map { "- \($0.text)" }.joined(separator: "\n")
        if !port.notes.contains("Certificate (") { port.notes += (port.notes.isEmpty ? "" : "\n") + note + "\n" }
        targets.scheduleSave()
        ui.flash("\(result.endpoint) added to Targets with the certificate summary.", seconds: 2)
    }

    /// One host per name (wildcards skipped); names that resolve get their address, others are kept by name.
    private func addNames(_ names: [String], hostname: String?) {
        let wanted = Array(NSOrderedSet(array: names.filter { !$0.hasPrefix("*.") })) as? [String] ?? []
        guard !wanted.isEmpty else { ui.flash("Only wildcard names — nothing to add.", seconds: 2); return }
        ui.flash("Resolving \(wanted.count) name(s)…", seconds: 2)
        let store = targets
        DispatchQueue.global(qos: .userInitiated).async {
            let resolved: [(name: String, address: String)] = wanted.map { name in
                (name, DNSLookup.isIPAddress(name) ? name : (DNS.a(name).first ?? name))
            }
            DispatchQueue.main.async {
                var added = 0
                for entry in resolved {
                    let isIP = DNSLookup.isIPAddress(entry.name)
                    let node = store.addHost(address: entry.address, hostname: isIP ? "" : entry.name)
                    if node.subtitle.isEmpty, !isIP { node.subtitle = entry.name }
                    added += 1
                }
                store.scheduleSave()
                ActivityLog.shared.record(.action, "\(added) host(s) added to Targets from certificate names", source: "Tools")
                UIState.shared.flash("\(added) host(s) added to Targets.", seconds: 2)
            }
        }
    }
}
