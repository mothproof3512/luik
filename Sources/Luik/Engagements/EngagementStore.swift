import AppKit
import Foundation
import Observation
import SwiftUI

/// One engagement (client, project, CTF box…): targets, notes, findings, log and evidence are kept
/// apart per engagement; one-liners, the knowledge base, Exploit-DB and Chef recipes are shared.
struct Engagement: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var client = ""
    var reference = ""      // project code, ticket, quote number…
    var period = ""         // free text: "13–17 Oct 2026"
    var scope: [String] = []        // CIDRs, IPs, ranges, hostnames (one per entry)
    var exclusions: [String] = []   // same notation; wins over scope
    var notes = ""
    var createdAt = Date()

    var displayName: String {
        name.trimmingCharacters(in: .whitespaces).isEmpty ? "Untitled engagement" : name
    }

    /// Safe folder name for evidence: "Acme internal 2026" → "Acme-internal-2026".
    var slug: String {
        let cleaned = displayName.map { $0.isLetter || $0.isNumber || $0 == "." || $0 == "_" ? $0 : "-" }
        let collapsed = String(cleaned).replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return collapsed.isEmpty ? id.uuidString : collapsed
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, client, reference, period, scope, exclusions, notes, createdAt
    }

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        client = try c.decodeIfPresent(String.self, forKey: .client) ?? ""
        reference = try c.decodeIfPresent(String.self, forKey: .reference) ?? ""
        period = try c.decodeIfPresent(String.self, forKey: .period) ?? ""
        scope = try c.decodeIfPresent([String].self, forKey: .scope) ?? []
        exclusions = try c.decodeIfPresent([String].self, forKey: .exclusions) ?? []
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}

private struct EngagementIndex: Codable {
    var engagements: [Engagement] = []
    var currentID: UUID? = nil
}

/// Keeps the list of engagements (engagements.json) and tells the per-engagement stores where
/// their files live: Engagements/<id>/targets.json, notes.json, activity.json, findings.json.
@Observable
final class EngagementStore {
    static let shared = EngagementStore()

    private static let fileName = "engagements.json"
    static let perEngagementFiles = ["targets.json", "notes.json", "activity.json", "findings.json"]

    var engagements: [Engagement] = []
    var currentID: UUID
    /// The "Manage engagements" sheet.
    var showManager = false

    init() {
        let index = Storage.load(EngagementIndex.self, from: EngagementStore.fileName)
        var list = index?.engagements ?? []
        if list.isEmpty {
            list = [Engagement(name: "Default engagement")]
        }
        engagements = list
        if let stored = index?.currentID, list.contains(where: { $0.id == stored }) {
            currentID = stored
        } else {
            currentID = list[0].id
        }
        migrateLegacyFilesIfNeeded()
        if index == nil || index?.currentID != currentID {
            save()
        }
    }

    var current: Engagement {
        engagements.first { $0.id == currentID } ?? engagements[0]
    }

    // MARK: - Files

    static func folder(for engagement: Engagement) -> URL {
        Storage.directory.appendingPathComponent("Engagements", isDirectory: true)
            .appendingPathComponent(engagement.id.uuidString, isDirectory: true)
    }

    var currentFolder: URL {
        let folder = EngagementStore.folder(for: current)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder
    }

    /// The file for the current engagement: fileURL("targets.json").
    func fileURL(_ name: String) -> URL {
        currentFolder.appendingPathComponent(name)
    }

    /// Versions before 0.14 kept targets, notes and the log at the top level of the data folder;
    /// move them into the first engagement once.
    private func migrateLegacyFilesIfNeeded() {
        let fm = FileManager.default
        let folder = EngagementStore.folder(for: current)
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in EngagementStore.perEngagementFiles {
            let old = Storage.url(for: name)
            let new = folder.appendingPathComponent(name)
            if fm.fileExists(atPath: old.path), !fm.fileExists(atPath: new.path) {
                try? fm.moveItem(at: old, to: new)
            }
        }
    }

    // MARK: - Switching and editing

    func switchTo(_ id: UUID) {
        guard id != currentID, engagements.contains(where: { $0.id == id }) else { return }
        // Pending autosaves must land in the old engagement's files first.
        AppDelegate.shared?.flushAllStores()
        currentID = id
        save()
        TargetStore.shared.reload()
        NotesStore.shared.reload()
        FindingsStore.shared.reload()
        DiagramStore.shared.reload()
        PlanStore.shared.reload()
        CanaryStore.shared.reload()
        ActivityLog.shared.reload()
        CommandOutputStore.shared.reload()
        ActivityLog.shared.record(.action, "Switched to engagement “\(current.displayName)”", source: "Engagements")
    }

    @discardableResult
    func create(name: String, switchToIt: Bool = true) -> Engagement {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let engagement = Engagement(name: cleaned.isEmpty ? "New engagement" : cleaned)
        engagements.append(engagement)
        save()
        if switchToIt {
            switchTo(engagement.id)
        }
        return engagement
    }

    func update(_ engagement: Engagement) {
        guard let index = engagements.firstIndex(where: { $0.id == engagement.id }) else { return }
        var cleaned = engagement
        cleaned.scope = cleaned.scope.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        cleaned.exclusions = cleaned.exclusions.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard engagements[index] != cleaned else { return }
        engagements[index] = cleaned
        save()
    }

    /// Removes the engagement and moves its folder to the Trash. The last engagement cannot be deleted.
    func delete(_ id: UUID) {
        guard engagements.count > 1, let engagement = engagements.first(where: { $0.id == id }) else { return }
        if id == currentID, let other = engagements.first(where: { $0.id != id }) {
            switchTo(other.id)
        }
        engagements.removeAll { $0.id == id }
        save()
        let folder = EngagementStore.folder(for: engagement)
        if FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.trashItem(at: folder, resultingItemURL: nil)
        }
        ActivityLog.shared.record(.action, "Deleted engagement “\(engagement.displayName)” (its folder is in the Trash)", source: "Engagements")
    }

    func save() {
        Storage.save(EngagementIndex(engagements: engagements, currentID: currentID), to: EngagementStore.fileName)
    }

    /// Binding to one engagement for the editor; every change is saved.
    func binding(for id: UUID) -> Binding<Engagement> {
        Binding(
            get: { [weak self] in
                self?.engagements.first { $0.id == id } ?? Engagement(name: "")
            },
            set: { [weak self] newValue in
                self?.update(newValue)
            }
        )
    }

    // MARK: - Scope

    var hasScope: Bool { !current.scope.isEmpty }

    func scopeStatus(of address: String) -> ScopeStatus {
        ScopeMatcher.status(of: address, scope: current.scope, exclusions: current.exclusions)
    }
}

enum ScopeStatus {
    case inScope
    case excluded
    case outOfScope
    case noScopeDefined

    var label: String {
        switch self {
        case .inScope: return "In scope"
        case .excluded: return "Explicitly excluded"
        case .outOfScope: return "Not in scope"
        case .noScopeDefined: return "No scope defined for this engagement"
        }
    }

    var symbol: String {
        switch self {
        case .inScope: return "checkmark.shield"
        case .excluded: return "xmark.shield"
        case .outOfScope: return "exclamationmark.shield"
        case .noScopeDefined: return "shield"
        }
    }

    /// True when the address should not be touched.
    var isProblem: Bool { self == .excluded || self == .outOfScope }
}

/// Scope entries: 10.0.0.0/24, 10.0.0.5, 10.0.0.10-10.0.0.20, 10.0.0.10-20, example.com,
/// *.example.com, 2001:db8::/32. A bare domain covers its subdomains too.
enum ScopeMatcher {
    enum Rule {
        case ipv4(UInt32)
        case cidr(network: UInt32, mask: UInt32)
        case range(UInt32, UInt32)
        case host(String)        // lower-cased, without a leading "*."
        case ipv6Prefix(String)  // lower-cased text prefix of the address
    }

    static func parse(_ entry: String) -> Rule? {
        let text = entry.trimmingCharacters(in: .whitespaces).lowercased()
        guard !text.isEmpty, !text.hasPrefix("#") else { return nil }
        if text.contains(":") {
            // IPv6 (optionally with a prefix length): compare the textual prefix.
            let address = text.split(separator: "/").first.map(String.init) ?? text
            return .ipv6Prefix(address.hasSuffix("::") ? String(address.dropLast(1)) : address)
        }
        if let slash = text.firstIndex(of: "/") {
            guard let ip = ipv4(String(text[..<slash])), let bits = Int(text[text.index(after: slash)...]), bits >= 0, bits <= 32 else { return nil }
            let mask: UInt32 = bits == 0 ? 0 : ~UInt32(0) << UInt32(32 - bits)
            return .cidr(network: ip & mask, mask: mask)
        }
        if let dash = text.firstIndex(of: "-"), let low = ipv4(String(text[..<dash])) {
            let rest = String(text[text.index(after: dash)...])
            if let high = ipv4(rest) {
                return .range(min(low, high), max(low, high))
            }
            if let last = UInt32(rest), last < 256 {
                let high = (low & 0xFFFFFF00) | last
                return .range(min(low, high), max(low, high))
            }
            return nil
        }
        if let ip = ipv4(text) {
            return .ipv4(ip)
        }
        var host = text
        if host.hasPrefix("*.") { host = String(host.dropFirst(2)) }
        guard !host.isEmpty, host.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_" }) else { return nil }
        return .host(host)
    }

    static func ipv4(_ text: String) -> UInt32? {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var value: UInt32 = 0
        for part in parts {
            guard let octet = UInt32(part), octet < 256, !part.isEmpty, part.count <= 3 else { return nil }
            value = (value << 8) | octet
        }
        return value
    }

    static func dotted(_ value: UInt32) -> String {
        "\(value >> 24).\((value >> 16) & 255).\((value >> 8) & 255).\(value & 255)"
    }

    static func matches(_ rule: Rule, address: String) -> Bool {
        let text = address.trimmingCharacters(in: .whitespaces).lowercased()
        let ip = ipv4(text)
        switch rule {
        case .ipv4(let value):
            return ip == value
        case .cidr(let network, let mask):
            guard let ip else { return false }
            return ip & mask == network
        case .range(let low, let high):
            guard let ip else { return false }
            return ip >= low && ip <= high
        case .host(let pattern):
            guard ip == nil else { return false }
            return text == pattern || text.hasSuffix("." + pattern)
        case .ipv6Prefix(let prefix):
            return text.contains(":") && text.hasPrefix(prefix)
        }
    }

    static func status(of address: String, scope: [String], exclusions: [String]) -> ScopeStatus {
        let scopeRules = scope.compactMap(parse)
        guard !scopeRules.isEmpty else { return .noScopeDefined }
        if exclusions.compactMap(parse).contains(where: { matches($0, address: address) }) {
            return .excluded
        }
        return scopeRules.contains(where: { matches($0, address: address) }) ? .inScope : .outOfScope
    }

    /// A short description of an entry for the editor, or nil when it is not understood.
    static func describe(_ entry: String) -> String? {
        guard let rule = parse(entry) else { return nil }
        switch rule {
        case .ipv4(let v): return "host \(dotted(v))"
        case .cidr(let network, let mask):
            let size = mask == 0 ? UInt64(1) << 32 : UInt64(~mask) + 1
            return "network \(dotted(network)) — \(size) address\(size == 1 ? "" : "es")"
        case .range(let low, let high): return "range \(dotted(low)) – \(dotted(high)) — \(UInt64(high - low) + 1) addresses"
        case .host(let h): return "\(h) and its subdomains"
        case .ipv6Prefix(let p): return "IPv6 addresses starting with \(p)"
        }
    }
}
