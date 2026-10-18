import Foundation

/// Reads `openssl s_client` output: what was negotiated, and whether the local openssl could
/// run at all. Pure functions, testable with captured output.
enum TLSProbe {
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
}
