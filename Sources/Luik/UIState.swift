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
}
