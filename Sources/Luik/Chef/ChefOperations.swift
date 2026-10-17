import CryptoKit
import Foundation

/// A parameter an operation can take (shown as a small editor in the recipe step).
struct ChefParam: Identifiable {
    enum Kind {
        case text
        case number
        case choice([String])
        case toggle
    }

    let id: String         // key in the step's values
    let label: String
    let kind: Kind
    let defaultValue: String
}

enum ChefError: LocalizedError {
    case invalidInput(String)

    var errorDescription: String? {
        switch self {
        case .invalidInput(let message): return message
        }
    }
}

/// One operation: name, category, parameters and the transformation itself (bytes in, bytes out).
struct ChefOperation: Identifiable {
    let id: String
    let name: String
    let category: String
    let params: [ChefParam]
    let run: (Data, [String: String]) throws -> Data

    init(_ id: String, _ name: String, _ category: String, params: [ChefParam] = [],
         run: @escaping (Data, [String: String]) throws -> Data) {
        self.id = id
        self.name = name
        self.category = category
        self.params = params
        self.run = run
    }

    /// Text-in/text-out convenience.
    static func text(_ id: String, _ name: String, _ category: String, params: [ChefParam] = [],
                     _ transform: @escaping (String, [String: String]) throws -> String) -> ChefOperation {
        ChefOperation(id, name, category, params: params) { data, values in
            Data(try transform(ChefText.string(data), values).utf8)
        }
    }
}

enum ChefText {
    static func string(_ data: Data) -> String {
        String(decoding: data, as: UTF8.self)
    }

    static func param(_ values: [String: String], _ op: ChefOperation, _ key: String) -> String {
        values[key] ?? op.params.first { $0.id == key }?.defaultValue ?? ""
    }
}

// MARK: - Catalogue

enum ChefCatalogue {
    static let all: [ChefOperation] = encodings + hashes + text + dataFormats + extract + network + dates + units

    static func operation(_ id: String) -> ChefOperation? {
        all.first { $0.id == id }
    }

    static var categories: [String] {
        var seen: [String] = []
        for op in all where !seen.contains(op.category) { seen.append(op.category) }
        return seen
    }

    // MARK: Encodings

    static let encodings: [ChefOperation] = [
        ChefOperation("to-base64", "To Base64", "Encoding",
                      params: [ChefParam(id: "urlsafe", label: "URL-safe", kind: .toggle, defaultValue: "false")]) { data, v in
            var s = data.base64EncodedString()
            if v["urlsafe"] == "true" {
                s = s.replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
            }
            return Data(s.utf8)
        },
        ChefOperation("from-base64", "From Base64", "Encoding") { data, _ in
            guard let decoded = Base64.decodeLenient(ChefText.string(data)) else {
                throw ChefError.invalidInput("Not valid Base64.")
            }
            return decoded
        },
        ChefOperation("to-base32", "To Base32", "Encoding") { data, _ in Data(Base32.encode(data).utf8) },
        ChefOperation("from-base32", "From Base32", "Encoding") { data, _ in
            guard let decoded = Base32.decode(ChefText.string(data)) else { throw ChefError.invalidInput("Not valid Base32.") }
            return decoded
        },
        ChefOperation("to-hex", "To Hex", "Encoding",
                      params: [ChefParam(id: "delimiter", label: "Delimiter", kind: .choice(["none", "space", "colon", "comma", "0x", "\\x"]), defaultValue: "none"),
                               ChefParam(id: "upper", label: "Upper case", kind: .toggle, defaultValue: "false")]) { data, v in
            let upper = v["upper"] == "true"
            let bytes = data.map { upper ? String(format: "%02X", $0) : String(format: "%02x", $0) }
            let joined: String
            switch v["delimiter"] ?? "none" {
            case "space": joined = bytes.joined(separator: " ")
            case "colon": joined = bytes.joined(separator: ":")
            case "comma": joined = bytes.joined(separator: ",")
            case "0x": joined = bytes.map { "0x" + $0 }.joined(separator: " ")
            case "\\x": joined = bytes.map { "\\x" + $0 }.joined()
            default: joined = bytes.joined()
            }
            return Data(joined.utf8)
        },
        ChefOperation("from-hex", "From Hex", "Encoding") { data, _ in
            guard let decoded = Hex.decode(ChefText.string(data)) else { throw ChefError.invalidInput("Not valid hex.") }
            return decoded
        },
        ChefOperation("to-binary", "To Binary", "Encoding") { data, _ in
            Data(data.map { String($0, radix: 2).leftPadded(to: 8) }.joined(separator: " ").utf8)
        },
        ChefOperation("from-binary", "From Binary", "Encoding") { data, _ in
            let cleaned = ChefText.string(data).filter { $0 == "0" || $0 == "1" }
            guard !cleaned.isEmpty, cleaned.count % 8 == 0 else { throw ChefError.invalidInput("Binary needs whole bytes (multiples of 8 bits).") }
            var out = Data()
            var index = cleaned.startIndex
            while index < cleaned.endIndex {
                let end = cleaned.index(index, offsetBy: 8)
                out.append(UInt8(cleaned[index..<end], radix: 2)!)
                index = end
            }
            return out
        },
        ChefOperation.text("url-encode", "URL Encode", "Encoding",
                           params: [ChefParam(id: "all", label: "Encode all characters", kind: .toggle, defaultValue: "false")]) { s, v in
            let allowed: CharacterSet = v["all"] == "true" ? CharacterSet() : CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+?/#:;,$@"))
            return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
        },
        ChefOperation.text("url-decode", "URL Decode", "Encoding") { s, _ in
            (s.replacingOccurrences(of: "+", with: " ").removingPercentEncoding) ?? s
        },
        ChefOperation.text("html-encode", "To HTML Entities", "Encoding") { s, _ in
            var out = ""
            for scalar in s.unicodeScalars {
                switch scalar {
                case "&": out += "&amp;"
                case "<": out += "&lt;"
                case ">": out += "&gt;"
                case "\"": out += "&quot;"
                case "'": out += "&#39;"
                default:
                    if scalar.isASCII { out.unicodeScalars.append(scalar) } else { out += "&#\(scalar.value);" }
                }
            }
            return out
        },
        ChefOperation.text("html-decode", "From HTML Entities", "Encoding") { s, _ in HTMLEntities.decode(s) },
        ChefOperation.text("unicode-escape", "Unicode Escape (\\u)", "Encoding") { s, _ in
            s.unicodeScalars.map { scalar in
                if scalar.isASCII && scalar.value >= 32 && scalar.value < 127 { return String(scalar) }
                if scalar.value > 0xFFFF {
                    let v = scalar.value - 0x10000
                    return String(format: "\\u%04X\\u%04X", 0xD800 + (v >> 10), 0xDC00 + (v & 0x3FF))
                }
                return String(format: "\\u%04X", scalar.value)
            }.joined()
        },
        ChefOperation.text("unicode-unescape", "Unicode Unescape", "Encoding") { s, _ in
            let regex = try! NSRegularExpression(pattern: #"\\u([0-9a-fA-F]{4})|\\x([0-9a-fA-F]{2})"#)
            var utf16: [UInt16] = []
            var result = ""
            var last = s.startIndex
            for m in regex.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
                guard let range = Range(m.range, in: s) else { continue }
                result += s[last..<range.lowerBound]
                let hex = m.range(at: 1).location != NSNotFound ? (s as NSString).substring(with: m.range(at: 1)) : (s as NSString).substring(with: m.range(at: 2))
                utf16 = [UInt16(hex, radix: 16) ?? 0]
                result += String(utf16CodeUnits: utf16, count: 1)
                last = range.upperBound
            }
            result += s[last...]
            return result
        },
        ChefOperation.text("charcode-to", "To Char Codes", "Encoding",
                           params: [ChefParam(id: "base", label: "Base", kind: .choice(["decimal", "hex"]), defaultValue: "decimal")]) { s, v in
            s.unicodeScalars.map { v["base"] == "hex" ? String(format: "%x", $0.value) : String($0.value) }.joined(separator: " ")
        },
        ChefOperation.text("charcode-from", "From Char Codes", "Encoding",
                           params: [ChefParam(id: "base", label: "Base", kind: .choice(["decimal", "hex"]), defaultValue: "decimal")]) { s, v in
            let radix = v["base"] == "hex" ? 16 : 10
            var out = ""
            for token in s.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\n" || $0 == "\t" }) {
                guard let value = UInt32(token, radix: radix), let scalar = UnicodeScalar(value) else {
                    throw ChefError.invalidInput("Not a valid char code: \(token)")
                }
                out.unicodeScalars.append(scalar)
            }
            return out
        },
        ChefOperation.text("rot13", "ROT13", "Encoding") { s, _ in Caesar.shift(s, by: 13) },
        ChefOperation.text("caesar", "Caesar / ROT-N", "Encoding",
                           params: [ChefParam(id: "shift", label: "Shift", kind: .number, defaultValue: "3")]) { s, v in
            Caesar.shift(s, by: Int(v["shift"] ?? "3") ?? 3)
        },
        ChefOperation("xor", "XOR", "Encoding",
                      params: [ChefParam(id: "key", label: "Key", kind: .text, defaultValue: ""),
                               ChefParam(id: "keyformat", label: "Key format", kind: .choice(["text", "hex"]), defaultValue: "text")]) { data, v in
            let keyText = v["key"] ?? ""
            let key: Data = v["keyformat"] == "hex" ? (Hex.decode(keyText) ?? Data()) : Data(keyText.utf8)
            guard !key.isEmpty else { throw ChefError.invalidInput("Enter a key.") }
            let keyBytes = [UInt8](key)
            return Data(data.enumerated().map { $0.element ^ keyBytes[$0.offset % keyBytes.count] })
        },
        ChefOperation.text("jwt-decode", "JWT Decode", "Encoding") { s, _ in
            let parts = s.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".")
            guard parts.count >= 2 else { throw ChefError.invalidInput("A JWT has three dot-separated parts.") }
            func pretty(_ part: Substring) -> String {
                guard let data = Base64.decodeLenient(String(part)) else { return "(not Base64)" }
                return JSONFormat.pretty(data) ?? ChefText.string(data)
            }
            var out = "Header:\n\(pretty(parts[0]))\n\nPayload:\n\(pretty(parts[1]))"
            if parts.count > 2 {
                out += "\n\nSignature (Base64url): \(parts[2])"
            }
            if let payload = Base64.decodeLenient(String(parts[1])),
               let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] {
                for key in ["exp", "iat", "nbf"] {
                    if let value = json[key] as? Double {
                        let date = Date(timeIntervalSince1970: value)
                        out += "\n\(key): \(ISO8601DateFormatter().string(from: date))" + (key == "exp" && date < Date() ? " (expired)" : "")
                    }
                }
            }
            return out
        },
        ChefOperation.text("jwt-sign", "JWT Encode / sign", "Encoding",
                           params: [ChefParam(id: "secret", label: "Secret", kind: .text, defaultValue: ""),
                                    ChefParam(id: "alg", label: "Algorithm", kind: .choice(["HS256", "HS384", "HS512", "none"]), defaultValue: "HS256")]) { s, v in
            // Input: the payload as JSON (or an existing token, whose payload is re-signed).
            let input = s.trimmingCharacters(in: .whitespacesAndNewlines)
            var payloadData = Data(input.utf8)
            if input.split(separator: ".").count >= 2, !input.hasPrefix("{"),
               let decoded = Base64.decodeLenient(String(input.split(separator: ".")[1])) {
                payloadData = decoded
            }
            guard (try? JSONSerialization.jsonObject(with: payloadData)) != nil else {
                throw ChefError.invalidInput("The input must be the payload as JSON (e.g. {\"sub\":\"1\",\"admin\":true}) or a JWT.")
            }
            let alg = v["alg"] ?? "HS256"
            let header = "{\"alg\":\"\(alg)\",\"typ\":\"JWT\"}"
            let signingInput = Base64.urlEncode(Data(header.utf8)) + "." + Base64.urlEncode(payloadData)
            let secret = Data((v["secret"] ?? "").utf8)
            let signature: String
            switch alg {
            case "none": signature = ""
            case "HS384": signature = Base64.urlEncode(Data(HMAC<SHA384>.authenticationCode(for: Data(signingInput.utf8), using: SymmetricKey(data: secret))))
            case "HS512": signature = Base64.urlEncode(Data(HMAC<SHA512>.authenticationCode(for: Data(signingInput.utf8), using: SymmetricKey(data: secret))))
            default: signature = Base64.urlEncode(Data(HMAC<SHA256>.authenticationCode(for: Data(signingInput.utf8), using: SymmetricKey(data: secret))))
            }
            return signingInput + "." + signature
        },
        ChefOperation.text("jwt-verify", "JWT Verify (HMAC)", "Encoding",
                           params: [ChefParam(id: "secret", label: "Secret", kind: .text, defaultValue: "")]) { s, v in
            let parts = s.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".", omittingEmptySubsequences: false)
            guard parts.count == 3, let headerData = Base64.decodeLenient(String(parts[0])),
                  let header = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any],
                  let alg = header["alg"] as? String else {
                throw ChefError.invalidInput("Not a JWT (header.payload.signature).")
            }
            let signingInput = Data((String(parts[0]) + "." + String(parts[1])).utf8)
            let key = SymmetricKey(data: Data((v["secret"] ?? "").utf8))
            let expected: Data?
            switch alg.uppercased() {
            case "HS256": expected = Data(HMAC<SHA256>.authenticationCode(for: signingInput, using: key))
            case "HS384": expected = Data(HMAC<SHA384>.authenticationCode(for: signingInput, using: key))
            case "HS512": expected = Data(HMAC<SHA512>.authenticationCode(for: signingInput, using: key))
            case "NONE": return parts[2].isEmpty ? "alg none — no signature; accepted only by broken verifiers." : "alg none but a signature is present."
            default: return "Algorithm \(alg) is not an HMAC; only HS256/384/512 can be checked with a secret here."
            }
            let given = Base64.decodeLenient(String(parts[2]))
            return expected == given ? "Valid: the signature matches the secret (\(alg))." : "Invalid: the signature does not match this secret (\(alg))."
        },
        ChefOperation.text("ps-encode", "PowerShell -EncodedCommand", "Encoding") { s, _ in
            var utf16 = Data()
            for unit in s.utf16 {
                utf16.append(UInt8(unit & 0xFF))
                utf16.append(UInt8(unit >> 8))
            }
            return utf16.base64EncodedString()
        },
        ChefOperation.text("ps-decode", "PowerShell -EncodedCommand decode", "Encoding") { s, _ in
            guard let data = Base64.decodeLenient(s) else { throw ChefError.invalidInput("Not Base64.") }
            return String(data: data, encoding: .utf16LittleEndian) ?? ""
        },
        ChefOperation("to-base58", "To Base58", "Encoding") { data, _ in
            Data(Base58.encode(data).utf8)
        },
        ChefOperation("from-base58", "From Base58", "Encoding") { data, _ in
            guard let decoded = Base58.decode(ChefText.string(data).trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw ChefError.invalidInput("Not Base58.")
            }
            return decoded
        },
        ChefOperation.text("url-encode-double", "URL Encode (double)", "Encoding") { s, _ in
            let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
            let once = s.addingPercentEncoding(withAllowedCharacters: unreserved) ?? s
            return once.addingPercentEncoding(withAllowedCharacters: unreserved) ?? once
        },
        ChefOperation.text("json-escape", "JSON string escape", "Encoding") { s, _ in
            let data = try JSONSerialization.data(withJSONObject: [s], options: [.withoutEscapingSlashes])
            let text = ChefText.string(data)
            return String(text.dropFirst(2).dropLast(2))
        },
        ChefOperation.text("json-unescape", "JSON string unescape", "Encoding") { s, _ in
            let wrapped = "[\"" + s + "\"]"
            guard let array = try? JSONSerialization.jsonObject(with: Data(wrapped.utf8)) as? [String], let first = array.first else {
                throw ChefError.invalidInput("Not a JSON-escaped string.")
            }
            return first
        },
        ChefOperation.text("shell-quote", "Shell single-quote", "Encoding") { s, _ in
            "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
        },
    ]

    // MARK: Hashes

    static let hashes: [ChefOperation] = [
        ChefOperation("md5", "MD5", "Hashing") { data, _ in Data(Insecure.MD5.hash(data: data).hexString.utf8) },
        ChefOperation("sha1", "SHA-1", "Hashing") { data, _ in Data(Insecure.SHA1.hash(data: data).hexString.utf8) },
        ChefOperation("sha256", "SHA-256", "Hashing") { data, _ in Data(SHA256.hash(data: data).hexString.utf8) },
        ChefOperation("sha384", "SHA-384", "Hashing") { data, _ in Data(SHA384.hash(data: data).hexString.utf8) },
        ChefOperation("sha512", "SHA-512", "Hashing") { data, _ in Data(SHA512.hash(data: data).hexString.utf8) },
        ChefOperation("crc32", "CRC-32", "Hashing") { data, _ in Data(String(format: "%08x", CRC32.checksum(data)).utf8) },
        ChefOperation("hmac", "HMAC", "Hashing",
                      params: [ChefParam(id: "key", label: "Key", kind: .text, defaultValue: ""),
                               ChefParam(id: "algo", label: "Algorithm", kind: .choice(["SHA-256", "SHA-1", "SHA-512", "MD5"]), defaultValue: "SHA-256")]) { data, v in
            let key = SymmetricKey(data: Data((v["key"] ?? "").utf8))
            let hex: String
            switch v["algo"] ?? "SHA-256" {
            case "SHA-1": hex = Data(HMAC<Insecure.SHA1>.authenticationCode(for: data, using: key)).hexString
            case "SHA-512": hex = Data(HMAC<SHA512>.authenticationCode(for: data, using: key)).hexString
            case "MD5": hex = Data(HMAC<Insecure.MD5>.authenticationCode(for: data, using: key)).hexString
            default: hex = Data(HMAC<SHA256>.authenticationCode(for: data, using: key)).hexString
            }
            return Data(hex.utf8)
        },
        ChefOperation.text("identify-hash", "Identify hash", "Hashing") { s, _ in
            // One hash (or hash-bearing line) per input line: bare digests, hash:salt, user:hash,
            // shadow / pwdump / NetNTLM lines, Cisco configuration lines, checksum lines…
            let lines = s.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard !lines.isEmpty else { return "" }
            return lines.map { HashIdentifier.report($0) }.joined(separator: "\n\n")
        },
        ChefOperation("hash-all", "All hashes", "Hashing") { data, _ in
            let lines = [
                "MD5:     \(Insecure.MD5.hash(data: data).hexString)",
                "SHA-1:   \(Insecure.SHA1.hash(data: data).hexString)",
                "SHA-256: \(SHA256.hash(data: data).hexString)",
                "SHA-512: \(SHA512.hash(data: data).hexString)",
                "CRC-32:  \(String(format: "%08x", CRC32.checksum(data)))",
                "Length:  \(data.count) bytes",
            ]
            return Data(lines.joined(separator: "\n").utf8)
        },
    ]

    // MARK: Text

    static let text: [ChefOperation] = [
        ChefOperation.text("upper", "Upper case", "Text") { s, _ in s.uppercased() },
        ChefOperation.text("lower", "Lower case", "Text") { s, _ in s.lowercased() },
        ChefOperation.text("reverse", "Reverse", "Text") { s, _ in String(s.reversed()) },
        ChefOperation.text("trim", "Trim whitespace", "Text") { s, _ in s.trimmingCharacters(in: .whitespacesAndNewlines) },
        ChefOperation.text("remove-whitespace", "Remove whitespace", "Text") { s, _ in s.filter { !$0.isWhitespace } },
        ChefOperation.text("remove-newlines", "Join lines", "Text",
                           params: [ChefParam(id: "sep", label: "Separator", kind: .text, defaultValue: "")]) { s, v in
            s.components(separatedBy: .newlines).filter { !$0.isEmpty }.joined(separator: v["sep"] ?? "")
        },
        ChefOperation.text("split", "Split to lines", "Text",
                           params: [ChefParam(id: "sep", label: "Split on", kind: .text, defaultValue: ",")]) { s, v in
            let sep = v["sep"] ?? ","
            return sep.isEmpty ? s : s.components(separatedBy: sep).joined(separator: "\n")
        },
        ChefOperation.text("sort", "Sort lines", "Text") { s, _ in s.components(separatedBy: "\n").sorted().joined(separator: "\n") },
        ChefOperation.text("unique", "Unique lines", "Text") { s, _ in
            var seen: Set<String> = []
            return s.components(separatedBy: "\n").filter { seen.insert($0).inserted }.joined(separator: "\n")
        },
        ChefOperation.text("count", "Count", "Text") { s, _ in
            let lines = s.isEmpty ? 0 : s.components(separatedBy: "\n").count
            let words = s.split { $0.isWhitespace }.count
            return "Characters: \(s.count)\nBytes (UTF-8): \(s.utf8.count)\nWords: \(words)\nLines: \(lines)"
        },
        ChefOperation.text("find-replace", "Find / Replace (regex)", "Text",
                           params: [ChefParam(id: "find", label: "Find", kind: .text, defaultValue: ""),
                                    ChefParam(id: "replace", label: "Replace", kind: .text, defaultValue: ""),
                                    ChefParam(id: "regex", label: "Regex", kind: .toggle, defaultValue: "true"),
                                    ChefParam(id: "ci", label: "Ignore case", kind: .toggle, defaultValue: "false")]) { s, v in
            let find = v["find"] ?? ""
            guard !find.isEmpty else { return s }
            let replacement = (v["replace"] ?? "").replacingOccurrences(of: "\\n", with: "\n").replacingOccurrences(of: "\\t", with: "\t")
            var options: String.CompareOptions = []
            if v["regex"] != "false" { options.insert(.regularExpression) }
            if v["ci"] == "true" { options.insert(.caseInsensitive) }
            return s.replacingOccurrences(of: find, with: replacement, options: options)
        },
        ChefOperation.text("regex-extract", "Regex extract", "Text",
                           params: [ChefParam(id: "pattern", label: "Pattern", kind: .text, defaultValue: ""),
                                    ChefParam(id: "ci", label: "Ignore case", kind: .toggle, defaultValue: "true")]) { s, v in
            let pattern = v["pattern"] ?? ""
            guard !pattern.isEmpty else { return "" }
            let regex = try NSRegularExpression(pattern: pattern, options: v["ci"] == "false" ? [] : [.caseInsensitive])
            return regex.matches(in: s, range: NSRange(s.startIndex..., in: s)).compactMap { m in
                Range(m.range, in: s).map { String(s[$0]) }
            }.joined(separator: "\n")
        },
    ]

    // MARK: Data formats

    static let dataFormats: [ChefOperation] = [
        ChefOperation("json-pretty", "JSON Beautify", "Data formats") { data, _ in
            guard let pretty = JSONFormat.pretty(data) else { throw ChefError.invalidInput("Not valid JSON.") }
            return Data(pretty.utf8)
        },
        ChefOperation("json-minify", "JSON Minify", "Data formats") { data, _ in
            guard let object = try? JSONSerialization.jsonObject(with: data),
                  let out = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
                throw ChefError.invalidInput("Not valid JSON.")
            }
            return out
        },
        ChefOperation("gzip", "Gzip", "Data formats") { data, _ in try Gzip.compress(data) },
        ChefOperation("gunzip", "Gunzip", "Data formats") { data, _ in try Gzip.decompress(data) },
        ChefOperation("zlib-deflate", "Zlib Deflate", "Data formats") { data, _ in try Zlib.deflate(data) },
        ChefOperation("zlib-inflate", "Zlib Inflate", "Data formats") { data, _ in try Zlib.inflate(data) },
        ChefOperation("hexdump", "Hexdump", "Data formats") { data, _ in
            var lines: [String] = []
            let bytes = [UInt8](data)
            var offset = 0
            while offset < bytes.count {
                let chunk = bytes[offset..<min(offset + 16, bytes.count)]
                let hex = chunk.map { String(format: "%02x", $0) }.joined(separator: " ")
                let ascii = chunk.map { $0 >= 32 && $0 < 127 ? String(UnicodeScalar($0)) : "." }.joined()
                lines.append(String(format: "%08x  %-48s |%@|", offset, (hex as NSString).utf8String!, ascii))
                offset += 16
            }
            return Data(lines.joined(separator: "\n").utf8)
        },
        ChefOperation("from-hexdump", "From Hexdump", "Data formats") { data, _ in
            var out = Data()
            for line in ChefText.string(data).components(separatedBy: .newlines) {
                var body = line
                if let colon = line.firstIndex(of: " "), line.prefix(8).allSatisfy({ $0.isHexDigit }) {
                    body = String(line[colon...])
                }
                if let bar = body.firstIndex(of: "|") { body = String(body[..<bar]) }
                if let decoded = Hex.decode(body) { out.append(decoded) }
            }
            return out
        },
    ]

    // MARK: Extract

    static let extract: [ChefOperation] = [
        ChefOperation.text("extract-ips", "Extract IPv4 addresses", "Extract") { s, _ in
            Extract.matches(#"\b(?:\d{1,3}\.){3}\d{1,3}\b"#, in: s)
        },
        ChefOperation.text("extract-urls", "Extract URLs", "Extract") { s, _ in
            Extract.matches(#"https?://[^\s"'<>]+"#, in: s)
        },
        ChefOperation.text("extract-emails", "Extract email addresses", "Extract") { s, _ in
            Extract.matches(#"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#, in: s)
        },
        ChefOperation.text("extract-domains", "Extract domains", "Extract") { s, _ in
            Extract.matches(#"\b(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,}\b"#, in: s.lowercased())
        },
        ChefOperation.text("extract-hashes", "Extract hashes (MD5/SHA)", "Extract") { s, _ in
            Extract.matches(#"\b[a-fA-F0-9]{32}\b|\b[a-fA-F0-9]{40}\b|\b[a-fA-F0-9]{64}\b"#, in: s)
        },
        ChefOperation.text("extract-cves", "Extract CVE IDs", "Extract") { s, _ in
            Extract.matches(#"CVE-\d{4}-\d{4,}"#, in: s.uppercased())
        },
        ChefOperation.text("strings", "Strings (printable runs)", "Extract",
                           params: [ChefParam(id: "min", label: "Min length", kind: .number, defaultValue: "4")]) { s, v in
            let minimum = Int(v["min"] ?? "4") ?? 4
            var runs: [String] = []
            var current = ""
            for scalar in s.unicodeScalars {
                if scalar.value >= 32 && scalar.value < 127 {
                    current.unicodeScalars.append(scalar)
                } else {
                    if current.count >= minimum { runs.append(current) }
                    current = ""
                }
            }
            if current.count >= minimum { runs.append(current) }
            return runs.joined(separator: "\n")
        },
    ]

    // MARK: Network

    static let network: [ChefOperation] = [
        ChefOperation.text("defang", "Defang URLs / IPs", "Network") { s, _ in
            s.replacingOccurrences(of: "http://", with: "hxxp://", options: .caseInsensitive)
                .replacingOccurrences(of: "https://", with: "hxxps://", options: .caseInsensitive)
                .replacingOccurrences(of: ".", with: "[.]")
        },
        ChefOperation.text("fang", "Fang (undo defang)", "Network") { s, _ in
            s.replacingOccurrences(of: "hxxp://", with: "http://", options: .caseInsensitive)
                .replacingOccurrences(of: "hxxps://", with: "https://", options: .caseInsensitive)
                .replacingOccurrences(of: "[.]", with: ".")
                .replacingOccurrences(of: "(.)", with: ".")
        },
        ChefOperation.text("ip-to-int", "IPv4 to integer", "Network") { s, _ in
            let parts = s.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".").compactMap { UInt32($0) }
            guard parts.count == 4, parts.allSatisfy({ $0 < 256 }) else { throw ChefError.invalidInput("Not an IPv4 address.") }
            let value = (parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3]
            return "\(value)\nhex: 0x\(String(value, radix: 16))"
        },
        ChefOperation.text("int-to-ip", "Integer to IPv4", "Network") { s, _ in
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let value = trimmed.hasPrefix("0x") ? UInt32(trimmed.dropFirst(2), radix: 16) : UInt32(trimmed) else {
                throw ChefError.invalidInput("Not a 32-bit integer.")
            }
            return "\(value >> 24).\((value >> 16) & 255).\((value >> 8) & 255).\(value & 255)"
        },
        ChefOperation.text("cidr", "CIDR range", "Network") { s, _ in
            let text = s.trimmingCharacters(in: .whitespacesAndNewlines)
            let pieces = text.split(separator: "/")
            guard pieces.count == 2, let prefix = Int(pieces[1]), prefix >= 0, prefix <= 32 else { throw ChefError.invalidInput("Use the form 10.0.0.0/24.") }
            let parts = pieces[0].split(separator: ".").compactMap { UInt32($0) }
            guard parts.count == 4, parts.allSatisfy({ $0 < 256 }) else { throw ChefError.invalidInput("Not an IPv4 address.") }
            let ip = (parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3]
            let mask: UInt32 = prefix == 0 ? 0 : ~UInt32(0) << (32 - UInt32(prefix))
            let network = ip & mask
            let broadcast = network | ~mask
            func dotted(_ v: UInt32) -> String { "\(v >> 24).\((v >> 16) & 255).\((v >> 8) & 255).\(v & 255)" }
            let hosts = prefix >= 31 ? (prefix == 32 ? 1 : 2) : Int(broadcast - network) - 1
            return "Network:   \(dotted(network))/\(prefix)\nNetmask:   \(dotted(mask))\nBroadcast: \(dotted(broadcast))\nFirst:     \(dotted(prefix >= 31 ? network : network + 1))\nLast:      \(dotted(prefix >= 31 ? broadcast : broadcast - 1))\nHosts:     \(hosts)"
        },
        ChefOperation.text("parse-url", "Parse URL", "Network") { s, _ in
            guard let url = URL(string: s.trimmingCharacters(in: .whitespacesAndNewlines)), let scheme = url.scheme else {
                throw ChefError.invalidInput("Not a URL.")
            }
            var lines = ["Scheme:   \(scheme)", "Host:     \(url.host ?? "")"]
            if let port = url.port { lines.append("Port:     \(port)") }
            lines.append("Path:     \(url.path)")
            if let query = url.query {
                lines.append("Query:    \(query)")
                for item in URLComponents(string: s)?.queryItems ?? [] {
                    lines.append("  \(item.name) = \(item.value ?? "")")
                }
            }
            if let fragment = url.fragment { lines.append("Fragment: \(fragment)") }
            return lines.joined(separator: "\n")
        },
        ChefOperation.text("cisco7-decode", "Cisco type 7 decode", "Network") { s, _ in
            // Accepts bare strings and whole configuration lines ("username x password 7 0822455D0A16").
            let lines = s.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard !lines.isEmpty else { return "" }
            return try lines.map { line -> String in
                let token = line.split(whereSeparator: { $0.isWhitespace }).last.map(String.init) ?? line
                guard let decoded = CiscoType7.decode(token) else {
                    throw ChefError.invalidInput("“\(token)” is not a Cisco type 7 string (two-digit offset followed by hex pairs).")
                }
                return lines.count == 1 ? decoded : "\(token)  →  \(decoded)"
            }.joined(separator: "\n")
        },
        ChefOperation.text("cisco7-encode", "Cisco type 7 encode", "Network",
                           params: [ChefParam(id: "seed", label: "Offset (0–15)", kind: .number, defaultValue: "7")]) { s, v in
            CiscoType7.encode(s.trimmingCharacters(in: .newlines), seed: Int(v["seed"] ?? "7") ?? 7)
        },
        ChefOperation.text("juniper9-decode", "Juniper $9$ decode", "Network") { s, _ in
            // Accepts bare "$9$…" secrets and configuration lines such as encrypted-password "$9$…";
            let lines = s.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard !lines.isEmpty else { return "" }
            return try lines.map { line -> String in
                let token = line.split(whereSeparator: { $0.isWhitespace || "\";".contains($0) }).first { $0.hasPrefix("$9$") }.map(String.init) ?? line
                guard let decoded = JuniperSecret.decode(token) else {
                    throw ChefError.invalidInput("“\(token)” is not a Juniper $9$ secret.")
                }
                return lines.count == 1 ? decoded : "\(token)  →  \(decoded)"
            }.joined(separator: "\n")
        },
    ]

    // MARK: Dates

    // MARK: Units

    static let units: [ChefOperation] = [
        ChefOperation.text("convert-bytes", "Convert data size", "Units",
                           params: [ChefParam(id: "from", label: "Input unit", kind: .choice(["auto", "B", "KB", "MB", "GB", "TB", "KiB", "MiB", "GiB", "TiB"]), defaultValue: "auto")]) { s, v in
            let (value, unit) = try DataSize.parse(s, defaultUnit: v["from"] ?? "auto")
            let bytes = value * DataSize.factor(unit)
            var out = "\(DataSize.format(value)) \(unit) = \(DataSize.format(bytes)) bytes\n\nDecimal (1000):"
            for name in ["KB", "MB", "GB", "TB"] { out += "\n  \(DataSize.format(bytes / DataSize.factor(name))) \(name)" }
            out += "\n\nBinary (1024):"
            for name in ["KiB", "MiB", "GiB", "TiB"] { out += "\n  \(DataSize.format(bytes / DataSize.factor(name))) \(name)" }
            return out
        },
        ChefOperation.text("convert-duration", "Convert duration", "Units") { s, _ in
            let seconds = try TimeSpan.parseSeconds(s)
            var out = "\(DataSize.format(seconds)) seconds"
            out += "\n\(DataSize.format(seconds / 60)) minutes"
            out += "\n\(DataSize.format(seconds / 3600)) hours"
            out += "\n\(DataSize.format(seconds / 86400)) days"
            out += "\n\(DataSize.format(seconds / 604800)) weeks"
            let days = Int(seconds) / 86400, hours = Int(seconds) % 86400 / 3600, minutes = Int(seconds) % 3600 / 60, rest = Int(seconds) % 60
            out += "\n= \(days)d \(hours)h \(minutes)m \(rest)s"
            return out
        },
    ]

    static let dates: [ChefOperation] = [
        ChefOperation.text("from-unix", "From Unix timestamp", "Dates") { s, _ in
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard var value = Double(trimmed) else { throw ChefError.invalidInput("Not a number.") }
            var unit = "seconds"
            if value > 1e14 { value /= 1_000_000; unit = "microseconds" } else if value > 1e11 { value /= 1000; unit = "milliseconds" }
            let date = Date(timeIntervalSince1970: value)
            let local = DateFormatter()
            local.dateFormat = "yyyy-MM-dd HH:mm:ss zzz"
            return "UTC:   \(ISO8601DateFormatter().string(from: date))\nLocal: \(local.string(from: date))\n(interpreted as \(unit))"
        },
        ChefOperation.text("to-unix", "To Unix timestamp", "Dates") { s, _ in
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            let iso = ISO8601DateFormatter()
            var date = iso.date(from: trimmed)
            if date == nil {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd", "dd-MM-yyyy HH:mm", "dd-MM-yyyy"] {
                    formatter.dateFormat = format
                    if let parsed = formatter.date(from: trimmed) { date = parsed; break }
                }
            }
            guard let date else { throw ChefError.invalidInput("Use ISO 8601 (2026-10-10T13:00:00Z) or yyyy-MM-dd HH:mm:ss.") }
            return "\(Int(date.timeIntervalSince1970))\nmilliseconds: \(Int(date.timeIntervalSince1970 * 1000))"
        },
        ChefOperation.text("now", "Current time", "Dates") { _, _ in
            let now = Date()
            return "Unix: \(Int(now.timeIntervalSince1970))\nUTC:  \(ISO8601DateFormatter().string(from: now))"
        },
    ]
}

// MARK: - Helpers

extension Digest {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

extension String {
    func leftPadded(to length: Int, with pad: Character = "0") -> String {
        count >= length ? self : String(repeating: pad, count: length - count) + self
    }
}

enum Base64 {
    /// Accepts standard and URL-safe alphabets, missing padding and embedded whitespace.
    static func decodeLenient(_ text: String) -> Data? {
        var cleaned = text.filter { !$0.isWhitespace }
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while cleaned.count % 4 != 0 { cleaned += "=" }
        return Data(base64Encoded: cleaned)
    }

    static func looksLikeBase64(_ text: String) -> Bool {
        let cleaned = text.filter { !$0.isWhitespace }
        guard cleaned.count >= 8 else { return false }
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=-_")
        return cleaned.allSatisfy { allowed.contains($0) }
    }
}

extension Base64 {
    /// Base64url without padding (JWT).
    static func urlEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Bitcoin-style Base58 (no 0, O, I, l).
enum Base58 {
    private static let alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")

    static func encode(_ data: Data) -> String {
        var digits: [Int] = [0]
        for byte in data {
            var carry = Int(byte)
            for index in digits.indices {
                carry += digits[index] << 8
                digits[index] = carry % 58
                carry /= 58
            }
            while carry > 0 {
                digits.append(carry % 58)
                carry /= 58
            }
        }
        var out = ""
        for byte in data {
            if byte == 0 { out.append(alphabet[0]) } else { break }
        }
        for digit in digits.reversed().drop(while: { $0 == 0 }) { out.append(alphabet[digit]) }
        return out
    }

    static func decode(_ text: String) -> Data? {
        var bytes: [UInt8] = [0]
        for character in text {
            guard let value = alphabet.firstIndex(of: character) else { return nil }
            var carry = value
            for index in bytes.indices {
                carry += Int(bytes[index]) * 58
                bytes[index] = UInt8(carry & 0xFF)
                carry >>= 8
            }
            while carry > 0 {
                bytes.append(UInt8(carry & 0xFF))
                carry >>= 8
            }
        }
        var leading = 0
        for character in text {
            if character == alphabet[0] { leading += 1 } else { break }
        }
        let body = bytes.reversed().drop { $0 == 0 }
        return Data(repeating: 0, count: leading) + Data(body)
    }
}

/// "1.5 GB", "1536MiB", "2048" + unit → bytes and back.
enum DataSize {
    static func factor(_ unit: String) -> Double {
        switch unit.uppercased() {
        case "B": return 1
        case "KB": return 1e3
        case "MB": return 1e6
        case "GB": return 1e9
        case "TB": return 1e12
        case "PB": return 1e15
        case "KIB": return 1024
        case "MIB": return 1024 * 1024
        case "GIB": return 1024 * 1024 * 1024
        case "TIB": return 1024 * 1024 * 1024 * 1024
        case "PIB": return 1024 * 1024 * 1024 * 1024 * 1024
        default: return 1
        }
    }

    static func parse(_ text: String, defaultUnit: String) throws -> (Double, String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard let regex = try? NSRegularExpression(pattern: #"^([0-9]*\.?[0-9]+)\s*([A-Za-z]*)$"#),
              let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
              let numberRange = Range(match.range(at: 1), in: trimmed), let value = Double(trimmed[numberRange]) else {
            throw ChefError.invalidInput("Enter a number with an optional unit, e.g. 1.5 GB, 1536 MiB or 2048 (then choose the unit).")
        }
        var unit = Range(match.range(at: 2), in: trimmed).map { String(trimmed[$0]) } ?? ""
        if unit.isEmpty { unit = defaultUnit == "auto" ? "B" : defaultUnit }
        let known = ["B", "KB", "MB", "GB", "TB", "PB", "KIB", "MIB", "GIB", "TIB", "PIB"]
        guard let canonical = known.first(where: { $0 == unit.uppercased() }) else {
            throw ChefError.invalidInput("Unknown unit “\(unit)”. Use B, KB, MB, GB, TB or KiB, MiB, GiB, TiB.")
        }
        let display = canonical.hasSuffix("IB") ? String(canonical.prefix(1)) + "iB" : canonical
        return (value, display)
    }

    static func format(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 { return String(Int64(value)) }
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 4
        formatter.minimumFractionDigits = 0
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}

/// "90m", "1h 30m", "2d", "3600", "1:30:00" → seconds.
enum TimeSpan {
    static func parseSeconds(_ text: String) throws -> Double {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.contains(":") {
            let parts = trimmed.split(separator: ":").map { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard parts.allSatisfy({ $0 != nil }), !parts.isEmpty else { throw ChefError.invalidInput("Use h:mm:ss, mm:ss, or units like 1h 30m.") }
            return parts.compactMap { $0 }.reduce(0) { $0 * 60 + $1 }
        }
        guard let regex = try? NSRegularExpression(pattern: #"([0-9]*\.?[0-9]+)\s*([a-z]*)"#) else { return 0 }
        let matches = regex.matches(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed))
        guard !matches.isEmpty else { throw ChefError.invalidInput("Enter a duration: 3600, 90m, 1h 30m, 2d, or h:mm:ss.") }
        var total = 0.0
        for match in matches {
            guard let numberRange = Range(match.range(at: 1), in: trimmed), let value = Double(trimmed[numberRange]) else { continue }
            let unit = Range(match.range(at: 2), in: trimmed).map { String(trimmed[$0]) } ?? ""
            switch unit {
            case "", "s", "sec", "secs", "second", "seconds": total += value
            case "m", "min", "mins", "minute", "minutes": total += value * 60
            case "h", "hr", "hrs", "hour", "hours": total += value * 3600
            case "d", "day", "days": total += value * 86400
            case "w", "wk", "week", "weeks": total += value * 604800
            case "ms": total += value / 1000
            default: throw ChefError.invalidInput("Unknown unit “\(unit)”.")
            }
        }
        return total
    }
}

enum Base32 {
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    static func encode(_ data: Data) -> String {
        var out = ""
        var buffer = 0
        var bits = 0
        for byte in data {
            buffer = (buffer << 8) | Int(byte)
            bits += 8
            while bits >= 5 {
                out.append(alphabet[(buffer >> (bits - 5)) & 31])
                bits -= 5
            }
        }
        if bits > 0 { out.append(alphabet[(buffer << (5 - bits)) & 31]) }
        while out.count % 8 != 0 { out.append("=") }
        return out
    }

    static func decode(_ text: String) -> Data? {
        var out = Data()
        var buffer = 0
        var bits = 0
        for char in text.uppercased() where char != "=" && !char.isWhitespace {
            guard let value = alphabet.firstIndex(of: char) else { return nil }
            buffer = (buffer << 5) | value
            bits += 5
            if bits >= 8 {
                out.append(UInt8((buffer >> (bits - 8)) & 255))
                bits -= 8
            }
        }
        return out
    }
}

enum Hex {
    static func decode(_ text: String) -> Data? {
        var cleaned = text.replacingOccurrences(of: "0x", with: "").replacingOccurrences(of: "\\x", with: "")
        cleaned = cleaned.filter { $0.isHexDigit }
        guard !cleaned.isEmpty, cleaned.count % 2 == 0 else { return nil }
        var out = Data(capacity: cleaned.count / 2)
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let end = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index..<end], radix: 16) else { return nil }
            out.append(byte)
            index = end
        }
        return out
    }

    static func looksLikeHex(_ text: String) -> Bool {
        let cleaned = text.replacingOccurrences(of: "0x", with: "").filter { !$0.isWhitespace && $0 != ":" && $0 != "," }
        return cleaned.count >= 4 && cleaned.count % 2 == 0 && cleaned.allSatisfy { $0.isHexDigit }
    }
}

enum Caesar {
    static func shift(_ text: String, by amount: Int) -> String {
        let shift = ((amount % 26) + 26) % 26
        return String(text.unicodeScalars.map { scalar -> Character in
            let value = scalar.value
            if value >= 65 && value <= 90 { return Character(UnicodeScalar(65 + (value - 65 + UInt32(shift)) % 26)!) }
            if value >= 97 && value <= 122 { return Character(UnicodeScalar(97 + (value - 97 + UInt32(shift)) % 26)!) }
            return Character(scalar)
        })
    }
}

enum HTMLEntities {
    private static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}", "copy": "©", "reg": "®",
        "euro": "€", "pound": "£", "yen": "¥", "hellip": "…", "mdash": "—", "ndash": "–", "laquo": "«", "raquo": "»",
    ]

    static func decode(_ text: String) -> String {
        let regex = try! NSRegularExpression(pattern: #"&(#x[0-9a-fA-F]+|#\d+|[a-zA-Z]+);"#)
        var result = ""
        var last = text.startIndex
        for m in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(m.range, in: text), let inner = Range(m.range(at: 1), in: text) else { continue }
            result += text[last..<range.lowerBound]
            let entity = String(text[inner])
            var replacement: String? = nil
            if entity.hasPrefix("#x"), let value = UInt32(entity.dropFirst(2), radix: 16), let scalar = UnicodeScalar(value) {
                replacement = String(scalar)
            } else if entity.hasPrefix("#"), let value = UInt32(entity.dropFirst()), let scalar = UnicodeScalar(value) {
                replacement = String(scalar)
            } else {
                replacement = named[entity]
            }
            result += replacement ?? String(text[range])
            last = range.upperBound
        }
        result += text[last...]
        return result
    }
}

enum JSONFormat {
    static func pretty(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let out = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]) else {
            return nil
        }
        return String(decoding: out, as: UTF8.self).replacingOccurrences(of: "\\/", with: "/")
    }
}

enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}

enum Zlib {
    /// Raw DEFLATE wrapped in a zlib header/trailer (what most "zlib" data looks like: 78 9c …).
    static func deflate(_ data: Data) throws -> Data {
        let raw = try rawDeflate(data)
        var out = Data([0x78, 0x9C])
        out.append(raw)
        var adler = adler32(data).bigEndian
        out.append(Data(bytes: &adler, count: 4))
        return out
    }

    static func inflate(_ data: Data) throws -> Data {
        guard data.count > 6, data[data.startIndex] & 0x0F == 8 else { throw ChefError.invalidInput("No zlib header found (expected 78 xx).") }
        let body = data.subdata(in: (data.startIndex + 2)..<(data.endIndex - 4))
        return try rawInflate(body)
    }

    static func rawDeflate(_ data: Data) throws -> Data {
        do {
            return try (data as NSData).compressed(using: .zlib) as Data
        } catch {
            throw ChefError.invalidInput("Compression failed: \(error.localizedDescription)")
        }
    }

    static func rawInflate(_ data: Data) throws -> Data {
        do {
            return try (data as NSData).decompressed(using: .zlib) as Data
        } catch {
            throw ChefError.invalidInput("Not a valid DEFLATE stream.")
        }
    }

    static func adler32(_ data: Data) -> UInt32 {
        var a: UInt32 = 1
        var b: UInt32 = 0
        for byte in data {
            a = (a + UInt32(byte)) % 65521
            b = (b + a) % 65521
        }
        return (b << 16) | a
    }
}

enum Gzip {
    static func compress(_ data: Data) throws -> Data {
        var out = Data([0x1F, 0x8B, 0x08, 0x00, 0, 0, 0, 0, 0x00, 0x03])
        out.append(try Zlib.rawDeflate(data))
        var crc = CRC32.checksum(data).littleEndian
        out.append(Data(bytes: &crc, count: 4))
        var size = UInt32(truncatingIfNeeded: data.count).littleEndian
        out.append(Data(bytes: &size, count: 4))
        return out
    }

    static func decompress(_ data: Data) throws -> Data {
        let bytes = [UInt8](data)
        guard bytes.count > 18, bytes[0] == 0x1F, bytes[1] == 0x8B, bytes[2] == 8 else {
            throw ChefError.invalidInput("No gzip header found (expected 1f 8b 08).")
        }
        let flags = bytes[3]
        var offset = 10
        if flags & 0x04 != 0 { // FEXTRA
            guard offset + 2 <= bytes.count else { throw ChefError.invalidInput("Truncated gzip header.") }
            let extraLength = Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8)
            offset += 2 + extraLength
        }
        if flags & 0x08 != 0 { // FNAME
            while offset < bytes.count, bytes[offset] != 0 { offset += 1 }
            offset += 1
        }
        if flags & 0x10 != 0 { // FCOMMENT
            while offset < bytes.count, bytes[offset] != 0 { offset += 1 }
            offset += 1
        }
        if flags & 0x02 != 0 { offset += 2 } // FHCRC
        guard offset < bytes.count - 8 else { throw ChefError.invalidInput("Truncated gzip data.") }
        return try Zlib.rawInflate(Data(bytes[offset..<(bytes.count - 8)]))
    }

    static func looksLikeGzip(_ data: Data) -> Bool {
        data.count > 18 && data[data.startIndex] == 0x1F && data[data.startIndex + 1] == 0x8B
    }
}

enum Extract {
    static func matches(_ pattern: String, in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return "" }
        var seen: Set<String> = []
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { m -> String? in
            guard let range = Range(m.range, in: text) else { return nil }
            let value = String(text[range])
            return seen.insert(value).inserted ? value : nil
        }.joined(separator: "\n")
    }
}
