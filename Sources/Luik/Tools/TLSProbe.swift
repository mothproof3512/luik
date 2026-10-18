import Foundation

/// Reads `openssl s_client` output and decides what a probe proved. Pure functions, so the
/// decisions can be tested with captured output and never depend on the network.
///
/// The rule that matters: a successful handshake proves nothing by itself. A probe that asks
/// for TLS 1.0 or for RC4 only counts when the server *negotiated* that version or a cipher of
/// that family. Otherwise the local openssl may simply have ignored the restriction (TLS 1.3
/// has its own cipher suites and is not affected by `-cipher`) and the server picked its own.
enum TLSProbe {
    enum Verdict: Equatable {
        /// The server negotiated exactly what the probe asked for.
        case accepted
        /// The handshake failed, or the server negotiated something else.
        case refused
        /// The local openssl could not run this probe (option unknown, version compiled out, no
        /// cipher matched the list, or it negotiated another version than it was told to).
        case notTestable(String)

        var isAccepted: Bool { self == .accepted }
    }

    struct Outcome: Equatable {
        var verdict: Verdict
        var negotiatedProtocol: String?
        var negotiatedCipher: String?
    }

    /// Names as s_client prints them ("TLSv1.2"), keyed by the s_client flag.
    static let protocolNames: [String: String] = ["-ssl3": "SSLv3", "-tls1": "TLSv1", "-tls1_1": "TLSv1.1", "-tls1_2": "TLSv1.2", "-tls1_3": "TLSv1.3"]

    /// "New, TLSv1.3, Cipher is TLS_AES_256_GCM_SHA384" is the line written right after the
    /// handshake; the session block below it ("Protocol  : TLSv1.3") is the fallback.
    static func negotiatedProtocol(_ output: String) -> String? {
        func normalize(_ value: String) -> String? {
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.contains("NONE") { return nil }
            return trimmed == "TLSv1.0" ? "TLSv1" : trimmed
        }
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("New, ") || trimmed.hasPrefix("Reused, ") {
                let parts = trimmed.components(separatedBy: ", ")
                // Older OpenSSL prints "TLSv1/SSLv3" here for every pre-1.3 version: not usable.
                if parts.count >= 2, !parts[1].contains("/"), let value = normalize(parts[1]) { return value }
            }
        }
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Protocol"), let colon = trimmed.firstIndex(of: ":") {
                return normalize(String(trimmed[trimmed.index(after: colon)...]))
            }
        }
        return nil
    }

    /// The cipher the server picked. "(NONE)", "0000" or nothing means no handshake — never a
    /// result. LibreSSL prints the suite's ID instead of a name for TLS 1.3 in the session block,
    /// so the "Cipher is …" line is preferred.
    static func negotiatedCipher(_ output: String) -> String? {
        func clean(_ value: String) -> String? {
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.contains("NONE") || trimmed == "0000" || trimmed == "0x0000" { return nil }
            return trimmed
        }
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("New, ") || trimmed.hasPrefix("Reused, "), let range = trimmed.range(of: "Cipher is ") {
                if let cipher = clean(String(trimmed[range.upperBound...])) { return cipher }
            }
        }
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Cipher"), !trimmed.hasPrefix("Ciphersuite"), let colon = trimmed.firstIndex(of: ":") {
                if let cipher = clean(String(trimmed[trimmed.index(after: colon)...])) { return cipher }
            }
        }
        return nil
    }

    /// Reasons the local openssl could not even try.
    static func localProblem(_ output: String) -> String? {
        let lower = output.lowercased()
        if lower.contains("unknown option") || lower.contains("unrecognized option") || lower.contains("bad option") || lower.contains("invalid command") || lower.contains("cannot supply both") { return "option not supported by this openssl" }
        if lower.contains("no protocols available") || lower.contains("unsupported protocol") || lower.contains("version too low") && lower.contains("ssl routines") { return "version not available in this openssl" }
        if lower.contains("no cipher match") || lower.contains("error setting cipher list") || lower.contains("no ciphers available") { return "no cipher of this family in this openssl" }
        return nil
    }

    /// A protocol probe (`-tls1_1`, …): accepted only when the server negotiated that version.
    static func evaluateProtocol(flag: String, output: String) -> Outcome {
        let negotiated = negotiatedProtocol(output)
        let cipher = negotiatedCipher(output)
        if let problem = localProblem(output) {
            return Outcome(verdict: .notTestable(problem), negotiatedProtocol: negotiated, negotiatedCipher: cipher)
        }
        guard let expected = protocolNames[flag] else { return Outcome(verdict: .notTestable("unknown probe"), negotiatedProtocol: negotiated, negotiatedCipher: cipher) }
        guard cipher != nil, let negotiated else {
            return Outcome(verdict: .refused, negotiatedProtocol: negotiated, negotiatedCipher: cipher)
        }
        if negotiated == expected { return Outcome(verdict: .accepted, negotiatedProtocol: negotiated, negotiatedCipher: cipher) }
        // The client was told to use one version and ended up on another: it ignored the flag
        // (that version is compiled out), so the server was never offered it.
        return Outcome(verdict: .notTestable("this openssl negotiated \(negotiated) instead of \(expected)"), negotiatedProtocol: negotiated, negotiatedCipher: cipher)
    }

    /// A cipher-family probe on TLS 1.2: accepted only when the handshake ended on TLS 1.2
    /// with a cipher that belongs to the family (`family` = what `openssl ciphers LIST` expands to).
    static func evaluateCipherFamily(family: Set<String>, output: String) -> Outcome {
        let negotiated = negotiatedProtocol(output)
        let cipher = negotiatedCipher(output)
        if let problem = localProblem(output) {
            return Outcome(verdict: .notTestable(problem), negotiatedProtocol: negotiated, negotiatedCipher: cipher)
        }
        if family.isEmpty {
            return Outcome(verdict: .notTestable("no cipher of this family in this openssl"), negotiatedProtocol: negotiated, negotiatedCipher: cipher)
        }
        guard let cipher, let negotiated else {
            return Outcome(verdict: .refused, negotiatedProtocol: negotiated, negotiatedCipher: cipher)
        }
        if negotiated == "TLSv1.3" {
            // -cipher does not restrict TLS 1.3 suites; the probe did not reach the server's 1.2 config.
            return Outcome(verdict: .notTestable("this openssl negotiated TLS 1.3 despite -tls1_2"), negotiatedProtocol: negotiated, negotiatedCipher: cipher)
        }
        if family.contains(cipher) { return Outcome(verdict: .accepted, negotiatedProtocol: negotiated, negotiatedCipher: cipher) }
        // Handshake on another cipher than the list allowed: the list was not applied. Not a result.
        return Outcome(verdict: .notTestable("negotiated \(cipher), which is not in the probed family"), negotiatedProtocol: negotiated, negotiatedCipher: cipher)
    }

    /// Secure renegotiation (RFC 5746) exists up to TLS 1.2 only: judged on a TLS 1.2 handshake.
    /// nil = not applicable (no TLS 1.2 handshake).
    static func secureRenegotiation(tls12Output: String?) -> Bool? {
        guard let output = tls12Output, negotiatedProtocol(output) == "TLSv1.2" else { return nil }
        if output.contains("Secure Renegotiation IS supported") { return true }
        if output.contains("Secure Renegotiation IS NOT supported") { return false }
        return nil
    }

    /// TLS compression, same scope as renegotiation.
    static func compressionEnabled(tls12Output: String?) -> Bool? {
        guard let output = tls12Output, negotiatedProtocol(output) == "TLSv1.2" else { return nil }
        for line in output.components(separatedBy: "\n") where line.trimmingCharacters(in: .whitespaces).hasPrefix("Compression:") {
            return !line.contains("NONE")
        }
        return nil
    }

    /// `openssl ciphers LIST` output ("A:B:C") → the names. OpenSSL ≥ 1.1.1 always prepends the
    /// TLS 1.3 suites (TLS_AES_…) whatever the list says; they are not part of any 1.2 family.
    static func cipherNames(fromCiphersOutput output: String) -> Set<String> {
        let line = output.components(separatedBy: "\n").first { !$0.isEmpty && !$0.lowercased().contains("error") && !$0.contains(":error:") } ?? ""
        return Set(line.split(separator: ":").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && !$0.contains(" ") && !$0.hasPrefix("TLS_") })
    }
}
