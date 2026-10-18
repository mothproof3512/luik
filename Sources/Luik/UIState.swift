import Foundation
import Observation

/// The modules of Luik, in tab order.
enum Module: String, CaseIterable, Identifiable {
    case terminal
    case notes
    case snippets
    case targets
    case findings
    case knowledgeBase
    case exploits
    case chef
    case activity
    case diagram
    case plan
    case tools
    case versionCheck
    case mailSecurity
    case reachability
    case playbooks
    case tlsInspector
    case httpHeaders
    case dnsLookup
    case shodan

    var id: String { rawValue }

    var title: String {
        switch self {
        case .terminal: return "Terminal"
        case .notes: return "Notes"
        case .snippets: return "One-liners"
        case .targets: return "Targets"
        case .findings: return "Findings"
        case .knowledgeBase: return "Knowledge base"
        case .exploits: return "Searchsploit"
        case .chef: return "Chef"
        case .activity: return "Log"
        case .diagram: return "Diagram"
        case .plan: return "Plan"
        case .tools: return "Tools"
        case .versionCheck: return "Version check"
        case .mailSecurity: return "Mail security"
        case .reachability: return "Canary"
        case .playbooks: return "Playbooks"
        case .tlsInspector: return "Certificates"
        case .httpHeaders: return "HTTP headers"
        case .dnsLookup: return "DNS & RDAP"
        case .shodan: return "Shodan"
        }
    }

    var icon: String {
        switch self {
        case .terminal: return "terminal"
        case .notes: return "note.text"
        case .snippets: return "doc.on.clipboard"
        case .targets: return "network"
        case .findings: return "exclamationmark.triangle"
        case .knowledgeBase: return "books.vertical"
        case .exploits: return "ladybug"
        case .chef: return "wand.and.stars"
        case .activity: return "clock.arrow.circlepath"
        case .diagram: return "point.3.connected.trianglepath.dotted"
        case .plan: return "list.clipboard"
        case .tools: return "wrench.and.screwdriver"
        case .versionCheck: return "clock.badge.exclamationmark"
        case .mailSecurity: return "envelope.badge.shield.half.filled"
        case .reachability: return "dot.radiowaves.left.and.right"
        case .playbooks: return "shippingbox"
        case .tlsInspector: return "checkmark.seal"
        case .httpHeaders: return "list.bullet.rectangle"
        case .dnsLookup: return "globe"
        case .shodan: return "binoculars"
        }
    }
}

extension Module {
    /// One line for the Tools sidebar.
    var summary: String {
        switch self {
        case .terminal: return "Shell tabs with command logging and saved connections."
        case .notes: return "Markdown notes per engagement, plus the library of cheat sheets and documentation."
        case .snippets: return "One-liners with $RHOST/$LHOST placeholders, multi-step sequences, reverse shell generator."
        case .targets: return "Hosts, ports and work items from scans, with checklists and suggestions."
        case .findings: return "Findings with CVSS, evidence and report export."
        case .knowledgeBase: return "Your findings sheet, searchable across every column; downloadable attack-vectors knowledge base."
        case .exploits: return "Exploit-DB offline: search by product and version, view, copy, mirror."
        case .chef: return "Encodings, hashes, JWT, data formats, units — CyberChef-style recipes."
        case .activity: return "Timestamped log of commands, imports, findings and notes."
        case .diagram: return "Network architecture drawings; import/export draw.io, Mermaid, PNG, SVG."
        case .plan: return "The engagement's test plan from a template: phases, items, fields."
        case .tools: return "The tools that are not in the top bar."
        case .versionCheck: return "Is this version current, supported or end of life? endoflife.date cycles and dates, GitHub release notes."
        case .mailSecurity: return "Can this domain be spoofed? MX, SPF (with lookup count), DMARC, DKIM keys, MTA-STS, TLS-RPT — judged and explained."
        case .reachability: return "Am I blocked? Probe in-scope hosts every N minutes; red badge and a Log entry when one stops answering."
        case .playbooks: return "Standard bundles per kind of engagement (plan, checklists, one-liners, diagram, reading) and your own playbook files."
        case .tlsInspector: return "Certificate chain as OSINT: names, organisation, issuer, validity, fingerprints, OCSP/CRL, validation level, CT timestamps — and the names CT logs know for the domain."
        case .httpHeaders: return "Security headers, cookie flags, redirects and CORS of a URL, judged — and the version disclosure for the Version check."
        case .dnsLookup: return "Records, reverse lookup, zone-transfer attempt and who owns the domain or address range (RDAP, ASN)."
        case .shodan: return "What Shodan has seen on a host (ports, banners, certificates, CVEs by banner), the subdomains of a domain, and searches — with your API key; results merge into Targets."
        }
    }

    /// Where a module lives when nothing was changed: the top bar, or the Tools tab's sidebar.
    static let defaultTabs: [Module] = [.terminal, .notes, .snippets, .targets, .findings, .plan, .activity, .tools]
    static let defaultTools: [Module] = [.knowledgeBase, .exploits, .chef, .diagram, .versionCheck, .mailSecurity, .tlsInspector, .httpHeaders, .dnsLookup, .shodan, .reachability, .playbooks]
}

/// Shared UI state (which tab is open, whether settings are visible).
@Observable
final class UIState {
    static let shared = UIState()

    init() {
        loadLayout()
    }

    var module: Module = .terminal
    var showSettings = false
    /// Error message when the chosen hotkey could not be registered (e.g. already in use).
    var hotKeyError: String? = nil
    /// The ⌘K search palette.
    var showPalette = false
    /// A newer release on GitHub, if the update check found one: (version, URL).
    var updateAvailable: (version: String, url: String)? = nil
    /// The keyboard-shortcuts sheet (⌘/).
    var showShortcuts = false
    /// The "Download a knowledge base" sheet (Knowledge base tab, Tools menu, ⌘K).
    var showKnowledgeBaseDownload = false
    /// The "Download documentation" sheet of the library (Notes tab, Tools menu, ⌘K).
    var showLibrarySources = false
    /// The reverse shell generator (One-liners tab, Tools menu, ⌘K).
    var showReverseShell = false
    /// A one-liner handed to the One-liners tab to open in its editor (from the Log, …).
    var pendingSnippet: Snippet?
    /// Opening effect of the colour scheme (ThemeIntroView): shown while true, token restarts it.
    var showIntro = false
    var introToken = 0
    /// Close-out export sheet.
    var showCloseOut = false
    /// First-start welcome sheet (Help › Welcome to Luik…).
    var showWelcome = false
    /// Playbook export / import sheet.
    var showPlaybook: PlaybookView.Mode?
    /// Short confirmation shown at the bottom of the panel for a moment ("Pinned to finding …").
    var flashMessage: String?
    @ObservationIgnored private var flashToken = 0

    func flash(_ message: String, seconds: Double = 2.2) {
        flashToken += 1
        let token = flashToken
        flashMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, self.flashToken == token else { return }
            self.flashMessage = nil
        }
    }
    /// The tabs of the top bar, in order (drag a tab to change it); ⌘1–9 follow this order.
    var tabOrder: [Module] = []
    /// The modules in the Tools tab's sidebar, in order.
    var toolOrder: [Module] = []
    /// The tool shown when the Tools tab is opened.
    var lastTool: Module? = nil

    /// Which tab the current module belongs to: itself, or Tools when it lives in the sidebar.
    var currentTab: Module {
        tabOrder.contains(module) ? module : .tools
    }

    var isDefaultLayout: Bool { tabOrder == Module.defaultTabs && toolOrder == Module.defaultTools }

    /// Opens a module wherever it lives (a tab, or a tool in the Tools tab).
    func open(_ target: Module) {
        if target == .tools {
            module = lastTool.flatMap { toolOrder.contains($0) ? $0 : nil } ?? toolOrder.first ?? .tools
        } else {
            module = target
        }
        if toolOrder.contains(module) { lastTool = module }
    }

    func loadLayout() {
        let defaults = UserDefaults.standard
        var tabs = (defaults.stringArray(forKey: SettingsKey.tabOrder) ?? []).compactMap { Module(rawValue: $0) }
        var tools = (defaults.stringArray(forKey: SettingsKey.toolOrder) ?? []).compactMap { Module(rawValue: $0) }
        // 0.27: Searchsploit, Knowledge base, Chef and Diagram moved into Tools once; later changes are the user's.
        if !defaults.bool(forKey: SettingsKey.toolsLayoutMigrated) {
            tabs.removeAll { Module.defaultTools.contains($0) }
            tools = []
            defaults.set(true, forKey: SettingsKey.toolsLayoutMigrated)
        }
        tabs.removeAll { tools.contains($0) }
        if !tabs.contains(.tools) { tabs.append(.tools) }
        tools.removeAll { $0 == .tools }
        for module in Module.allCases where !tabs.contains(module) && !tools.contains(module) {
            if Module.defaultTools.contains(module) { tools.append(module) } else { tabs.append(module) }
        }
        tabOrder = tabs
        toolOrder = tools
    }

    /// Puts the tab at `from` where the tab at `to` is (the one at `to` shifts aside).
    func moveTab(from: Int, to: Int) {
        guard from != to, tabOrder.indices.contains(from), tabOrder.indices.contains(to) else { return }
        let module = tabOrder.remove(at: from)
        tabOrder.insert(module, at: to)
        saveLayout()
    }

    /// Context menu: one position to the left (-1) or right (+1).
    func moveTab(_ module: Module, by offset: Int) {
        guard let index = tabOrder.firstIndex(of: module) else { return }
        let target = index + offset
        guard tabOrder.indices.contains(target) else { return }
        tabOrder.swapAt(index, target)
        saveLayout()
    }

    func moveTool(from source: IndexSet, to destination: Int) {
        SnippetStore.reorder(&toolOrder, from: source, to: destination)
        saveLayout()
    }

    func moveTool(_ module: Module, by offset: Int) {
        guard let index = toolOrder.firstIndex(of: module) else { return }
        let target = index + offset
        guard toolOrder.indices.contains(target) else { return }
        toolOrder.swapAt(index, target)
        saveLayout()
    }

    /// A top-bar tab becomes a tool in the Tools tab (the Tools tab itself cannot move).
    func moveToTools(_ target: Module) {
        guard target != .tools, tabOrder.contains(target) else { return }
        tabOrder.removeAll { $0 == target }
        toolOrder.append(target)
        if module == target { lastTool = target }
        saveLayout()
    }

    /// A tool gets its own tab in the top bar (before the Tools tab).
    func moveToTabs(_ target: Module) {
        guard toolOrder.contains(target) else { return }
        toolOrder.removeAll { $0 == target }
        if let toolsIndex = tabOrder.firstIndex(of: .tools) {
            tabOrder.insert(target, at: toolsIndex)
        } else {
            tabOrder.append(target)
        }
        if lastTool == target { lastTool = toolOrder.first }
        saveLayout()
    }

    func resetLayout() {
        tabOrder = Module.defaultTabs
        toolOrder = Module.defaultTools
        saveLayout()
    }

    private func saveLayout() {
        UserDefaults.standard.set(tabOrder.map { $0.rawValue }, forKey: SettingsKey.tabOrder)
        UserDefaults.standard.set(toolOrder.map { $0.rawValue }, forKey: SettingsKey.toolOrder)
        AppDelegate.shared?.rebuildViewMenu()
    }
}
