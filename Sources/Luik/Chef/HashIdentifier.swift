import Foundation

/// Guesses the algorithm behind a hash string from its format, length and alphabet, with the
/// matching hashcat mode and john format — in the spirit of hashid, haiti and name-that-hash.
///
/// The input may be a bare digest, a `hash:salt` pair, a `user:hash` or /etc/shadow line, a
/// pwdump / secretsdump line, a NetNTLM capture, a Responder log line, a Cisco or Juniper
/// configuration line, a `sha256sum` line or a fingerprint with colons — the identifier strips
/// what is around the hash and says so in the remarks.
enum HashIdentifier {
    enum Confidence {
        case likely, possible
    }

    struct Candidate: Identifiable {
        let name: String
        /// hashcat mode ("1000"), several modes ("17200–17230") or "—" when hashcat has none.
        let hashcat: String
        /// john format ("nt") or "—".
        let john: String
        let confidence: Confidence
        let note: String?

        init(_ name: String, _ hashcat: String, _ john: String, _ confidence: Confidence = .likely, note: String? = nil) {
            self.name = name
            self.hashcat = hashcat
            self.john = john
            self.confidence = confidence
            self.note = note
        }

        var id: String { name }

        /// The first mode number in `hashcat`, for a ready-made command line (nil when the hash
        /// first needs converting or wrapping).
        var hashcatMode: String? {
            let digits = hashcat.prefix { $0.isNumber }
            guard !digits.isEmpty, !hashcat.contains("convert"), !hashcat.contains("in front") else { return nil }
            return String(digits)
        }

        /// A john format name usable after --format= (nil for "—" or descriptive text).
        var johnFormat: String? {
            let first = john.split(separator: " ").first.map(String.init) ?? ""
            guard !first.isEmpty, first != "—", first.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else { return nil }
            return first
        }
    }

    struct Analysis {
        /// The part of the input that was identified (after stripping a user name, label, prefix…).
        let subject: String
        /// What was stripped or noticed on the way.
        let remarks: [String]
        let candidates: [Candidate]

        var likely: [Candidate] { candidates.filter { $0.confidence == .likely } }
        var possible: [Candidate] { candidates.filter { $0.confidence == .possible } }
        var isEmpty: Bool { candidates.isEmpty }
    }

    // MARK: - Entry points

    /// All candidates, most likely first (kept for callers that only need names).
    static func identify(_ raw: String) -> [Candidate] {
        analyze(raw).candidates
    }

    static func analyze(_ raw: String) -> Analysis {
        let cleaned = clean(raw)
        guard !cleaned.isEmpty else { return Analysis(subject: "", remarks: [], candidates: []) }
        let whole = analyzeWhole(cleaned)
        if !whole.isEmpty { return whole }

        // Nothing matched the line as a whole: look for a hash-like token inside it
        // ("key = value", log lines, configuration lines, prose around a hash).
        let separators: Set<Character> = ["\"", "'", "`", "=", ",", ";", "(", ")", "<", ">", "[", "]", "|"]
        let tokens = cleaned.split { $0.isWhitespace || separators.contains($0) }.map(String.init).filter { $0.count >= 8 }
        if tokens.count > 1 {
            for token in tokens.sorted(by: { $0.count > $1.count }) {
                let inner = analyzeWhole(token)
                if !inner.likely.isEmpty {
                    return Analysis(subject: inner.subject, remarks: ["found inside the line"] + inner.remarks, candidates: inner.candidates)
                }
            }
        }
        return whole
    }

    /// Multi-line, human-readable result for one input line (used by the Chef operation).
    static func report(_ raw: String) -> String {
        let analysis = analyze(raw)
        var lines: [String] = []
        let shown = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        lines.append(shown.count > 90 ? String(shown.prefix(87)) + "…" : shown)
        if !analysis.remarks.isEmpty {
            lines.append("  (" + analysis.remarks.joined(separator: "; ") + ")")
        }
        if analysis.isEmpty {
            lines.append("  no match — " + describe(analysis.subject))
            lines.append("  tip: paste salted hashes as hash:salt, Windows dumps as the whole user:rid:lm:nt::: line, and a /etc/shadow entry including the user name")
            return lines.joined(separator: "\n")
        }
        let likely = analysis.likely
        let possible = analysis.possible
        let width = min(46, likely.map { $0.name.count }.max() ?? 0)
        for candidate in likely {
            let name = candidate.name.count >= width ? candidate.name : candidate.name.padding(toLength: width, withPad: " ", startingAt: 0)
            var line = "  \(name)   hashcat \(candidate.hashcat)   john \(candidate.john)"
            if let note = candidate.note { line += "\n      ↳ \(note)" }
            lines.append(line)
        }
        if !possible.isEmpty {
            let text = possible.map { candidate -> String in
                var piece = candidate.name
                if candidate.hashcat != "—" { piece += " [\(candidate.hashcat)]" }
                if let note = candidate.note { piece += " — \(note)" }
                return piece
            }.joined(separator: " · ")
            lines.append("  less likely: " + text)
        }
        if let first = likely.first, let mode = first.hashcatMode {
            lines.append("  → hashcat -m \(mode) -a 0 hashes.txt /usr/share/wordlists/rockyou.txt")
            if let format = first.johnFormat {
                lines.append("    john --format=\(format) --wordlist=/usr/share/wordlists/rockyou.txt hashes.txt")
            }
        } else if let first = likely.first, let format = first.johnFormat {
            lines.append("  → john --format=\(format) --wordlist=/usr/share/wordlists/rockyou.txt hashes.txt")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Pipeline

    private static func clean(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = text.last, ",;".contains(last) { text.removeLast() }
        let quotes: Set<Character> = ["\"", "'", "`"]
        while text.count >= 2, let first = text.first, let last = text.last, quotes.contains(first), first == last {
            text = String(text.dropFirst().dropLast())
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func analyzeWhole(_ input: String) -> Analysis {
        var subject = input
        var remarks: [String] = []

        // "[SMB] NTLMv2-SSP Hash : …" (Responder) and "NT hash: …" style labels.
        if let m = captures(labelRegex, subject), !m[2].isEmpty {
            subject = m[2]
            remarks.append("label “\(m[1].trimmingCharacters(in: .whitespaces))” ignored")
        }

        // Cisco configuration lines: "enable secret 5 $1$…", "username x password 7 0822455D0A16".
        if let m = captures(ciscoLineRegex, subject) {
            let type = m[1]
            let token = m[2]
            remarks.append("Cisco configuration line, password type \(type)")
            switch type {
            case "0":
                return Analysis(subject: token, remarks: remarks,
                                candidates: [Candidate("Cisco type 0 — plaintext", "—", "—", note: "the password is “\(token)”")])
            case "4":
                return Analysis(subject: token, remarks: remarks,
                                candidates: [Candidate("Cisco-IOS type 4 (SHA-256)", "5700", "raw-sha256 ($cisco4$…)")])
            case "5":
                return Analysis(subject: token, remarks: remarks, candidates: [Candidate("Cisco-IOS type 5 (md5crypt)", "500", "md5crypt")])
            case "6":
                return Analysis(subject: token, remarks: remarks,
                                candidates: [Candidate("Cisco type 6 (AES, reversible with the device's master key)", "—", "—")])
            case "7":
                return Analysis(subject: token, remarks: remarks, candidates: [ciscoType7Candidate(token)])
            default:
                subject = token // 8 and 9 go through the rules below
            }
        }

        // sha256sum-style "hash  filename".
        if let m = captures(checksumLineRegex, subject) {
            subject = m[1]
            remarks.append("checksum line — file name ignored")
        }

        // Fingerprint style: 5f:4d:cc:3b:… or 5F-4D-CC-….
        if captures(hexPairsRegex, subject) != nil {
            subject = subject.filter { $0.isHexDigit }
            remarks.append("separators removed (fingerprint/thumbprint style — these are usually not password hashes)")
        }

        // {CRYPT} wrapper (LDAP) around a Unix crypt hash.
        if subject.lowercased().hasPrefix("{crypt}") {
            subject = String(subject.dropFirst(7))
            remarks.append("{CRYPT} wrapper removed")
        }

        // 0x prefix on a plain digest (MSSQL and Sybase keep theirs — the rules know them).
        let lower = subject.lowercased()
        if let m = captures(hexWith0xRegex, subject),
           !lower.hasPrefix("0x0100"), !lower.hasPrefix("0x0200"), !lower.hasPrefix("0xc007") {
            subject = m[1]
            remarks.append("0x prefix removed")
        }

        // 1. Structured / prefixed formats.
        for rule in rules where rule.regex.firstMatch(in: subject, range: NSRange(subject.startIndex..., in: subject)) != nil {
            return Analysis(subject: subject, remarks: remarks, candidates: rule.candidates)
        }

        // 2. Colon forms: NetNTLM, pwdump, LM:NT, hash:salt, user:hash, shadow lines.
        if let analysis = colonForms(subject, remarks: remarks) {
            return analysis
        }

        // 3. Plain digests by alphabet and length.
        return Analysis(subject: subject, remarks: remarks, candidates: plainCandidates(subject))
    }

    private static func colonForms(_ subject: String, remarks: [String]) -> Analysis? {
        guard subject.contains(":") else { return nil }

        if let m = captures(netNTLMv1Regex, subject) {
            let user = m[1].isEmpty ? "" : " for \(m[1])" + (m[2].isEmpty ? "" : "@\(m[2])")
            return Analysis(subject: subject, remarks: remarks + ["NetNTLMv1 capture\(user)"],
                            candidates: [Candidate("NetNTLMv1 / NetNTLMv1+ESS", "5500", "netntlm",
                                                   note: "if the challenge is 1122334455667788: crack the NT hash with 27000 or crack.sh / ntlmv1-multi")])
        }
        if let m = captures(netNTLMv2Regex, subject) {
            let user = m[1].isEmpty ? "" : " for \(m[1])" + (m[2].isEmpty ? "" : "@\(m[2])")
            return Analysis(subject: subject, remarks: remarks + ["NetNTLMv2 capture\(user)"],
                            candidates: [Candidate("NetNTLMv2", "5600", "netntlmv2")])
        }
        if let m = captures(pwdumpRegex, subject) {
            var candidates = [Candidate("NTLM (field 4 of the pwdump line)", "1000", "nt", note: emptyHashNote(m[4])),
                              Candidate("LM (field 3)", "3000", "lm", m[3].lowercased() == "aad3b435b51404eeaad3b435b51404ee" ? .possible : .likely,
                                        note: m[3].lowercased() == "aad3b435b51404eeaad3b435b51404ee" ? "empty LM hash — LM is disabled, nothing to crack" : nil)]
            if m[4].lowercased() == "31d6cfe0d16ae931b73c59d7e0c089c0" {
                candidates[0] = Candidate("NTLM (field 4 of the pwdump line)", "1000", "nt", note: "this is the NTLM hash of the empty password")
            }
            let rid = m[2].isEmpty ? "" : ", RID \(m[2])"
            return Analysis(subject: subject, remarks: remarks + ["pwdump / secretsdump line for \(m[1])\(rid)"], candidates: candidates)
        }
        if let m = captures(lmNTPairRegex, subject) {
            var candidates = [Candidate("LM:NT pair (pwdump without user name)", "1000 (NT) / 3000 (LM)", "nt / lm", note: emptyHashNote(m[2]))]
            if m[1].lowercased() != "aad3b435b51404eeaad3b435b51404ee" {
                candidates.append(Candidate("md5($pass.$salt) / Joomla < 2.5.18 (32-byte salt)", "10 / 11", "dynamic_1", .possible))
            }
            return Analysis(subject: subject, remarks: remarks, candidates: candidates)
        }

        let parts = subject.components(separatedBy: ":")

        // hash:salt and hash:user.
        if parts.count == 2, parts[0].allSatisfy({ $0.isHexDigit }), !parts[1].isEmpty {
            let salted = saltedCandidates(hashLength: parts[0].count, salt: parts[1])
            if !salted.isEmpty {
                return Analysis(subject: subject, remarks: remarks + ["hash:salt (or hash:user) form, salt length \(parts[1].count)"], candidates: salted)
            }
        }

        // user:hash, /etc/shadow and htpasswd lines: identify field 2.
        if parts.count >= 2, !parts[0].isEmpty, !(parts[0].count >= 8 && parts[0].allSatisfy({ $0.isHexDigit })) {
            var field = parts[1]
            var extra: [String] = []
            if field.hasPrefix("!") || field.hasPrefix("*") {
                extra.append("account locked/disabled (\(field.prefix(1)) in front of the hash)")
                field = String(field.drop { $0 == "!" || $0 == "*" })
            }
            if field.isEmpty || field == "x" {
                return Analysis(subject: subject, remarks: remarks + ["field 2 is “\(parts[1])” — no hash here (passwd entry, the hash lives in /etc/shadow)"], candidates: [])
            }
            let inner = analyzeWhole(field)
            if !inner.isEmpty {
                let kind = parts.count >= 8 ? "/etc/shadow line" : (parts.count == 2 ? "user:hash line" : "colon-separated line")
                return Analysis(subject: inner.subject, remarks: remarks + ["\(kind) for “\(parts[0])” — hash taken from field 2"] + extra + inner.remarks,
                                candidates: inner.candidates)
            }
        }
        return nil
    }

    // MARK: - Plain digests

    private static func plainCandidates(_ subject: String) -> [Candidate] {
        if subject.count >= 8, subject.allSatisfy({ $0.isHexDigit }) {
            var candidates = hexCandidates(subject)
            if let decoded = CiscoType7.decode(subject), subject.count <= 100 {
                candidates.append(Candidate("Cisco type 7 (reversible)", "—", "—", candidates.isEmpty ? .likely : .possible, note: "decodes to “\(decoded)”"))
            }
            return candidates
        }

        let cryptAlphabet = Set("./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
        if subject.allSatisfy({ cryptAlphabet.contains($0) }) {
            let mixed = subject.contains { $0.isUppercase } && subject.contains { $0.isLowercase } && subject.contains { $0.isNumber }
            switch subject.count {
            case 13:
                return [Candidate("descrypt (traditional DES crypt, /etc/passwd and htpasswd)", "1500", "descrypt", mixed ? .likely : .possible)]
            case 16:
                return [Candidate("Cisco-ASA MD5 (needs hash:user)", "2410", "asa-md5", mixed ? .likely : .possible),
                        Candidate("Cisco-PIX MD5", "2400", "pix-md5", mixed ? .likely : .possible)]
            case 43 where !subject.contains("+"):
                var out = [Candidate("Cisco-IOS type 4 (SHA-256, unpadded Base64)", "5700", "raw-sha256 ($cisco4$…)")]
                if !subject.contains(".") {
                    out.append(Candidate("SHA-256 (Base64 without padding)", "1400 (convert to hex)", "raw-sha256", .possible))
                }
                return out
            default:
                break
            }
        }

        if subject.count >= 16, Base64.looksLikeBase64(subject), let data = Base64.decodeLenient(subject) {
            return base64Candidates(byteCount: data.count)
        }
        return []
    }

    private static func hexCandidates(_ hex: String) -> [Candidate] {
        let lower = hex.lowercased()
        switch hex.count {
        case 8:
            return [Candidate("CRC-32 (as hash:salt, e.g. c762de4a:00000000)", "11500", "crc32", .possible),
                    Candidate("Adler-32 / FNV-32 / CRC-32C", "—", "—", .possible, note: "checksums, not password hashes")]
        case 16:
            return [Candidate("MySQL 3.23 (pre-4.1)", "200", "mysql"),
                    Candidate("Oracle 7–10g (DES, needs hash:user)", "3100", "oracle"),
                    Candidate("Half MD5 (first 8 bytes)", "5100", "—", .possible),
                    Candidate("LM — one half (7 characters)", "3000", "lm", .possible),
                    Candidate("CRC-64 / FNV-64 / SipHash", "—", "—", .possible)]
        case 32:
            var out: [Candidate] = []
            switch lower {
            case "31d6cfe0d16ae931b73c59d7e0c089c0":
                out.append(Candidate("NTLM", "1000", "nt", note: "this is the NTLM hash of the empty password"))
            case "aad3b435b51404eeaad3b435b51404ee":
                out.append(Candidate("LM", "3000", "lm", note: "the empty LM hash — LM storage is disabled, nothing to crack"))
            case "d41d8cd98f00b204e9800998ecf8427e":
                out.append(Candidate("MD5", "0", "raw-md5", note: "MD5 of the empty string"))
            default:
                break
            }
            if out.isEmpty {
                out += [Candidate("MD5", "0", "raw-md5"),
                        Candidate("NTLM", "1000", "nt"),
                        Candidate("MD4", "900", "raw-md4"),
                        Candidate("LM", "3000", "lm")]
            } else {
                let special = out[0].name
                let others = [Candidate("MD5", "0", "raw-md5", .possible), Candidate("NTLM", "1000", "nt", .possible), Candidate("MD4", "900", "raw-md4", .possible)]
                out += others.filter { $0.name != special }
            }
            out += [Candidate("Domain Cached Credentials (MS Cache, hash:user)", "1100", "mscash", .possible),
                    Candidate("md5(md5($pass))", "2600", "—", .possible),
                    Candidate("md5(utf16le($pass))", "70", "—", .possible),
                    Candidate("MD2", "—", "md2", .possible),
                    Candidate("RIPEMD-128 / Haval-128 / Tiger-128 / Snefru-128", "—", "—", .possible),
                    Candidate("RAdmin v2.x", "9900", "radmin", .possible),
                    Candidate("Skype (hash:user)", "23", "skype", .possible),
                    Candidate("Kerberos AES-128 key (secretsdump / DCSync)", "—", "—", .possible, note: "a key, not a hash")]
            return out
        case 40:
            var out: [Candidate] = []
            if lower == "da39a3ee5e6b4b0d3255bfef95601890afd80709" {
                out.append(Candidate("SHA-1", "100", "raw-sha1", note: "SHA-1 of the empty string"))
            } else {
                out.append(Candidate("SHA-1", "100", "raw-sha1"))
            }
            out += [Candidate("MySQL 4.1+ / 5.x (usually shown with a leading *)", "300", "mysql-sha1"),
                    Candidate("RIPEMD-160", "6000", "ripemd-160"),
                    Candidate("sha1(sha1($pass))", "4500", "—", .possible),
                    Candidate("sha1(utf16le($pass))", "170", "—", .possible),
                    Candidate("Tiger-160 / Haval-160 / HAS-160", "—", "has-160", .possible),
                    Candidate("SHA-1 of a Git object / LinkedIn-style dump", "100", "raw-sha1", .possible)]
            return out
        case 48:
            return [Candidate("Tiger-192", "—", "tiger"),
                    Candidate("Haval-192", "—", "—", .possible),
                    Candidate("SHA-1 + 4-byte salt (hex)", "—", "—", .possible)]
        case 56:
            return [Candidate("SHA-224", "1300", "raw-sha224"),
                    Candidate("SHA3-224", "17300", "—"),
                    Candidate("Keccak-224", "17700", "—", .possible),
                    Candidate("Haval-224 / Skein-256(224)", "—", "—", .possible)]
        case 64:
            var out: [Candidate] = []
            if lower == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" {
                out.append(Candidate("SHA-256", "1400", "raw-sha256", note: "SHA-256 of the empty string"))
            } else {
                out.append(Candidate("SHA-256", "1400", "raw-sha256"))
            }
            out += [Candidate("SHA3-256", "17400", "—"),
                    Candidate("Keccak-256", "17800", "raw-keccak-256"),
                    Candidate("BLAKE2s-256", "—", "—", .possible),
                    Candidate("GOST R 34.11-94", "6900", "gost", .possible),
                    Candidate("Streebog-256 (GOST 2012)", "11700", "—", .possible),
                    Candidate("sha256(utf16le($pass))", "1470", "—", .possible),
                    Candidate("RIPEMD-256 / Haval-256 / Snefru-256 / Skein-256", "—", "—", .possible),
                    Candidate("Kerberos AES-256 key (secretsdump / DCSync)", "—", "—", .possible, note: "a key, not a hash: use it for pass-the-key or ticket forging instead of cracking")]
            return out
        case 80:
            return [Candidate("RIPEMD-320", "—", "ripemd-320")]
        case 96:
            return [Candidate("SHA-384", "10800", "raw-sha384"),
                    Candidate("SHA3-384", "17500", "—"),
                    Candidate("Keccak-384", "17900", "—", .possible),
                    Candidate("Skein-512(384)", "—", "—", .possible)]
        case 128:
            var out: [Candidate] = []
            if lower.hasPrefix("cf83e1357eefb8bdf1542850d66d8007") {
                out.append(Candidate("SHA-512", "1700", "raw-sha512", note: "SHA-512 of the empty string"))
            } else {
                out.append(Candidate("SHA-512", "1700", "raw-sha512"))
            }
            out += [Candidate("SHA3-512", "17600", "—"),
                    Candidate("Keccak-512", "18000", "raw-keccak"),
                    Candidate("Whirlpool", "6100", "whirlpool"),
                    Candidate("BLAKE2b-512", "600", "raw-blake2", .possible),
                    Candidate("Streebog-512 (GOST 2012)", "11800", "—", .possible),
                    Candidate("sha512(utf16le($pass))", "1770", "—", .possible),
                    Candidate("Skein-512 / Skein-1024(512)", "—", "—", .possible)]
            return out
        default:
            return []
        }
    }

    private static func saltedCandidates(hashLength: Int, salt: String) -> [Candidate] {
        switch hashLength {
        case 8:
            return [Candidate("CRC-32 with salt", "11500", "crc32")]
        case 16:
            return [Candidate("Oracle 7–10g (hash:user)", "3100", "oracle"),
                    Candidate("MySQL 3.23 — the part after the colon is not used", "200", "mysql", .possible)]
        case 32:
            var out = [Candidate("md5($pass.$salt)", "10", "dynamic_1"),
                       Candidate("md5($salt.$pass)", "20", "dynamic_4")]
            switch salt.count {
            case 2: out.insert(Candidate("osCommerce / xt:Commerce (2-character salt)", "21", "dynamic_4"), at: 0)
            case 3: out.insert(Candidate("vBulletin < 3.8.5 (3-character salt)", "2611", "dynamic_6"), at: 0)
            case 5: out.insert(Candidate("IPB 2+ (5-character salt)", "2811", "ipb2"), at: 0)
            case 8: out.insert(Candidate("MyBB 1.2+ (8-character salt)", "2811", "ipb2"), at: 0)
            case 30: out.insert(Candidate("vBulletin ≥ 3.8.5 (30-character salt)", "2711", "dynamic_6"), at: 0)
            case 32:
                out.insert(Candidate("Joomla < 2.5.18 (32-character salt)", "11", "dynamic_1"), at: 0)
                out.append(Candidate("md5(md5($salt).$pass) / md5($salt.md5($pass))", "3610 / 3710", "—", .possible))
            default: break
            }
            out += [Candidate("Domain Cached Credentials (MS Cache) as hash:user", "1100", "mscash", .possible),
                    Candidate("Skype as hash:user", "23", "skype", .possible),
                    Candidate("md5(md5($pass).$salt) / md5($salt.$pass.$salt)", "2600 / 3800", "—", .possible)]
            return out
        case 40:
            return [Candidate("sha1($pass.$salt)", "110", "dynamic_24"),
                    Candidate("sha1($salt.$pass)", "120", "dynamic_25"),
                    Candidate("sha1(utf16le($pass).$salt)", "130", "—", .possible),
                    Candidate("HMAC-SHA1 (key = $salt)", "160", "hmac-sha1", .possible)]
        case 64:
            return [Candidate("sha256($pass.$salt)", "1410", "dynamic_62"),
                    Candidate("sha256($salt.$pass)", "1420", "dynamic_61"),
                    Candidate("HMAC-SHA256 (key = $salt)", "1460", "hmac-sha256", .possible)]
        case 128:
            return [Candidate("sha512($pass.$salt)", "1710", "dynamic_82"),
                    Candidate("sha512($salt.$pass)", "1720", "dynamic_81"),
                    Candidate("HMAC-SHA512 (key = $salt)", "1760", "hmac-sha512", .possible)]
        default:
            return []
        }
    }

    private static func base64Candidates(byteCount: Int) -> [Candidate] {
        switch byteCount {
        case 16:
            return [Candidate("MD5 (Base64)", "0 (convert to hex)", "raw-md5"),
                    Candidate("NTLM / MD4 (Base64)", "1000 / 900 (convert to hex)", "nt", .possible)]
        case 20:
            return [Candidate("SHA-1 (Base64, like {SHA} without the prefix)", "101 (with {SHA} in front) or 100 as hex", "nsldap / raw-sha1")]
        case 24:
            return [Candidate("Salted SHA-1 with 4-byte salt (like {SSHA} without the prefix)", "111 (with {SSHA} in front)", "salted-sha1")]
        case 28:
            return [Candidate("SHA-224 (Base64)", "1300 (convert to hex)", "raw-sha224"),
                    Candidate("Salted SHA-1 with 8-byte salt ({SSHA} style)", "111 (with {SSHA} in front)", "salted-sha1", .possible)]
        case 32:
            return [Candidate("SHA-256 (Base64)", "1400 (convert to hex)", "raw-sha256"),
                    Candidate("LastPass (hash:user)", "6800", "lastpass", .possible)]
        case 36, 40:
            return [Candidate("Salted SHA-256 ({SSHA256} style, \(byteCount - 32)-byte salt)", "1411 (with {SSHA256} in front)", "—")]
        case 48:
            return [Candidate("SHA-384 (Base64)", "10800 (convert to hex)", "raw-sha384")]
        case 64:
            return [Candidate("SHA-512 (Base64)", "1700 (convert to hex)", "raw-sha512")]
        case 68, 72, 80:
            return [Candidate("Salted SHA-512 ({SSHA512} style, \(byteCount - 64)-byte salt)", "1711 (with {SSHA512} in front)", "ssha512")]
        default:
            return []
        }
    }

    // MARK: - Helpers

    private static func emptyHashNote(_ nt: String) -> String? {
        nt.lowercased() == "31d6cfe0d16ae931b73c59d7e0c089c0" ? "the NT hash is that of the empty password" : nil
    }

    private static func ciscoType7Candidate(_ token: String) -> Candidate {
        if let decoded = CiscoType7.decode(token) {
            return Candidate("Cisco type 7 (reversible)", "—", "—", note: "decodes to “\(decoded)”")
        }
        return Candidate("Cisco type 7 (reversible) — but this does not decode cleanly", "—", "—", .possible, note: "check the string; use the Cisco type 7 decode operation")
    }

    private static func describe(_ subject: String) -> String {
        let count = subject.count
        let kind: String
        if subject.allSatisfy({ $0.isHexDigit }) {
            kind = "hex"
        } else if subject.allSatisfy({ $0.isLetter || $0.isNumber || "+/=".contains($0) }) {
            kind = "Base64-like"
        } else if subject.allSatisfy({ $0.isLetter || $0.isNumber || "./".contains($0) }) {
            kind = "crypt alphabet"
        } else {
            kind = "mixed characters"
        }
        var parts = ["\(count) characters, \(kind)"]
        let dollars = subject.filter { $0 == "$" }.count
        if dollars > 0 { parts.append("\(dollars) × $") }
        let colons = subject.filter { $0 == ":" }.count
        if colons > 0 { parts.append("\(colons) × :") }
        if kind == "hex", ![8, 16, 32, 40, 48, 56, 64, 80, 96, 128].contains(count) {
            parts.append("no common digest has this length — truncated, concatenated (hash+salt?) or not a hash")
        }
        return parts.joined(separator: ", ")
    }

    private static func captures(_ regex: NSRegularExpression, _ text: String) -> [String]? {
        guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            guard let range = Range(match.range(at: index), in: text) else { return "" }
            return String(text[range])
        }
    }

    private static func regex(_ pattern: String, _ options: NSRegularExpression.Options = []) -> NSRegularExpression {
        // The patterns are constants that are checked in the project's tests; a typo would show at launch.
        try! NSRegularExpression(pattern: pattern, options: options)
    }

    private static let labelRegex = regex(#"^([A-Za-z\[][A-Za-z0-9 _()\[\]/-]{0,40}?)\s*:\s+(\S.*)$"#)
    private static let ciscoLineRegex = regex(#"(?:secret|password|key|md5|community)\s+([0456789])\s+(\S+)"#, [.caseInsensitive])
    private static let checksumLineRegex = regex(#"^([0-9A-Fa-f]{32,128})\s+\*?\S.*$"#)
    private static let hexPairsRegex = regex(#"^(?:[0-9A-Fa-f]{2}[:\- ]){3,}[0-9A-Fa-f]{2}$"#)
    private static let hexWith0xRegex = regex(#"^0[xX]([0-9A-Fa-f]+)$"#)
    private static let netNTLMv1Regex = regex(#"^([^:]*)::([^:]*):([0-9A-Fa-f]{48}):([0-9A-Fa-f]{48}):([0-9A-Fa-f]{16})$"#)
    private static let netNTLMv2Regex = regex(#"^([^:]*)::([^:]*):([0-9A-Fa-f]{16}):([0-9A-Fa-f]{32}):([0-9A-Fa-f]+)$"#)
    private static let pwdumpRegex = regex(#"^([^:]+):(\d*):([0-9A-Fa-f]{32}):([0-9A-Fa-f]{32}):::"#)
    private static let lmNTPairRegex = regex(#"^([0-9A-Fa-f]{32}):([0-9A-Fa-f]{32})$"#)

    // MARK: - Rules for prefixed and structured formats (checked on the whole string, in order)

    private struct Rule {
        let regex: NSRegularExpression
        let candidates: [Candidate]

        init(_ pattern: String, _ candidates: [Candidate]) {
            regex = HashIdentifier.regex(pattern)
            self.candidates = candidates
        }

        init(_ pattern: String, _ name: String, _ hashcat: String, _ john: String, note: String? = nil) {
            self.init(pattern, [Candidate(name, hashcat, john, note: note)])
        }
    }

    private static let rules: [Rule] = [
        // Unix crypt family
        Rule(#"^\$2[abxy]?\$\d{2}\$[./A-Za-z0-9]{53}$"#, "bcrypt", "3200", "bcrypt"),
        Rule(#"^\$2[abxy]?\$"#, "bcrypt (unusual length — check for truncation)", "3200", "bcrypt"),
        Rule(#"^\$wp\$2[aby]\$"#, "WordPress ≥ 6.8 (bcrypt of base64(sha384($pass)))", "—", "—",
             note: "not plain bcrypt: the $wp prefix marks the SHA-384 pre-hash"),
        Rule(#"^\$1\$[^$]{0,8}\$[./A-Za-z0-9]{22}$"#, "md5crypt (Unix MD5, Cisco-IOS type 5)", "500", "md5crypt"),
        Rule(#"^\$1\$"#, "md5crypt (unusual length — check for truncation)", "500", "md5crypt"),
        Rule(#"^\$apr1\$"#, "Apache apr1 (htpasswd MD5)", "1600", "md5crypt"),
        Rule(#"^\$5\$"#, "sha256crypt (Unix)", "7400", "sha256crypt"),
        Rule(#"^\$6\$"#, "sha512crypt (Unix)", "1800", "sha512crypt"),
        Rule(#"^\$y\$"#, "yescrypt (modern Linux /etc/shadow)", "—", "crypt (libxcrypt)", note: "hashcat has no mode; john uses --format=crypt"),
        Rule(#"^\$gy\$"#, "gost-yescrypt", "—", "crypt (libxcrypt)"),
        Rule(#"^\$7\$"#, "scrypt (crypt notation)", "—", "scrypt"),
        Rule(#"^\$argon2(id|i|d)\$"#, "Argon2", "34000 (hashcat ≥ 7.0)", "argon2"),
        Rule(#"^\$md5(,rounds=\d+)?\$"#, "Solaris sunmd5", "3300", "sunmd5"),
        Rule(#"^\$sha1\$"#, "sha1crypt (NetBSD / Juniper)", "15100", "sha1crypt"),
        Rule(#"^_[./A-Za-z0-9]{19}$"#, "BSDi crypt", "12400", "bsdicrypt"),

        // PBKDF2 / scrypt notations
        Rule(#"^\$pbkdf2-sha256\$"#, "PBKDF2-HMAC-SHA256 (passlib)", "20300", "pbkdf2-hmac-sha256"),
        Rule(#"^\$pbkdf2-sha512\$"#, "PBKDF2-HMAC-SHA512 (passlib)", "20200", "pbkdf2-hmac-sha512"),
        Rule(#"^\$pbkdf2\$"#, "PBKDF2-HMAC-SHA1 (passlib)", "20400", "pbkdf2-hmac-sha1"),
        Rule(#"^sha256:\d+:[^:]+:[^:]+$"#, "PBKDF2-HMAC-SHA256 (sha256:iterations:salt:hash)", "10900", "pbkdf2-hmac-sha256"),
        Rule(#"^sha512:\d+:[^:]+:[^:]+$"#, "PBKDF2-HMAC-SHA512 (sha512:iterations:salt:hash)", "12100", "pbkdf2-hmac-sha512"),
        Rule(#"^sha1:\d+:[^:]+:[^:]+$"#, "PBKDF2-HMAC-SHA1 (sha1:iterations:salt:hash)", "12000", "pbkdf2-hmac-sha1"),
        Rule(#"^md5:\d+:[^:]+:[^:]+$"#, "PBKDF2-HMAC-MD5 (md5:iterations:salt:hash)", "11900", "pbkdf2-hmac-md5"),
        Rule(#"^SCRYPT:\d+:\d+:\d+:"#, "scrypt", "8900", "scrypt"),
        Rule(#"^\$ml\$"#, "macOS 10.8+ (PBKDF2-SHA512)", "7100", "pbkdf2-hmac-sha512"),
        Rule(#"^AQAAAAEAACcQ"#, "ASP.NET Core Identity v3 (PBKDF2-HMAC-SHA256, 10 000 iterations)", "— (convert to sha256:10000:salt:hash, 10900)", "—"),
        Rule(#"^AQAAAAIAAYag"#, "ASP.NET Core Identity v3 (PBKDF2-HMAC-SHA512, 100 000 iterations)", "— (convert to sha512:100000:salt:hash, 12100)", "—"),

        // Network devices
        Rule(#"^\$8\$"#, "Cisco-IOS type 8 (PBKDF2-SHA256)", "9200", "pbkdf2-hmac-sha256"),
        Rule(#"^\$9\$[./A-Za-z0-9]{14}\$[./A-Za-z0-9]{43}$"#, "Cisco-IOS type 9 (scrypt)", "9300", "scrypt"),
        Rule(#"^\$9\$[^$]+$"#, "Juniper $9$ (reversible obfuscation)", "—", "—", note: "use the Juniper $9$ decode operation"),
        Rule(#"^AK1[A-Za-z0-9+/=]+$"#, "FortiGate (FortiOS)", "7000", "fortigate"),
        Rule(#"^SH2[A-Za-z0-9+/=]+$"#, "FortiGate256 (FortiOS 7+)", "26300", "fortigate256"),

        // Web applications
        Rule(#"^\$[PH]\$[./A-Za-z0-9]{31}$"#, "phpass (WordPress < 6.8, phpBB3, Joomla ≥ 2.5.18 portable)", "400", "phpass"),
        Rule(#"^\$S\$[./A-Za-z0-9]{52}$"#, "Drupal 7", "7900", "drupal7"),
        Rule(#"^pbkdf2_sha256\$\d+\$[^$]+\$[A-Za-z0-9+/=]+$"#, "Django PBKDF2-SHA256", "10000", "django"),
        Rule(#"^pbkdf2_sha1\$\d+\$"#, "Django PBKDF2-SHA1", "— (convert to sha1:iterations:salt:hash, 12000)", "—"),
        Rule(#"^sha1\$[^$]*\$[0-9a-fA-F]{40}$"#, "Django SHA-1 (sha1$salt$hash)", "124", "—"),
        Rule(#"^md5\$[^$]*\$[0-9a-fA-F]{32}$"#, "Django MD5 (md5$salt$hash)", "— (20 as hash:salt)", "dynamic_4"),
        Rule(#"^bcrypt_sha256\$\$2[aby]\$"#, "Django bcrypt_sha256 (bcrypt of sha256($pass))", "—", "—"),
        Rule(#"^bcrypt\$\$2[aby]\$"#, "Django bcrypt — strip the bcrypt$ prefix", "3200", "bcrypt"),
        Rule(#"^argon2\$argon2"#, "Django Argon2 — strip the argon2$ prefix", "34000 (hashcat ≥ 7.0)", "argon2"),
        Rule(#"^\$episerver\$\*[01]\*"#, "EPiServer 6.x", "141 / 1441", "episerver"),

        // LDAP / directory / AIX
        Rule(#"^\{SSHA\}"#, "LDAP salted SHA-1 ({SSHA})", "111", "salted-sha1"),
        Rule(#"^\{SHA\}"#, "LDAP SHA-1 ({SHA}, Base64)", "101", "nsldap"),
        Rule(#"^\{SSHA256\}"#, "LDAP salted SHA-256 ({SSHA256})", "1411", "—"),
        Rule(#"^\{SHA256\}"#, "LDAP SHA-256 ({SHA256}, Base64)", "1400 (convert to hex)", "raw-sha256"),
        Rule(#"^\{SSHA512\}"#, "LDAP salted SHA-512 ({SSHA512})", "1711", "ssha512"),
        Rule(#"^\{SHA512\}"#, "LDAP SHA-512 ({SHA512}, Base64)", "1700 (convert to hex)", "raw-sha512"),
        Rule(#"^\{MD5\}"#, "LDAP MD5 ({MD5}, Base64)", "0 (convert to hex)", "raw-md5"),
        Rule(#"^\{SMD5\}"#, "LDAP salted MD5 ({SMD5})", "—", "—"),
        Rule(#"^\{PKCS5S2\}"#, "Atlassian PBKDF2-HMAC-SHA1 ({PKCS5S2})", "12001", "pbkdf2-hmac-sha1"),
        Rule(#"^\{PBKDF2[-_]SHA256\}"#, "PBKDF2-SHA256 (389-ds / passlib LDAP)", "— (convert to 10900)", "—"),
        Rule(#"^\{smd5\}"#, "AIX {smd5}", "6300", "aix-smd5"),
        Rule(#"^\{ssha1\}"#, "AIX {ssha1}", "6700", "aix-ssha1"),
        Rule(#"^\{ssha256\}"#, "AIX {ssha256}", "6400", "aix-ssha256"),
        Rule(#"^\{ssha512\}"#, "AIX {ssha512}", "6500", "aix-ssha512"),

        // Windows / Active Directory
        Rule(#"^\$NT\$[0-9a-fA-F]{32}$"#, "NTLM (john notation)", "1000", "nt"),
        Rule(#"^\$LM\$[0-9a-fA-F]{16}$"#, "LM (john notation)", "3000", "lm"),
        Rule(#"^\$DCC2\$\d+#[^#]+#[0-9a-fA-F]{32}$"#, "Domain Cached Credentials 2 (MS Cache 2)", "2100", "mscash2"),
        Rule(#"^\$krb5tgs\$23\$"#, "Kerberos 5 TGS-REP etype 23 (RC4) — Kerberoast", "13100", "krb5tgs"),
        Rule(#"^\$krb5tgs\$17\$"#, "Kerberos 5 TGS-REP etype 17 (AES128) — Kerberoast", "19600", "krb5tgs"),
        Rule(#"^\$krb5tgs\$18\$"#, "Kerberos 5 TGS-REP etype 18 (AES256) — Kerberoast", "19700", "krb5tgs"),
        Rule(#"^\$krb5tgs\$"#, "Kerberos 5 TGS-REP (no etype given — usually 23)", "13100", "krb5tgs"),
        Rule(#"^\$krb5asrep\$23\$"#, "Kerberos 5 AS-REP etype 23 — AS-REP roast", "18200", "krb5asrep"),
        Rule(#"^\$krb5asrep\$17\$"#, "Kerberos 5 AS-REP etype 17 (AES128)", "32100", "krb5asrep"),
        Rule(#"^\$krb5asrep\$18\$"#, "Kerberos 5 AS-REP etype 18 (AES256)", "32200", "krb5asrep"),
        Rule(#"^\$krb5asrep\$"#, "Kerberos 5 AS-REP (john notation, etype 23)", "18200", "krb5asrep"),
        Rule(#"^\$krb5pa\$23\$"#, "Kerberos 5 AS-REQ pre-auth etype 23", "7500", "krb5pa-md5"),
        Rule(#"^\$krb5pa\$17\$"#, "Kerberos 5 AS-REQ pre-auth etype 17", "19800", "krb5pa-sha1"),
        Rule(#"^\$krb5pa\$18\$"#, "Kerberos 5 AS-REQ pre-auth etype 18", "19900", "krb5pa-sha1"),
        Rule(#"^\$mskrb5\$"#, "Kerberos 5 AS-REQ pre-auth etype 23 (john mskrb5 notation)", "7500", "mskrb5"),
        Rule(#"^\$krb5db\$17\$"#, "Kerberos 5 database key etype 17", "28800", "—"),
        Rule(#"^\$krb5db\$18\$"#, "Kerberos 5 database key etype 18", "28900", "—"),
        Rule(#"^\$DPAPImk\$1\*"#, "DPAPI master key v1", "15300", "dpapimk"),
        Rule(#"^\$DPAPImk\$2\*"#, "DPAPI master key v2", "15900", "dpapimk"),
        Rule(#"^\$bitlocker\$"#, "BitLocker", "22100", "bitlocker"),
        Rule(#"^\$WINHELLO\$"#, "Windows Hello PIN / password", "28100", "—"),

        // Databases
        Rule(#"^\*[0-9A-Fa-f]{40}$"#, "MySQL 4.1+ / 5.x (SHA-1 of SHA-1)", "300", "mysql-sha1"),
        Rule(#"^\$A\$005\$"#, "MySQL 8 caching_sha2_password", "7401", "—"),
        Rule(#"^\$mysqlna\$"#, "MySQL network authentication (CRAM)", "11200", "mysqlna"),
        Rule(#"^md5[0-9a-f]{32}$"#, "PostgreSQL MD5 (needs hash:user)", "12", "postgres"),
        Rule(#"^SCRAM-SHA-256\$\d+:"#, "PostgreSQL SCRAM-SHA-256", "28600", "—"),
        Rule(#"^\$postgres\$"#, "PostgreSQL CRAM (MD5)", "11100", "postgres"),
        Rule(#"^0x0100[0-9A-Fa-f]{48}$"#, "MSSQL 2005", "132", "mssql05"),
        Rule(#"^0x0100[0-9A-Fa-f]{88}$"#, "MSSQL 2000", "131", "mssql"),
        Rule(#"^0x0200[0-9A-Fa-f]{136}$"#, "MSSQL 2012 / 2014+", "1731", "mssql12"),
        Rule(#"^0xc007[0-9A-Fa-f]+$"#, "Sybase ASE", "8000", "sybasease"),
        Rule(#"^S:[0-9A-Fa-f]{60}$"#, "Oracle 11g (S:)", "112", "oracle11"),
        Rule(#"^T:[0-9A-Fa-f]{160}$"#, "Oracle 12c (T:)", "12300", "oracle12c"),
        Rule(#"^H:[0-9A-Fa-f]{32}$"#, "Oracle 11g (H:, MD5 of user:password)", "—", "—"),

        // Documents, archives, wallets, keys, wireless
        Rule(#"^\$office\$\*2007\*"#, "MS Office 2007", "9400", "office"),
        Rule(#"^\$office\$\*2010\*"#, "MS Office 2010", "9500", "office"),
        Rule(#"^\$office\$\*2013\*"#, "MS Office 2013+", "9600", "office"),
        Rule(#"^\$oldoffice\$\*[01]\*"#, "MS Office ≤ 2003 (MD5 + RC4)", "9700", "oldoffice"),
        Rule(#"^\$oldoffice\$\*[34]\*"#, "MS Office ≤ 2003 (SHA-1 + RC4)", "9800", "oldoffice"),
        Rule(#"^\$pdf\$1\*"#, "PDF 1.1–1.3 (Acrobat 2–4)", "10400", "pdf"),
        Rule(#"^\$pdf\$[24]\*"#, "PDF 1.4–1.6 (Acrobat 5–8)", "10500", "pdf"),
        Rule(#"^\$pdf\$5\*5\*"#, "PDF 1.7 Level 3 (Acrobat 9)", "10600", "pdf"),
        Rule(#"^\$pdf\$5\*6\*"#, "PDF 1.7 Level 8 (Acrobat 10–11)", "10700", "pdf"),
        Rule(#"^\$zip2\$"#, "WinZip (AES)", "13600", "zip"),
        Rule(#"^\$pkzip2?\$"#, "PKZIP", "17200–17230", "pkzip"),
        Rule(#"^\$rar5\$"#, "RAR5", "13000", "rar5"),
        Rule(#"^\$RAR3\$\*0\*"#, "RAR3-hp (encrypted headers)", "12500", "rar"),
        Rule(#"^\$RAR3\$\*1\*"#, "RAR3-p", "23700 / 23800", "rar"),
        Rule(#"^\$7z\$"#, "7-Zip", "11600", "7z"),
        Rule(#"^\$keepass\$"#, "KeePass 1.x / 2.x", "13400", "keepass"),
        Rule(#"^\$gpg\$"#, "GPG secret key", "17010", "gpg"),
        Rule(#"^\$sshng\$"#, "OpenSSH / RSA / DSA / EC private key", "22911 / 22921 / 22931 / 22941 / 22951", "ssh"),
        Rule(#"^\$bitcoin\$"#, "Bitcoin / Litecoin wallet.dat", "11300", "bitcoin"),
        Rule(#"^\$ethereum\$p\*"#, "Ethereum wallet (PBKDF2)", "15600", "ethereum"),
        Rule(#"^\$ethereum\$s\*"#, "Ethereum wallet (scrypt)", "15700", "ethereum"),
        Rule(#"^\$luks\$"#, "LUKS", "14600", "luks"),
        Rule(#"^\$itunes_backup\$\*9\*"#, "iTunes backup < 10", "14700", "itunes-backup"),
        Rule(#"^\$itunes_backup\$\*10\*"#, "iTunes backup ≥ 10", "14800", "itunes-backup"),
        Rule(#"^\$ab\$"#, "Android backup", "18900", "androidbackup"),
        Rule(#"^\$odf\$"#, "OpenDocument (ODF)", "18400 / 18600", "odf"),
        Rule(#"^\$axcrypt\$"#, "AxCrypt", "13200 / 23500", "axcrypt"),
        Rule(#"^\$telegram\$"#, "Telegram", "22301 / 22600 / 24500", "telegram"),
        Rule(#"^\$WPAPSK\$"#, "WPA/WPA2 PSK (legacy notation)", "22000", "wpapsk"),
        Rule(#"^WPA\*0[12]\*"#, "WPA/WPA2 PMKID + EAPOL (hc22000)", "22000", "wpapsk"),
        Rule(#"^\$sip\$"#, "SIP digest", "11400", "sip"),
        Rule(#"^\$cram_md5\$"#, "CRAM-MD5", "10200", "cram-md5"),
        Rule(#"^\$racf\$"#, "RACF", "8500", "racf"),
        Rule(#"^\$sntp-ms\$"#, "MS SNTP", "31300", "sntp-ms"),
        Rule(#"^\$radmin3\$"#, "Radmin 3", "29200", "radmin3"),

        // Things that look like hashes but are not password hashes
        Rule(#"^\$HEX\["#, "hashcat $HEX[…] notation — a hex-encoded candidate or plaintext, not a hash", "—", "—"),
        Rule(#"^SHA256:[A-Za-z0-9+/]{43}$"#, "SSH key fingerprint (SHA-256) — not a password hash", "—", "—"),
        Rule(#"^MD5:(?:[0-9a-f]{2}:){15}[0-9a-f]{2}$"#, "SSH key fingerprint (MD5) — not a password hash", "—", "—"),
        Rule(#"^eyJ[A-Za-z0-9_-]*\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]*$"#, "JWT (JSON Web Token)", "16500", "— (jwt2john → hmac-sha256)",
             note: "use the JWT decode operation to read header and payload"),
    ]
}

/// Cisco type 7 "encryption": a Vigenère-style XOR with a fixed key; the first two digits are
/// the starting offset into the key. Reversible, which is why it is worth having here.
enum CiscoType7 {
    private static let key = Array("dsfd;kfoA,.iyewrkldJKDHSUBsgvca69834ncxv9873254k;fg87".utf8)

    static func decode(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 4, t.count % 2 == 0, t.allSatisfy({ $0.isHexDigit }),
              let seed = Int(t.prefix(2)), seed <= 15 else { return nil }
        var bytes: [UInt8] = []
        var position = seed
        var index = t.index(t.startIndex, offsetBy: 2)
        while index < t.endIndex {
            let next = t.index(index, offsetBy: 2)
            guard let byte = UInt8(t[index..<next], radix: 16) else { return nil }
            bytes.append(byte ^ key[position % key.count])
            position += 1
            index = next
        }
        guard bytes.allSatisfy({ $0 >= 32 && $0 < 127 }), let decoded = String(bytes: bytes, encoding: .utf8) else { return nil }
        return decoded
    }

    static func encode(_ text: String, seed: Int = 7) -> String {
        let start = max(0, min(15, seed))
        var out = String(format: "%02d", start)
        for (offset, byte) in text.utf8.enumerated() {
            out += String(format: "%02X", byte ^ key[(start + offset) % key.count])
        }
        return out
    }
}

/// Juniper "$9$" secrets: the reversible obfuscation used for most secrets in JunOS
/// configurations (the algorithm known from junosdecode / junos-eznc).
enum JuniperSecret {
    private static let family = ["QzF3n6/9CAtpu0O", "B1IREhcSyrleKvMW8LXx", "7N-dVbwsY2g4oaJZGUDj", "iHkq.mPf5T"]
    private static let alphabet: [Character] = Array(family.joined())
    private static let position: [Character: Int] = Dictionary(uniqueKeysWithValues: alphabet.enumerated().map { ($1, $0) })
    private static let extra: [Character: Int] = {
        var table: [Character: Int] = [:]
        for (index, group) in family.enumerated() {
            for character in group { table[character] = 3 - index }
        }
        return table
    }()
    private static let encoding = [[1, 4, 32], [1, 16, 32], [1, 8, 32], [1, 64], [1, 32], [1, 4, 16, 128], [1, 32, 64]]

    static func decode(_ text: String) -> String? {
        var secret = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if secret.hasPrefix("\""), secret.hasSuffix("\""), secret.count >= 2 { secret = String(secret.dropFirst().dropLast()) }
        guard secret.hasPrefix("$9$") else { return nil }
        var chars = Array(secret.dropFirst(3))
        guard let first = chars.first, let skip = extra[first], chars.count > skip + 1 else { return nil }
        chars.removeFirst(1 + skip)
        var previous = first
        var bytes: [UInt8] = []
        while !chars.isEmpty {
            let decode = encoding[bytes.count % encoding.count]
            guard chars.count >= decode.count else { return nil }
            let nibble = Array(chars.prefix(decode.count))
            chars.removeFirst(decode.count)
            var value = 0
            for (character, weight) in zip(nibble, decode) {
                guard let a = position[character], let b = position[previous] else { return nil }
                let gap = ((a - b) % alphabet.count + alphabet.count) % alphabet.count - 1
                value += gap * weight
                previous = character
            }
            bytes.append(UInt8(((value % 256) + 256) % 256))
        }
        guard bytes.allSatisfy({ $0 >= 32 && $0 < 127 }), let decoded = String(bytes: bytes, encoding: .utf8) else { return nil }
        return decoded
    }

    /// The inverse, so the decoder can be checked (and a value re-encoded for a configuration).
    static func encode(_ text: String, salt saltCharacter: Character? = nil) -> String {
        let salt = saltCharacter.flatMap { position[$0] != nil ? $0 : nil } ?? alphabet[Int(text.utf8.count) % alphabet.count]
        var out = "$9$" + String(salt)
        for i in 0..<(extra[salt] ?? 0) { out.append(alphabet[(i * 7 + 3) % alphabet.count]) }
        var previous = salt
        for (index, byte) in text.utf8.enumerated() {
            let encode = encoding[index % encoding.count]
            var remainder = Int(byte)
            var gaps: [Int] = []
            for weight in encode.reversed() {
                gaps.insert(remainder / weight, at: 0)
                remainder %= weight
            }
            for gap in gaps {
                let next = alphabet[(gap + (position[previous] ?? 0) + 1) % alphabet.count]
                out.append(next)
                previous = next
            }
        }
        return out
    }
}
