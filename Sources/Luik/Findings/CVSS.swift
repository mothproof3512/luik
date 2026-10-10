import Foundation

/// CVSS v3.1 base and temporal scores (specification section 7). Vectors from v3.0 are accepted
/// and scored with the v3.1 formulas (the only difference is the rounding function).
enum CVSS31 {
    struct Option: Identifiable {
        let value: String
        let label: String
        var id: String { value }
    }

    struct Metric: Identifiable {
        let key: String
        let name: String
        let options: [Option]
        var id: String { key }
    }

    static let base: [Metric] = [
        Metric(key: "AV", name: "Attack vector", options: [Option(value: "N", label: "Network"), Option(value: "A", label: "Adjacent"), Option(value: "L", label: "Local"), Option(value: "P", label: "Physical")]),
        Metric(key: "AC", name: "Attack complexity", options: [Option(value: "L", label: "Low"), Option(value: "H", label: "High")]),
        Metric(key: "PR", name: "Privileges required", options: [Option(value: "N", label: "None"), Option(value: "L", label: "Low"), Option(value: "H", label: "High")]),
        Metric(key: "UI", name: "User interaction", options: [Option(value: "N", label: "None"), Option(value: "R", label: "Required")]),
        Metric(key: "S", name: "Scope", options: [Option(value: "U", label: "Unchanged"), Option(value: "C", label: "Changed")]),
        Metric(key: "C", name: "Confidentiality", options: [Option(value: "N", label: "None"), Option(value: "L", label: "Low"), Option(value: "H", label: "High")]),
        Metric(key: "I", name: "Integrity", options: [Option(value: "N", label: "None"), Option(value: "L", label: "Low"), Option(value: "H", label: "High")]),
        Metric(key: "A", name: "Availability", options: [Option(value: "N", label: "None"), Option(value: "L", label: "Low"), Option(value: "H", label: "High")]),
    ]

    static let temporal: [Metric] = [
        Metric(key: "E", name: "Exploit code maturity", options: [Option(value: "X", label: "Not defined"), Option(value: "U", label: "Unproven"), Option(value: "P", label: "Proof of concept"), Option(value: "F", label: "Functional"), Option(value: "H", label: "High")]),
        Metric(key: "RL", name: "Remediation level", options: [Option(value: "X", label: "Not defined"), Option(value: "O", label: "Official fix"), Option(value: "T", label: "Temporary fix"), Option(value: "W", label: "Workaround"), Option(value: "U", label: "Unavailable")]),
        Metric(key: "RC", name: "Report confidence", options: [Option(value: "X", label: "Not defined"), Option(value: "U", label: "Unknown"), Option(value: "R", label: "Reasonable"), Option(value: "C", label: "Confirmed")]),
    ]

    static let defaultValues: [String: String] = [
        "AV": "N", "AC": "L", "PR": "N", "UI": "N", "S": "U", "C": "N", "I": "N", "A": "N",
        "E": "X", "RL": "X", "RC": "X",
    ]

    struct Result {
        let base: Double
        let temporal: Double?       // nil when no temporal metric is set
        let impact: Double
        let exploitability: Double
        var severity: Severity { Severity.from(score: temporal ?? base) }
        var effective: Double { temporal ?? base }
    }

    /// "CVSS:3.1/AV:N/AC:L/…" → metric values; nil unless the prefix and all eight base metrics are there.
    static func parse(_ vector: String) -> [String: String]? {
        let parts = vector.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "/").map(String.init)
        guard let first = parts.first, first.uppercased().hasPrefix("CVSS:3.") else { return nil }
        var values: [String: String] = [:]
        for part in parts.dropFirst() {
            let pair = part.split(separator: ":", maxSplits: 1).map(String.init)
            guard pair.count == 2 else { return nil }
            let key = pair[0].uppercased()
            let value = pair[1].uppercased()
            guard let metric = (base + temporal).first(where: { $0.key == key }),
                  metric.options.contains(where: { $0.value == value }) else { return nil }
            values[key] = value
        }
        guard base.allSatisfy({ values[$0.key] != nil }) else { return nil }
        return values
    }

    /// Builds the vector string; temporal metrics are included only when set.
    static func vector(from values: [String: String]) -> String {
        var out = "CVSS:3.1"
        for metric in base {
            out += "/\(metric.key):\(values[metric.key] ?? defaultValues[metric.key]!)"
        }
        for metric in temporal {
            if let value = values[metric.key], value != "X" {
                out += "/\(metric.key):\(value)"
            }
        }
        return out
    }

    static func score(vector: String) -> Result? {
        guard let values = parse(vector) else { return nil }
        return score(values: values)
    }

    static func score(values v: [String: String]) -> Result? {
        guard let av = weight(["N": 0.85, "A": 0.62, "L": 0.55, "P": 0.2], v["AV"]),
              let ac = weight(["L": 0.77, "H": 0.44], v["AC"]),
              let ui = weight(["N": 0.85, "R": 0.62], v["UI"]),
              let c = weight(["H": 0.56, "L": 0.22, "N": 0], v["C"]),
              let i = weight(["H": 0.56, "L": 0.22, "N": 0], v["I"]),
              let a = weight(["H": 0.56, "L": 0.22, "N": 0], v["A"]),
              let scope = v["S"], scope == "U" || scope == "C" else { return nil }
        let changed = scope == "C"
        guard let pr = weight(changed ? ["N": 0.85, "L": 0.68, "H": 0.5] : ["N": 0.85, "L": 0.62, "H": 0.27], v["PR"]) else { return nil }

        let iss = 1 - (1 - c) * (1 - i) * (1 - a)
        let impact = changed ? 7.52 * (iss - 0.029) - 3.25 * pow(iss - 0.02, 15) : 6.42 * iss
        let exploitability = 8.22 * av * ac * pr * ui
        let baseScore: Double
        if impact <= 0 {
            baseScore = 0
        } else if changed {
            baseScore = roundUp(min(1.08 * (impact + exploitability), 10))
        } else {
            baseScore = roundUp(min(impact + exploitability, 10))
        }

        let e = weight(["X": 1, "H": 1, "F": 0.97, "P": 0.94, "U": 0.91], v["E"] ?? "X") ?? 1
        let rl = weight(["X": 1, "U": 1, "W": 0.97, "T": 0.96, "O": 0.95], v["RL"] ?? "X") ?? 1
        let rc = weight(["X": 1, "C": 1, "R": 0.96, "U": 0.92], v["RC"] ?? "X") ?? 1
        let hasTemporal = [v["E"], v["RL"], v["RC"]].contains { $0 != nil && $0 != "X" }
        let temporalScore = hasTemporal ? roundUp(baseScore * e * rl * rc) : nil

        return Result(base: baseScore, temporal: temporalScore, impact: max(impact, 0), exploitability: exploitability)
    }

    private static func weight(_ table: [String: Double], _ value: String?) -> Double? {
        guard let value else { return nil }
        return table[value]
    }

    /// CVSS v3.1 Roundup: smallest number with one decimal that is ≥ the input (with the
    /// integer trick from the specification to avoid floating point surprises).
    static func roundUp(_ input: Double) -> Double {
        let integer = Int((input * 100_000).rounded())
        if integer % 10_000 == 0 {
            return Double(integer) / 100_000
        }
        return (Double(integer / 10_000) + 1) / 10
    }

    static func format(_ score: Double) -> String {
        String(format: "%.1f", score)
    }
}
