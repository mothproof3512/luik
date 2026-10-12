import AppKit
import SwiftUI

/// Every keyboard shortcut and mouse trick in Luik, in one sheet (Help › Keyboard Shortcuts, ⌘/).
struct ShortcutsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.luikTheme) private var theme
    @AppStorage(SettingsKey.hotKey) private var hotKey = "cmd+escape"

    private struct Shortcut: Identifiable {
        let keys: String
        let action: String
        var id: String { keys + action }
    }

    private struct ShortcutGroup: Identifiable {
        let title: String
        let shortcuts: [Shortcut]
        var id: String { title }
    }

    private var groups: [ShortcutGroup] {
        let hotKeyLabel = HotKeyCombo(string: hotKey)?.displayString ?? "none set"
        let tabs = Module.allCases.enumerated().map { index, module in Shortcut(keys: "⌘\(index + 1)", action: module.title) }
        return [
            ShortcutGroup(title: "Panel", shortcuts: [
                Shortcut(keys: hotKeyLabel, action: "Show / hide Luik from any app (Settings › General to change; paused in the apps you list there)"),
                Shortcut(keys: "drag bottom edge", action: "Change the panel height (becomes Settings › Appearance › Height); double-click the edge to go back to the default height"),
                Shortcut(keys: "esc", action: "Close the ⌘K search or a popover"),
                Shortcut(keys: "⌘,", action: "Settings"),
                Shortcut(keys: "⌘/", action: "This list"),
                Shortcut(keys: "⌘H", action: "Hide Luik (macOS hide)"),
                Shortcut(keys: "⌘Q", action: "Quit Luik — pending notes, targets and findings are saved first"),
            ]),
            ShortcutGroup(title: "Tabs", shortcuts: tabs),
            ShortcutGroup(title: "Search and tools", shortcuts: [
                Shortcut(keys: "⌘K", action: "Search everything: notes, one-liners, targets, findings, knowledge base, Exploit-DB, Chef operations, log, engagements and actions"),
                Shortcut(keys: "↑ ↓  ↩", action: "In ⌘K: choose a result, open it in its tab"),
                Shortcut(keys: "⌘N", action: "New finding"),
                Shortcut(keys: "⌘⇧E", action: "Capture an evidence screenshot (Luik hides first; drag an area, or press space and click a window)"),
                Shortcut(keys: "⌘⌥⇧E", action: "Capture evidence with Luik still visible"),
            ]),
            ShortcutGroup(title: "Terminal", shortcuts: [
                Shortcut(keys: "⌘T", action: "New terminal tab"),
                Shortcut(keys: "⌘W", action: "Close the current terminal tab"),
                Shortcut(keys: "⌘⇧]  ⌘⇧[", action: "Next / previous terminal tab"),
                Shortcut(keys: "⌘F", action: "Find in the scrollback (⌘G next, ⌘⇧G previous, ⌘E use the selection)"),
                Shortcut(keys: "⌘C  ⌘V", action: "Copy the selection / paste (bracketed paste when the shell supports it)"),
                Shortcut(keys: "⌥ + key", action: "Option works as Meta (⌥← ⌥→ jump words, ⌥. last argument, …)"),
                Shortcut(keys: "Connect ▾", action: "Open a saved ssh / jump-host connection in a new tab (One-liners' $RHOST, $LHOST, $LPORT are filled in)"),
            ]),
            ShortcutGroup(title: "One-liners", shortcuts: [
                Shortcut(keys: "drag a row", action: "Reorder one-liners within a category (right-click: Move up / down / to top / to bottom, Duplicate); the arrows beside a heading move the category"),
                Shortcut(keys: "Copy all", action: "A multi-step one-liner copies every step, one per line; each step also has its own copy and paste buttons"),
                Shortcut(keys: "Reverse shell", action: "Generator: a template from the cheat sheet in your library (InternalAllTheThings) or your own “Reverse shells” one-liners, with $LHOST/$LPORT, shell, encoding, the listener and the TTY upgrade; Save as one-liner keeps the three steps"),
            ]),
            ShortcutGroup(title: "Targets", shortcuts: [
                Shortcut(keys: "click ◯", action: "Cycle a node's status: to do → in progress → done → N/A"),
                Shortcut(keys: "right-click", action: "Sub-node, add missing checklist items, set a status, delete"),
                Shortcut(keys: "Finding", action: "Turn the selected node into a finding (notes → evidence, host:port → affected)"),
                Shortcut(keys: "One-liners ▾", action: "The one-liners tagged for the selected host/port, with $RHOST, $RPORT and $RURL filled in — copy, or paste into the terminal"),
                Shortcut(keys: "double-click divider", action: "Reset the list/detail split (Targets, Findings, Knowledge base, Searchsploit)"),
            ]),
            ShortcutGroup(title: "Notes and library", shortcuts: [
                Shortcut(keys: "Edit / Read", action: "Notes are Markdown: edit the text, or read it rendered — every code block then has a copy button"),
                Shortcut(keys: "⋯ › Import folder", action: "Copy a folder of .md cheat sheets into the library (shared by all engagements); ⋯ › Download documentation fetches PayloadsAllTheThings, InternalAllTheThings or your own repository"),
                Shortcut(keys: "click a link", action: "Links between pages of a downloaded collection open inside Luik; web links open in the browser"),
            ]),
            ShortcutGroup(title: "Editing text", shortcuts: [
                Shortcut(keys: "⌘Z  ⌘⇧Z", action: "Undo / redo in notes and fields"),
                Shortcut(keys: "⌘A  ⌘X", action: "Select all / cut"),
                Shortcut(keys: "⌘F", action: "Find in a text field or the notes editor"),
            ]),
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Keyboard shortcuts")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(group.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(theme.accentColor)
                            ForEach(group.shortcuts) { shortcut in
                                HStack(alignment: .firstTextBaseline, spacing: 12) {
                                    Text(shortcut.keys)
                                        .font(.system(.callout, design: .monospaced).weight(.semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
                                        .frame(width: 170, alignment: .leading)
                                    Text(shortcut.action)
                                        .font(.callout)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                    }
                    Text("Menu bar: the Luik icon shows/hides the panel without the hotkey — handy while the hotkey is paused for a remote desktop. Every item above is also in the menus (Edit, Terminal, View, Tools, Help).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
            }
        }
        .frame(width: 680, height: 600)
    }
}
