import AppKit
import Foundation
import Observation

/// A product known to endoflife.date (api/v1/products).
struct EOLProduct: Codable, Identifiable, Hashable {
    var name: String
    var label: String
    var aliases: [String] = []
    var category: String = ""
    var tags: [String] = []

    var id: String { name }

    private enum CodingKeys: String, CodingKey { case name, label, aliases, category, tags }

    init(name: String, label: String, aliases: [String] = [], category: String = "", tags: [String] = []) {
        self.name = name
        self.label = label
        self.aliases = aliases
        self.category = category
        self.tags = tags
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? name
        aliases = try c.decodeIfPresent([String].self, forKey: .aliases) ?? []
        category = try c.decodeIfPresent(String.self, forKey: .category) ?? ""
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
    }
}

/// One release cycle of a product.
struct EOLRelease: Codable, Identifiable, Hashable {
    struct Latest: Codable, Hashable {
        var name: String
        var date: String?
        var link: String?
    }

    var name: String
    var label: String
    var codename: String?
    var releaseDate: String?
    var isLts: Bool
    var isEoas: Bool?
    var eoasFrom: String?
    var isEol: Bool
    var eolFrom: String?
    var isMaintained: Bool
    var latest: Latest?

    var id: String { name }

    private enum CodingKeys: String, CodingKey { case name, label, codename, releaseDate, isLts, isEoas, eoasFrom, isEol, eolFrom, isMaintained, latest }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? name
        codename = try? c.decodeIfPresent(String.self, forKey: .codename)
        releaseDate = try? c.decodeIfPresent(String.self, forKey: .releaseDate)
        isLts = (try? c.decodeIfPresent(Bool.self, forKey: .isLts)) ?? false
        isEoas = try? c.decodeIfPresent(Bool.self, forKey: .isEoas)
        eoasFrom = try? c.decodeIfPresent(String.self, forKey: .eoasFrom)
        isEol = (try? c.decodeIfPresent(Bool.self, forKey: .isEol)) ?? false
        eolFrom = try? c.decodeIfPresent(String.self, forKey: .eolFrom)
        isMaintained = (try? c.decodeIfPresent(Bool.self, forKey: .isMaintained)) ?? !isEol
        latest = try? c.decodeIfPresent(Latest.self, forKey: .latest)
    }

    /// EOL date as a Date, when it is a date.
    var eolDate: Date? { eolFrom.flatMap { VersionCheck.date($0) } }

    enum State {
        case eol, unmaintained, securityOnly, maintained

        var label: String {
            switch self {
            case .eol: return "End of life"
            case .unmaintained: return "Not maintained"
            case .securityOnly: return "Security fixes only"
            case .maintained: return "Maintained"
            }
        }
    }

    var state: State {
        if isEol { return .eol }
        if !isMaintained { return .unmaintained }
        if isEoas == true { return .securityOnly }
        return .maintained
    }
}

/// The product page: cycles plus links and identifiers.
struct EOLProductDetail: Codable, Hashable {
    struct Links: Codable, Hashable {
        var html: String?
        var releasePolicy: String?
    }

    struct Identifier: Codable, Hashable {
        var type: String
        var id: String
    }

    var name: String
    var label: String
    var category: String?
    var versionCommand: String?
    var links: Links?
    var identifiers: [Identifier] = []
    var releases: [EOLRelease] = []

    private enum CodingKeys: String, CodingKey { case name, label, category, versionCommand, links, identifiers, releases }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? name
        category = try? c.decodeIfPresent(String.self, forKey: .category)
        versionCommand = try? c.decodeIfPresent(String.self, forKey: .versionCommand)
        links = try? c.decodeIfPresent(Links.self, forKey: .links)
        identifiers = (try? c.decodeIfPresent([Identifier].self, forKey: .identifiers)) ?? []
        releases = (try? c.decodeIfPresent([EOLRelease].self, forKey: .releases)) ?? []
    }

    /// owner/repo from a GitHub package URL among the identifiers, when there is one.
    var githubRepository: String? {
        for identifier in identifiers {
            let id = identifier.id
            if let range = id.range(of: "pkg:github/") {
                let rest = id[range.upperBound...].split(separator: "@").first.map(String.init) ?? ""
                let parts = rest.split(separator: "/")
                if parts.count >= 2 { return "\(parts[0])/\(parts[1])" }
            }
        }
        return nil
    }

    /// The newest release overall (first cycle's latest).
    var newest: EOLRelease? { releases.first }
}

/// A GitHub release, for the changelog.
struct GitHubRelease: Codable, Identifiable, Hashable {
    var tagName: String
    var name: String?
    var publishedAt: String?
    var htmlUrl: String?
    var body: String?
    var prerelease: Bool?

    var id: String { tagName }

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name", name, publishedAt = "published_at", htmlUrl = "html_url", body, prerelease
    }
}

/// What a given version means against the product's cycles.
struct VersionVerdict {
    enum Severity { case fine, patchBehind, securityOnly, unmaintained, eol, unknown }

    var cycle: EOLRelease?
    var severity: Severity
    var summary: String
    var details: [String]

    var findingSeverity: Severity { severity }
}

/// Version and end-of-life check: endoflife.date for cycles, support and EOL dates, GitHub for
/// the release notes. Nothing is bundled; the product list is cached for a day.
@Observable
final class VersionCheck {
    static let shared = VersionCheck()

    private static let productsFile = "eol-products.json"
    private static let cacheAge: TimeInterval = 24 * 3600

    var products: [EOLProduct] = []
    var productsFetchedAt: Date?
    var isLoadingProducts = false
    var query: String = ""
    var version: String = ""
    var selectedProduct: EOLProduct?
    var detail: EOLProductDetail?
    var isLoadingDetail = false
    var repository: String = ""
    var releases: [GitHubRelease] = []
    var isLoadingReleases = false
    var error: String?

    private struct ProductCache: Codable {
        var fetchedAt: Date
        var products: [EOLProduct]
    }

    init() {
        if let cache = Storage.load(ProductCache.self, from: VersionCheck.productsFile) {
            products = cache.products
            productsFetchedAt = cache.fetchedAt
        }
    }

    // MARK: - Product list

    func loadProductsIfNeeded(force: Bool = false) {
        if !force, let at = productsFetchedAt, Date().timeIntervalSince(at) < VersionCheck.cacheAge, !products.isEmpty { return }
        guard !isLoadingProducts else { return }
        isLoadingProducts = true
        Task { @MainActor in
            do {
                let data = try await VersionCheck.fetch(URL(string: "https://endoflife.date/api/v1/products/")!)
                struct Envelope: Decodable { var result: [EOLProduct] }
                let decoded = try JSONDecoder().decode(Envelope.self, from: data)
                self.products = decoded.result.sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
                self.productsFetchedAt = Date()
                Storage.save(ProductCache(fetchedAt: Date(), products: self.products), to: VersionCheck.productsFile)
                self.error = nil
            } catch {
                self.error = "Could not load the product list from endoflife.date: \(error.localizedDescription)"
            }
            self.isLoadingProducts = false
        }
    }

    /// Products matching the query: exact name/alias first, then label/name prefix, then contains.
    var matches: [EOLProduct] {
        let needle = VersionCheck.normalize(query)
        guard !needle.isEmpty else { return [] }
        let words = needle.split(separator: " ").map(String.init)
        func score(_ product: EOLProduct) -> Int? {
            let name = VersionCheck.normalize(product.name)
            let label = VersionCheck.normalize(product.label)
            let aliases = product.aliases.map { VersionCheck.normalize($0) }
            if name == needle || label == needle || aliases.contains(needle) { return 0 }
            if name.hasPrefix(needle) || label.hasPrefix(needle) || aliases.contains(where: { $0.hasPrefix(needle) }) { return 1 }
            let haystack = ([name, label] + aliases).joined(separator: " ")
            if words.allSatisfy({ haystack.contains($0) }) { return 2 }
            // "apache httpd" → apache-http-server: every word as a fragment of the name without separators.
            let compact = haystack.replacingOccurrences(of: " ", with: "")
            if words.allSatisfy({ compact.contains($0) }) { return 3 }
            return nil
        }
        var scored: [(score: Int, product: EOLProduct)] = []
        for product in products {
            if let value = score(product) {
                scored.append((score: value, product: product))
            }
        }
        scored.sort { a, b in
            if a.score != b.score { return a.score < b.score }
            return a.product.label.localizedCaseInsensitiveCompare(b.product.label) == .orderedAscending
        }
        return scored.prefix(40).map { $0.product }
    }

    static func normalize(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    // MARK: - Product detail

    func select(_ product: EOLProduct) {
        selectedProduct = product
        detail = nil
        releases = []
        repository = ""
        isLoadingDetail = true
        error = nil
        let name = product.name
        Task { @MainActor in
            do {
                let data = try await VersionCheck.fetch(URL(string: "https://endoflife.date/api/v1/products/\(name)")!)
                struct Envelope: Decodable { var result: EOLProductDetail }
                let decoded = try JSONDecoder().decode(Envelope.self, from: data)
                guard self.selectedProduct?.name == name else { return }
                self.detail = decoded.result
                if let repo = decoded.result.githubRepository {
                    self.repository = repo
                    self.loadReleases()
                }
            } catch {
                self.error = "Could not load \(product.label): \(error.localizedDescription)"
            }
            self.isLoadingDetail = false
        }
    }

    /// From Targets: product words and version from the nmap service line.
    func prefill(product: String, version: String?) {
        query = product
        self.version = version ?? ""
        if products.isEmpty {
            loadProductsIfNeeded()
        }
        if let first = matches.first {
            select(first)
        } else {
            selectedProduct = nil
            detail = nil
        }
    }

    // MARK: - GitHub releases

    func loadReleases() {
        let repo = repository.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "https://github.com/", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard repo.split(separator: "/").count == 2 else {
            releases = []
            return
        }
        isLoadingReleases = true
        Task { @MainActor in
            do {
                var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases?per_page=25")!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                request.setValue("Luik/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
                if let token = KeychainItem.githubToken.read(), !token.isEmpty {
                    request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
                }
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    throw NSError(domain: "Luik", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: http.statusCode == 404 ? "No releases at github.com/\(repo)." : "HTTP \(http.statusCode) from GitHub (rate limit? add a token in the library's download sheet)."])
                }
                self.releases = try JSONDecoder().decode([GitHubRelease].self, from: data).filter { $0.prerelease != true }
            } catch {
                self.releases = []
                self.error = error.localizedDescription
            }
            self.isLoadingReleases = false
        }
    }

    // MARK: - Verdict

    /// The entered version against the cycles.
    func verdict(for versionText: String, in detail: EOLProductDetail) -> VersionVerdict {
        let version = versionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !version.isEmpty else {
            if let newest = detail.newest {
                return VersionVerdict(cycle: nil, severity: .unknown, summary: "Newest: \(newest.latest?.name ?? newest.label)\(newest.latest?.date.map { " (\($0))" } ?? "")", details: [])
            }
            return VersionVerdict(cycle: nil, severity: .unknown, summary: "", details: [])
        }
        let components = VersionCheck.components(of: version)
        // The cycle whose name matches the most leading components ("2.4" for "2.4.49").
        var best: (release: EOLRelease, length: Int)? = nil
        for release in detail.releases {
            let cycleComponents = VersionCheck.components(of: release.name)
            guard !cycleComponents.isEmpty, cycleComponents.count <= components.count,
                  Array(components.prefix(cycleComponents.count)) == cycleComponents else { continue }
            if best == nil || cycleComponents.count > best!.length {
                best = (release, cycleComponents.count)
            }
        }
        guard let cycle = best?.release else {
            return VersionVerdict(cycle: nil, severity: .unknown,
                                  summary: "Version \(version) does not match a known cycle of \(detail.label); the newest is \(detail.newest?.latest?.name ?? detail.newest?.label ?? "?").",
                                  details: [])
        }
        var details: [String] = []
        var severity: VersionVerdict.Severity = .fine
        if let date = cycle.releaseDate { details.append("Cycle \(cycle.label) released \(date)") }
        switch cycle.state {
        case .eol:
            severity = .eol
            details.append("End of life\(cycle.eolFrom.map { " since \($0)" } ?? "") — no more fixes, including security fixes")
        case .unmaintained:
            severity = .unmaintained
            details.append("Not maintained any more")
        case .securityOnly:
            severity = .securityOnly
            details.append("Security fixes only\(cycle.eoasFrom.map { " since \($0)" } ?? "")\(cycle.eolFrom.map { "; end of life on \($0)" } ?? "")")
        case .maintained:
            if let eol = cycle.eolFrom { details.append("Supported until \(eol)") }
            if let eoas = cycle.eoasFrom { details.append("Active support until \(eoas)") }
        }
        if let latest = cycle.latest?.name, VersionCheck.compare(version, latest) == .orderedAscending {
            if severity == .fine { severity = .patchBehind }
            details.append("Behind on patches: \(latest) is the latest in this cycle\(cycle.latest?.date.map { " (\($0))" } ?? "")")
        } else if let latest = cycle.latest?.name {
            details.append("Up to date within the cycle (latest \(latest))")
        }
        if let newest = detail.newest, newest.name != cycle.name, let newestName = newest.latest?.name ?? Optional(newest.label) {
            details.append("Newest cycle: \(newest.label) (\(newestName))")
        }
        let summary: String
        switch severity {
        case .eol: summary = "\(detail.label) \(version) is end of life."
        case .unmaintained: summary = "\(detail.label) \(version) is no longer maintained."
        case .securityOnly: summary = "\(detail.label) \(version) only receives security fixes."
        case .patchBehind: summary = "\(detail.label) \(version) is supported but behind on patches."
        case .fine: summary = "\(detail.label) \(version) is supported and current."
        case .unknown: summary = ""
        }
        return VersionVerdict(cycle: cycle, severity: severity, summary: summary, details: details)
    }

    /// "2.4.49-ubuntu" → [2, 4, 49]
    static func components(of version: String) -> [Int] {
        var result: [Int] = []
        var current = ""
        for character in version {
            if character.isNumber {
                current.append(character)
            } else {
                if !current.isEmpty { result.append(Int(current) ?? 0); current = "" }
                if character != "." { break }
            }
        }
        if !current.isEmpty { result.append(Int(current) ?? 0) }
        return result
    }

    static func compare(_ a: String, _ b: String) -> ComparisonResult {
        let x = components(of: a), y = components(of: b)
        for index in 0..<max(x.count, y.count) {
            let l = index < x.count ? x[index] : 0
            let r = index < y.count ? y[index] : 0
            if l != r { return l < r ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    static func date(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: text)
    }

    // MARK: - Networking

    private static func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("Luik/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NSError(domain: "Luik", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode) from \(url.host ?? "server")"])
        }
        return data
    }
}
