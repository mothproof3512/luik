import AppKit
import Foundation
import Observation
import SwiftUI

/// What one TLS endpoint showed: the certificate chain, the protocol versions and ciphers it
/// accepts, and the verdict lines. Everything comes from the system's openssl (LibreSSL),
/// a handful of handshakes — the same thing you would do by hand with s_client.
struct TLSCertificate: Identifiable {
    let id = UUID()
    var subject = ""
    var issuer = ""
    var notBefore: Date?
    var notAfter: Date?
    var sans: [String] = []
    var keyBits: Int?
    var keyType = ""
    var signatureAlgorithm = ""
    var fingerprint = ""
    var pem = ""

    var commonName: String {
        if let range = subject.range(of: "CN=") {
            let rest = subject[range.upperBound...]
            return String(rest.split(separator: ",").first ?? "").trimmingCharacters(in: .whitespaces)
        }
        return subject
    }
    var isSelfSigned: Bool { !subject.isEmpty && subject == issuer }
    var daysLeft: Int? { notAfter.map { Int($0.timeIntervalSinceNow / 86400) } }
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
    var chain: [TLSCertificate] = []
    /// Protocol name → accepted / refused / nil (not testable with this openssl).
    var protocols: [(name: String, flag: String, accepted: Bool?)] = []
    /// Cipher family → accepted.
    var weakCiphers: [(name: String, accepted: Bool)] = []
    var items: [CheckItem] = []
    var raw = ""

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
        let starttls = self.starttls
        DispatchQueue.global(qos: .userInitiated).async {
            let result = TLSInspector.inspect(host: host, port: port, starttls: starttls)
            DispatchQueue.main.async {
                self.result = result
                self.isRunning = false
                if !result.reachable { self.error = "No TLS handshake with \(result.endpoint) — closed port, no TLS there, or a timeout." }
                ActivityLog.shared.record(.action, "TLS inspected on \(result.endpoint): \(result.problems.count) issue(s), \(result.negotiatedProtocol) \(result.negotiatedCipher)", source: "Tools", host: host)
            }
        }
    }

    // MARK: - The inspection

    private static func sclient(host: String, port: Int, starttls: String, extra: [String]) -> String {
        var arguments = ["s_client", "-connect", "\(host):\(port)", "-servername", host]
        if starttls != "none" { arguments += ["-starttls", starttls] }
        arguments += extra
        return ShellTool.run(openssl, arguments, input: "", timeout: 12)
    }

    private static func value(_ label: String, in text: String) -> String {
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

    private static func handshakeSucceeded(_ output: String) -> Bool? {
        if output.contains("unknown option") || output.contains("Unknown option") || output.contains("bad option") { return nil }
        let cipher = value("Cipher", in: output)
        if cipher.isEmpty || cipher.contains("NONE") { return false }
        return true
    }

    private static func pemBlocks(in text: String) -> [String] {
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

    private static func parseCertificate(pem: String) -> TLSCertificate {
        var cert = TLSCertificate()
        cert.pem = pem
        let text = ShellTool.run(openssl, ["x509", "-noout", "-text", "-fingerprint", "-sha256"], input: pem + "\n", timeout: 6)
        let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "MMM d HH:mm:ss yyyy zzz"
        func date(_ text: String) -> Date? {
            formatter.date(from: text.replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespaces))
        }
        var sawSignatureAlgorithm = false
        for (index, line) in lines.enumerated() {
            if line.hasPrefix("Subject:") { cert.subject = String(line.dropFirst(8)).trimmingCharacters(in: .whitespaces) }
            else if line.hasPrefix("Issuer:") { cert.issuer = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces) }
            else if line.hasPrefix("Not Before:") { cert.notBefore = date(String(line.dropFirst(11))) }
            else if line.hasPrefix("Not After :") || line.hasPrefix("Not After:") { cert.notAfter = date(String(line.drop(while: { $0 != ":" }).dropFirst())) }
            else if line.hasPrefix("Public-Key:") || line.hasPrefix("RSA Public-Key:") || line.hasPrefix("Public Key:") {
                let digits = line.filter { $0.isNumber }
                cert.keyBits = Int(digits)
            }
            else if line.hasPrefix("Public Key Algorithm:") { cert.keyType = String(line.dropFirst(21)).trimmingCharacters(in: .whitespaces) }
            else if line.hasPrefix("ASN1 OID:") && cert.keyType.contains("EC") { cert.keyType += " " + String(line.dropFirst(9)).trimmingCharacters(in: .whitespaces) }
            else if line.hasPrefix("Signature Algorithm:") && !sawSignatureAlgorithm { cert.signatureAlgorithm = String(line.dropFirst(20)).trimmingCharacters(in: .whitespaces); sawSignatureAlgorithm = true }
            else if line.hasPrefix("X509v3 Subject Alternative Name"), index + 1 < lines.count {
                cert.sans = lines[index + 1].components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    .compactMap { $0.hasPrefix("DNS:") ? String($0.dropFirst(4)) : ($0.hasPrefix("IP Address:") ? String($0.dropFirst(11)) : nil) }
            }
            else if line.hasPrefix("SHA256 Fingerprint=") || line.hasPrefix("sha256 Fingerprint=") { cert.fingerprint = String(line.drop(while: { $0 != "=" }).dropFirst()) }
        }
        if cert.keyType.isEmpty, let bits = cert.keyBits { cert.keyType = "\(bits)-bit" }
        return cert
    }

    static func matches(host: String, san: String) -> Bool {
        let host = host.lowercased()
        let san = san.lowercased()
        if san == host { return true }
        if san.hasPrefix("*.") {
            let suffix = san.dropFirst(1)   // ".example.com"
            guard host.hasSuffix(suffix) else { return false }
            let label = host.dropLast(suffix.count)
            return !label.isEmpty && !label.contains(".")
        }
        return false
    }

    static func inspect(host: String, port: Int, starttls: String) -> TLSResult {
        var result = TLSResult(host: host, port: port, starttls: starttls, checkedAt: Date())
        var items: [CheckItem] = []
        let main = sclient(host: host, port: port, starttls: starttls, extra: ["-showcerts"])
        result.raw = main
        guard handshakeSucceeded(main) == true else {
            result.reachable = false
            result.items = [CheckItem(level: .info, text: "No TLS handshake with \(host):\(port).")]
            return result
        }
        result.negotiatedProtocol = value("Protocol", in: main)
        result.negotiatedCipher = value("Cipher", in: main)
        result.tempKey = value("Server Temp Key", in: main)
        result.verifyCode = value("Verify return code", in: main)
        result.chain = pemBlocks(in: main).map(parseCertificate)

        // Certificate
        if let leaf = result.chain.first {
            let isIP = host.allSatisfy { $0.isNumber || $0 == "." || $0 == ":" }
            let nameOK = leaf.sans.contains { matches(host: host, san: $0) } || (leaf.sans.isEmpty && matches(host: host, san: leaf.commonName))
            if isIP {
                items.append(CheckItem(level: .info, text: "Connected by IP address; the certificate is for \(leaf.sans.prefix(5).joined(separator: ", "))\(leaf.sans.count > 5 ? " (+\(leaf.sans.count - 5))" : "")."))
            } else if nameOK {
                items.append(CheckItem(level: .pass, text: "Certificate name matches \(host)\(leaf.sans.count > 1 ? " (\(leaf.sans.count) names)" : "")."))
            } else {
                items.append(CheckItem(level: .fail, text: "Certificate name mismatch: \(host) is not in the certificate (\(leaf.sans.isEmpty ? leaf.commonName : leaf.sans.prefix(5).joined(separator: ", ")))."))
            }
            if let days = leaf.daysLeft {
                if days < 0 {
                    items.append(CheckItem(level: .fail, text: "Certificate expired \(-days) day(s) ago (\(leaf.notAfter!.formatted(date: .abbreviated, time: .omitted)))."))
                } else if days < 30 {
                    items.append(CheckItem(level: .warn, text: "Certificate expires in \(days) day(s) (\(leaf.notAfter!.formatted(date: .abbreviated, time: .omitted)))."))
                } else {
                    items.append(CheckItem(level: .pass, text: "Certificate valid until \(leaf.notAfter!.formatted(date: .abbreviated, time: .omitted)) (\(days) days)."))
                }
                if let before = leaf.notBefore, let after = leaf.notAfter, after.timeIntervalSince(before) > 398 * 86400 {
                    items.append(CheckItem(level: .info, text: "Validity period of \(Int(after.timeIntervalSince(before) / 86400)) days — browsers distrust public certificates over 398 days."))
                }
            }
            if leaf.isSelfSigned {
                items.append(CheckItem(level: .warn, text: "Self-signed certificate (\(leaf.commonName)): clients cannot verify the server; users learn to click through warnings."))
            } else if result.verifyCode.hasPrefix("0") {
                items.append(CheckItem(level: .pass, text: "Chain verifies against the system trust store (issuer: \(result.chain.count > 1 ? result.chain[1].commonName : leaf.issuer))."))
            } else if !result.verifyCode.isEmpty {
                items.append(CheckItem(level: .warn, text: "Chain does not verify: \(result.verifyCode) — untrusted or internal CA, or an incomplete chain (\(result.chain.count) certificate(s) sent)."))
            }
            if let bits = leaf.keyBits {
                let rsa = leaf.keyType.lowercased().contains("rsa")
                if rsa && bits < 2048 {
                    items.append(CheckItem(level: .fail, text: "\(bits)-bit RSA key — below the 2048-bit minimum."))
                } else if !rsa && bits < 224 {
                    items.append(CheckItem(level: .warn, text: "\(bits)-bit \(leaf.keyType) key — short for an EC key."))
                } else {
                    items.append(CheckItem(level: .pass, text: "Key: \(leaf.keyType.isEmpty ? "\(bits) bit" : "\(leaf.keyType), \(bits) bit"); signature \(leaf.signatureAlgorithm)."))
                }
            }
            let signature = leaf.signatureAlgorithm.lowercased()
            if signature.contains("sha1") || signature.contains("md5") {
                items.append(CheckItem(level: .fail, text: "Certificate signed with \(leaf.signatureAlgorithm) — SHA-1/MD5 signatures are deprecated."))
            }
        } else {
            items.append(CheckItem(level: .warn, text: "No certificate could be read from the handshake."))
        }

        // Protocol versions
        let versions: [(String, String)] = [("SSLv3", "-ssl3"), ("TLS 1.0", "-tls1"), ("TLS 1.1", "-tls1_1"), ("TLS 1.2", "-tls1_2"), ("TLS 1.3", "-tls1_3")]
        for (name, flag) in versions {
            let accepted = handshakeSucceeded(sclient(host: host, port: port, starttls: starttls, extra: [flag]))
            result.protocols.append((name, flag, accepted))
        }
        let accepted = result.protocols.filter { $0.accepted == true }.map { $0.name }
        let legacy = accepted.filter { $0 == "SSLv3" || $0 == "TLS 1.0" || $0 == "TLS 1.1" }
        if !legacy.isEmpty {
            items.append(CheckItem(level: legacy.contains("SSLv3") ? .fail : .warn, text: "Legacy protocol(s) accepted: \(legacy.joined(separator: ", ")) — deprecated (RFC 8996); only TLS 1.2 and 1.3 should be offered."))
        }
        if !accepted.contains("TLS 1.2") && !accepted.contains("TLS 1.3") {
            items.append(CheckItem(level: .fail, text: "Neither TLS 1.2 nor TLS 1.3 could be negotiated by this openssl — modern clients may fail to connect."))
        } else if accepted.contains("TLS 1.3") {
            items.append(CheckItem(level: .pass, text: "Protocols: \(accepted.joined(separator: ", ")) (negotiated \(result.negotiatedProtocol))."))
        } else {
            items.append(CheckItem(level: .info, text: "TLS 1.3 not offered; \(accepted.joined(separator: ", ")) accepted (negotiated \(result.negotiatedProtocol))."))
        }
        let untestable = result.protocols.filter { $0.accepted == nil }.map { $0.name }
        if !untestable.isEmpty {
            items.append(CheckItem(level: .info, text: "Not testable with this openssl (compiled out): \(untestable.joined(separator: ", ")) — treat as not offered, confirm with sslscan/testssl.sh if it matters."))
        }

        // Cipher families (TLS 1.2 handshakes with a restricted cipher list)
        let families: [(String, String, CheckItem.Level, String)] = [
            ("NULL / anonymous", "NULL:aNULL", .fail, "no encryption or no authentication"),
            ("EXPORT grade", "EXPORT", .fail, "40/56-bit export ciphers"),
            ("RC4", "RC4", .fail, "RC4 is broken (RFC 7465)"),
            ("3DES", "3DES", .warn, "64-bit block cipher (Sweet32)"),
            ("CBC-only", "AES128-SHA:AES256-SHA:AES128-SHA256:AES256-SHA256:ECDHE-RSA-AES128-SHA:ECDHE-RSA-AES256-SHA", .info, "CBC ciphers — fine on TLS 1.2 with current libraries, but Lucky13-class issues on old ones"),
            ("Static RSA key exchange", "kRSA", .warn, "no forward secrecy: a leaked private key decrypts recorded traffic"),
        ]
        if accepted.contains("TLS 1.2") {
            for (name, list, level, why) in families {
                let output = sclient(host: host, port: port, starttls: starttls, extra: ["-tls1_2", "-cipher", list])
                let ok = handshakeSucceeded(output) == true
                result.weakCiphers.append((name, ok))
                if ok { items.append(CheckItem(level: level, text: "\(name) ciphers accepted (\(value("Cipher", in: output))): \(why).")) }
            }
            if !result.weakCiphers.contains(where: { $0.accepted }) {
                items.append(CheckItem(level: .pass, text: "No weak cipher family accepted on TLS 1.2 (NULL, export, RC4, 3DES, static RSA)."))
            }
        }
        if !result.tempKey.isEmpty {
            let lower = result.tempKey.lowercased()
            if lower.contains("dh") && !lower.contains("ecdh") && !lower.contains("x25519"), let bits = Int(result.tempKey.filter { $0.isNumber }), bits < 2048 {
                items.append(CheckItem(level: .warn, text: "Ephemeral DH key of \(bits) bits (Logjam) — use ≥ 2048-bit DH or ECDHE."))
            } else {
                items.append(CheckItem(level: .pass, text: "Key exchange: \(result.tempKey)."))
            }
        }
        if main.contains("Secure Renegotiation IS NOT supported") {
            items.append(CheckItem(level: .warn, text: "Secure renegotiation (RFC 5746) not supported."))
        }
        if main.contains("Compression: ") && !main.contains("Compression: NONE") {
            items.append(CheckItem(level: .warn, text: "TLS compression enabled (CRIME)."))
        }
        result.items = items.sorted { $0.level.rawValue > $1.level.rawValue }
        return result
    }

    static func markdown(_ result: TLSResult) -> String {
        var out = "## TLS — \(result.endpoint)\(result.starttls == "none" ? "" : " (STARTTLS \(result.starttls))")\n\n_Checked \(result.checkedAt.formatted(date: .abbreviated, time: .shortened)) · negotiated \(result.negotiatedProtocol) \(result.negotiatedCipher)_\n\n"
        out += ShellTool.markdownList(result.items) + "\n\n"
        if !result.protocols.isEmpty {
            out += "| Protocol | Accepted |\n|---|---|\n"
            for protocolEntry in result.protocols { out += "| \(protocolEntry.name) | \(protocolEntry.accepted.map { $0 ? "yes" : "no" } ?? "not testable") |\n" }
            out += "\n"
        }
        for (index, cert) in result.chain.enumerated() {
            out += "**Certificate \(index + 1)** — \(cert.commonName)\n\n- Subject: \(cert.subject)\n- Issuer: \(cert.issuer)\n"
            if let before = cert.notBefore, let after = cert.notAfter { out += "- Valid: \(before.formatted(date: .abbreviated, time: .omitted)) – \(after.formatted(date: .abbreviated, time: .omitted))\n" }
            if !cert.sans.isEmpty { out += "- Names: \(cert.sans.joined(separator: ", "))\n" }
            out += "- Key: \(cert.keyType)\(cert.keyBits.map { " \($0) bit" } ?? ""); signature \(cert.signatureAlgorithm)\n- SHA-256: \(cert.fingerprint)\n\n"
        }
        return out
    }
}

struct TLSInspectorView: View {
    @Environment(FindingsStore.self) private var findings
    @Environment(TargetStore.self) private var targets
    @Environment(UIState.self) private var ui
    @Environment(\.luikTheme) private var theme
    @State private var showChain = false
    @State private var showRaw = false

    var body: some View {
        @Bindable var inspector = TLSInspector.shared
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField("host or host:port (www.example.com, 203.0.113.10:8443)", text: $inspector.target)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)
                    .onSubmit { inspector.run() }
                Picker("STARTTLS", selection: $inspector.starttls) {
                    ForEach(TLSInspector.starttlsOptions, id: \.self) { Text($0).tag($0) }
                }
                .frame(maxWidth: 170)
                .help("For mail, FTP, LDAP and database ports that upgrade to TLS after a plain-text greeting")
                Button {
                    inspector.run()
                } label: {
                    Label("Inspect", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(inspector.isRunning || inspector.target.trimmingCharacters(in: .whitespaces).isEmpty)
                if inspector.isRunning {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                if let result = inspector.result, result.reachable {
                    CheckResultButtons(markdown: { TLSInspector.markdown(result) },
                                       findingTitle: result.problems.isEmpty ? nil : "Weak TLS configuration on \(result.endpoint)",
                                       createFinding: { createFinding(result) },
                                       addToTargets: { addToTargets(result) })
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
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
                            Text(result.endpoint)
                                .font(.title2.weight(.semibold))
                            Text("\(result.negotiatedProtocol) · \(result.negotiatedCipher) · \(result.problems.filter { $0.level == .fail }.count) failing · \(result.problems.filter { $0.level == .warn }.count) warnings")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(result.items) { CheckItemRow(item: $0) }
                        HStack(spacing: 6) {
                            ForEach(Array(result.protocols.enumerated()), id: \.offset) { _, entry in
                                Text(entry.name)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background((entry.accepted == true ? (entry.name.hasPrefix("TLS 1.2") || entry.name.hasPrefix("TLS 1.3") ? Color.green : Color.orange) : Color.gray).opacity(entry.accepted == nil ? 0.15 : 0.3), in: Capsule())
                                    .help(entry.accepted.map { $0 ? "accepted" : "refused" } ?? "not testable with this openssl")
                            }
                        }
                        DisclosureGroup(isExpanded: $showChain) {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(result.chain.enumerated()), id: \.element.id) { index, cert in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(index + 1). \(cert.commonName)\(cert.isSelfSigned ? " (self-signed)" : "")")
                                            .font(.callout.weight(.semibold))
                                        Text("Issuer: \(cert.issuer)")
                                        if let before = cert.notBefore, let after = cert.notAfter {
                                            Text("Valid \(before.formatted(date: .abbreviated, time: .omitted)) – \(after.formatted(date: .abbreviated, time: .omitted))")
                                        }
                                        if !cert.sans.isEmpty { Text("Names: \(cert.sans.joined(separator: ", "))").lineLimit(3) }
                                        Text("Key: \(cert.keyType)\(cert.keyBits.map { " \($0) bit" } ?? "") · \(cert.signatureAlgorithm)")
                                        Text("SHA-256: \(cert.fingerprint)")
                                            .font(.system(.caption2, design: .monospaced))
                                    }
                                    .font(.caption)
                                    .textSelection(.enabled)
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                                    .contextMenu {
                                        Button("Copy PEM") {
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(cert.pem, forType: .string)
                                        }
                                    }
                                }
                            }
                            .padding(.top, 4)
                        } label: {
                            Text("Certificate chain: \(result.chain.count) certificate(s)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
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
                    Image(systemName: "lock.shield")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Enter a host (and port) and press Inspect: certificate chain and names, expiry, key and signature, protocol versions, weak cipher families, forward secrecy.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Text("About ten TLS handshakes with the system's openssl — nothing else is sent. A port node in Targets gets a TLS button for its https/ssl services.")
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

    private func createFinding(_ result: TLSResult) {
        var finding = Finding(title: "Weak TLS configuration on \(result.endpoint)")
        let fails = result.problems.filter { $0.level == .fail }
        finding.severity = fails.isEmpty ? .low : (fails.contains { $0.text.contains("expired") || $0.text.contains("NULL") || $0.text.contains("EXPORT") } ? .medium : .low)
        finding.description = "Issues:\n" + result.problems.map { "- \($0.text)" }.joined(separator: "\n")
            + "\n\nNegotiated: \(result.negotiatedProtocol) \(result.negotiatedCipher)\n"
            + (result.chain.first.map { "Certificate: \($0.commonName), issuer \($0.issuer)\($0.notAfter.map { ", valid until \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "")" } ?? "")
        finding.impact = "Weak protocol versions, cipher suites or certificate problems let an attacker on the network path downgrade, decrypt or impersonate the connection, and train users to accept certificate warnings."
        finding.recommendation = "Offer TLS 1.2 and 1.3 only, with AEAD cipher suites and ECDHE key exchange; disable SSLv3/TLS 1.0/1.1, RC4, 3DES, export and NULL ciphers; serve a complete chain from a trusted CA with ≥ 2048-bit RSA or P-256 keys, renewed before expiry."
        finding.affected = [result.endpoint]
        finding.references = "https://wiki.mozilla.org/Security/Server_Side_TLS\nhttps://www.rfc-editor.org/rfc/rfc8996"
        finding.source = "TLS inspector"
        _ = findings.add(finding)
        ActivityLog.shared.record(.action, "Finding “\(finding.title)” created from the TLS inspector", source: "Tools", host: result.host)
    }

    private func addToTargets(_ result: TLSResult) {
        let isIP = result.host.allSatisfy { $0.isNumber || $0 == "." || $0 == ":" }
        let address = isIP ? result.host : (DNS.a(result.host).first ?? result.host)
        let host = targets.addHost(address: address, hostname: isIP ? "" : result.host)
        let service = result.starttls == "none" ? (result.port == 443 ? "https" : "ssl/\(result.port)") : result.starttls
        let port = targets.addPort(to: host, number: result.port, proto: "tcp", description: "\(service) — \(result.negotiatedProtocol)")
        var note = "TLS (\(result.checkedAt.formatted(date: .abbreviated, time: .shortened))): \(result.negotiatedProtocol) \(result.negotiatedCipher)\n"
        if let leaf = result.chain.first { note += "Certificate: \(leaf.commonName), issuer \(leaf.issuer)\(leaf.notAfter.map { ", until \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "")\n" }
        note += result.problems.map { "- \($0.text)" }.joined(separator: "\n") + "\n"
        if !port.notes.contains("TLS (") { port.notes += (port.notes.isEmpty ? "" : "\n") + note }
        targets.scheduleSave()
        ui.flash("\(result.endpoint) added to Targets with the TLS summary.", seconds: 2)
    }
}
