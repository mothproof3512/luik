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
        }
    }
}

/// Shared UI state (which tab is open, whether settings are visible).
@Observable
final class UIState {
    static let shared = UIState()

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

    /// The tabs in the order of the top bar (drag a tab to change it); ⌘1–9 follow this order.
    var tabOrder: [Module] = UIState.loadTabOrder()

    static func loadTabOrder() -> [Module] {
        let stored = UserDefaults.standard.stringArray(forKey: SettingsKey.tabOrder) ?? []
        var order = stored.compactMap { Module(rawValue: $0) }
        for module in Module.allCases where !order.contains(module) {
            order.append(module)
        }
        return order
    }

    var isDefaultTabOrder: Bool { tabOrder == Module.allCases }

    /// Puts the tab at `from` where the tab at `to` is (the one at `to` shifts aside).
    func moveTab(from: Int, to: Int) {
        guard from != to, tabOrder.indices.contains(from), tabOrder.indices.contains(to) else { return }
        let module = tabOrder.remove(at: from)
        tabOrder.insert(module, at: to)
        saveTabOrder()
    }

    /// Context menu: one position to the left (-1) or right (+1).
    func moveTab(_ module: Module, by offset: Int) {
        guard let index = tabOrder.firstIndex(of: module) else { return }
        let target = index + offset
        guard tabOrder.indices.contains(target) else { return }
        tabOrder.swapAt(index, target)
        saveTabOrder()
    }

    func resetTabOrder() {
        tabOrder = Module.allCases
        saveTabOrder()
    }

    private func saveTabOrder() {
        UserDefaults.standard.set(tabOrder.map { $0.rawValue }, forKey: SettingsKey.tabOrder)
        AppDelegate.shared?.rebuildViewMenu()
    }
}
