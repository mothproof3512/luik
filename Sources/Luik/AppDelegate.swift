import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) var shared: AppDelegate?

    private var statusItem: NSStatusItem?
    private var dropdown: DropdownController?
    private let hotKey = HotKeyManager()

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: SettingsDefaults.all)
        migrateDefaultHotKeyIfNeeded()

        // Shells we start inherit the working directory; start in the home folder instead of "/".
        FileManager.default.changeCurrentDirectoryPath(NSHomeDirectory())

        buildMainMenu()
        setupStatusItem()

        let root = RootView()
            .environment(UIState.shared)
            .environment(TerminalStore.shared)
            .environment(NotesStore.shared)
            .environment(SnippetStore.shared)
            .environment(TargetStore.shared)
            .environment(KnowledgeBaseStore.shared)
            .environment(ExploitStore.shared)
            .environment(ChefStore.shared)
            .environment(ActivityLog.shared)
            .environment(ConnectionStore.shared)
            .environment(EngagementStore.shared)
            .environment(FindingsStore.shared)
            .environment(ChecklistStore.shared)
            .environment(LibraryStore.shared)
            .environment(DiagramStore.shared)
        let controller = DropdownController(rootView: root)
        controller.onDidShow = {
            if UIState.shared.module == .terminal {
                TerminalStore.shared.focusSelected()
            }
        }
        dropdown = controller

        TerminalStore.shared.ensureSession()

        hotKey.onTrigger = { [weak self] in
            self?.toggleDropdown()
        }
        refreshHotKey()

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(defaultsChanged), name: UserDefaults.didChangeNotification, object: nil)
        center.addObserver(self, selector: #selector(applicationResignedActive), name: NSApplication.didResignActiveNotification, object: nil)
        // When another app becomes active: pause the hotkey if needed (e.g. in a remote desktop).
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(frontmostAppChanged),
                                                          name: NSWorkspace.didActivateApplicationNotification, object: nil)

        if UserDefaults.standard.bool(forKey: SettingsKey.showOnLaunch) {
            showDropdown()
        }
        UpdateCheck.checkAtLaunchIfDue()
    }

    func applicationWillTerminate(_ notification: Notification) {
        flushAllStores()
        TerminalStore.shared.terminateAll()
        hotKey.unregister()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Writes every pending autosave right now (hide, quit, engagement switch).
    private var viewMenu: NSMenu?

    func flushAllStores() {
        NotesStore.shared.flush()
        LibraryStore.shared.flush()
        DiagramStore.shared.flush()
        SnippetStore.shared.flush()
        TargetStore.shared.flush()
        FindingsStore.shared.flush()
        ChefStore.shared.flush()
        ChecklistStore.shared.flush()
        ActivityLog.shared.flush()
    }

    // MARK: - Show / hide

    @objc func toggleDropdown() {
        guard let dropdown else { return }
        let willShow = !(dropdown.isShown && NSApp.isActive)
        dropdown.toggle()
        if willShow {
            focusIfTerminal()
        } else {
            flushAllStores()
        }
    }

    @objc func showDropdown() {
        dropdown?.show()
        focusIfTerminal()
    }

    @objc func hideDropdown() {
        dropdown?.hide()
        flushAllStores()
    }

    @objc func openSettings() {
        showDropdown()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            UIState.shared.showSettings = true
        }
    }

    /// ⌘⇧E: screenshot evidence with macOS's screencapture; hides the panel first when asked to.
    @objc func captureEvidenceHidingLuik() {
        captureEvidence(hideLuik: UserDefaults.standard.bool(forKey: SettingsKey.hideWhileCapturing))
    }

    @objc func captureEvidenceKeepingLuik() {
        captureEvidence(hideLuik: false)
    }

    /// `onCapture` gets the saved file (e.g. to link it in a finding) besides the usual
    /// attachment to the selected target node and the log entry.
    func captureEvidence(hideLuik: Bool, onCapture: ((URL) -> Void)? = nil) {
        let wasShown = dropdown?.isShown ?? false
        let run = {
            EvidenceCapture.capture { url in
                if hideLuik && wasShown {
                    self.showDropdown()
                }
                if let url {
                    onCapture?(url)
                }
                if url != nil, onCapture == nil, UIState.shared.module != .targets, TargetStore.shared.selectedNode == nil {
                    UIState.shared.module = .activity
                }
            }
        }
        if hideLuik && wasShown {
            dropdown?.hide(restoreFocus: false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: run)
        } else {
            run()
        }
    }

    @objc func togglePalette() {
        if !(dropdown?.isShown ?? false) {
            showDropdown()
        }
        UIState.shared.showPalette.toggle()
    }

    private func focusIfTerminal() {
        if UIState.shared.module == .terminal {
            TerminalStore.shared.focusSelected(afterDelay: true)
        }
    }

    @objc private func applicationResignedActive() {
        guard let dropdown, dropdown.isShown else { return }
        if UserDefaults.standard.bool(forKey: SettingsKey.hideOnFocusLoss) {
            dropdown.hide(restoreFocus: false)
            flushAllStores()
        }
    }

    // MARK: - Hotkey and settings

    /// Up to version 0.5 the default was F12. If that old default is still stored, remove it once
    /// so the new default (⌘Esc) applies. Any choice made after that is left alone.
    private func migrateDefaultHotKeyIfNeeded() {
        let defaults = UserDefaults.standard
        let flag = "hotKeyDefaultMigrated_v6"
        guard !defaults.bool(forKey: flag) else { return }
        defaults.set(true, forKey: flag)
        if let stored = defaults.string(forKey: SettingsKey.hotKey), stored == "f12" {
            defaults.removeObject(forKey: SettingsKey.hotKey)
        }
    }

    /// Registers the chosen hotkey, or temporarily removes it while an app from the
    /// "pause in" list (e.g. Windows App / Remote Desktop / Parallels) is the active app.
    private func refreshHotKey() {
        if shouldPauseHotKey(for: NSWorkspace.shared.frontmostApplication) {
            hotKey.unregister()
            return
        }
        let stored = UserDefaults.standard.string(forKey: SettingsKey.hotKey) ?? ""
        guard let combo = HotKeyCombo(string: stored) else {
            hotKey.unregister() // empty or invalid = no hotkey
            UIState.shared.hotKeyError = nil
            return
        }
        if hotKey.currentCombo != combo {
            hotKey.register(combo)
            UIState.shared.hotKeyError = hotKey.lastError
        }
    }

    private func shouldPauseHotKey(for app: NSRunningApplication?) -> Bool {
        guard let app, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return false }
        let raw = UserDefaults.standard.string(forKey: SettingsKey.hotKeyPauseApps) ?? ""
        let patterns = SettingsDefaults.templateItems(raw).map { $0.lowercased() }
        guard !patterns.isEmpty else { return false }
        let name = (app.localizedName ?? "").lowercased()
        let bundleID = (app.bundleIdentifier ?? "").lowercased()
        return patterns.contains { name.contains($0) || bundleID.contains($0) }
    }

    @objc private func frontmostAppChanged() {
        refreshHotKey()
    }

    @objc private func defaultsChanged() {
        refreshHotKey()
        dropdown?.relayoutIfShown()
        TerminalStore.shared.applyAppearance()
    }

    // MARK: - Menu bar item

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "chevron.down.square", accessibilityDescription: "Luik")
            button.toolTip = "Luik"
        }
        let menu = NSMenu()
        let toggleItem = NSMenuItem(title: "Show/Hide Luik", action: #selector(toggleDropdown), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Luik", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
        item.menu = menu
        statusItem = item
    }

    // MARK: - Main menu (needed for ⌘C/⌘V and the keyboard shortcuts)

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "Show/Hide Luik", action: #selector(toggleDropdown), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Hide Luik", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit Luik", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenu.addItem(.separator())
        let findMenuItem = NSMenuItem(title: "Find", action: nil, keyEquivalent: "")
        let findMenu = NSMenu(title: "Find")
        let findAction = #selector(NSTextView.performFindPanelAction(_:))
        let find = NSMenuItem(title: "Find…", action: findAction, keyEquivalent: "f")
        find.tag = Int(NSFindPanelAction.showFindPanel.rawValue)
        findMenu.addItem(find)
        let findNext = NSMenuItem(title: "Find Next", action: findAction, keyEquivalent: "g")
        findNext.tag = Int(NSFindPanelAction.next.rawValue)
        findMenu.addItem(findNext)
        let findPrevious = NSMenuItem(title: "Find Previous", action: findAction, keyEquivalent: "G")
        findPrevious.tag = Int(NSFindPanelAction.previous.rawValue)
        findMenu.addItem(findPrevious)
        let useSelection = NSMenuItem(title: "Use Selection for Find", action: findAction, keyEquivalent: "e")
        useSelection.tag = Int(NSFindPanelAction.setFindString.rawValue)
        findMenu.addItem(useSelection)
        findMenuItem.submenu = findMenu
        editMenu.addItem(findMenuItem)
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        let toolsMenuItem = NSMenuItem()
        let toolsMenu = NSMenu(title: "Tools")
        toolsMenu.addItem(NSMenuItem(title: "Search Everything…", action: #selector(togglePalette), keyEquivalent: "k"))
        let capture = NSMenuItem(title: "Capture Evidence Screenshot", action: #selector(captureEvidenceHidingLuik), keyEquivalent: "e")
        capture.keyEquivalentModifierMask = [.command, .shift]
        toolsMenu.addItem(capture)
        let captureVisible = NSMenuItem(title: "Capture Evidence (keep Luik visible)", action: #selector(captureEvidenceKeepingLuik), keyEquivalent: "e")
        captureVisible.keyEquivalentModifierMask = [.command, .shift, .option]
        toolsMenu.addItem(captureVisible)
        toolsMenu.addItem(.separator())
        toolsMenu.addItem(NSMenuItem(title: "Open Evidence Folder", action: #selector(openEvidenceFolder), keyEquivalent: ""))
        toolsMenu.addItem(.separator())
        toolsMenu.addItem(NSMenuItem(title: "New Finding", action: #selector(newFinding), keyEquivalent: "n"))
        toolsMenu.addItem(NSMenuItem(title: "Manage Engagements…", action: #selector(manageEngagements), keyEquivalent: ""))
        toolsMenu.addItem(NSMenuItem(title: "Edit Checklists…", action: #selector(editChecklists), keyEquivalent: ""))
        toolsMenu.addItem(NSMenuItem(title: "Download Knowledge Base…", action: #selector(downloadKnowledgeBase), keyEquivalent: ""))
        toolsMenu.addItem(NSMenuItem(title: "Download Documentation (Library)…", action: #selector(downloadDocumentation), keyEquivalent: ""))
        toolsMenu.addItem(NSMenuItem(title: "Reverse Shell Generator…", action: #selector(showReverseShell), keyEquivalent: ""))
        toolsMenu.addItem(NSMenuItem(title: "Import Cheat Sheets into Library…", action: #selector(importCheatSheets), keyEquivalent: ""))
        toolsMenuItem.submenu = toolsMenu
        mainMenu.addItem(toolsMenuItem)

        let terminalMenuItem = NSMenuItem()
        let terminalMenu = NSMenu(title: "Terminal")
        terminalMenu.addItem(NSMenuItem(title: "New Tab", action: #selector(newTerminalTab), keyEquivalent: "t"))
        terminalMenu.addItem(NSMenuItem(title: "Close Tab", action: #selector(closeTerminalTab), keyEquivalent: "w"))
        let nextItem = NSMenuItem(title: "Next Tab", action: #selector(nextTerminalTab), keyEquivalent: "]")
        nextItem.keyEquivalentModifierMask = [.command, .shift]
        terminalMenu.addItem(nextItem)
        let previousItem = NSMenuItem(title: "Previous Tab", action: #selector(previousTerminalTab), keyEquivalent: "[")
        previousItem.keyEquivalentModifierMask = [.command, .shift]
        terminalMenu.addItem(previousItem)
        terminalMenuItem.submenu = terminalMenu
        mainMenu.addItem(terminalMenuItem)

        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        self.viewMenu = viewMenu
        rebuildViewMenu()
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        let helpMenuItem = NSMenuItem()
        let helpMenu = NSMenu(title: "Help")
        helpMenu.addItem(NSMenuItem(title: "Keyboard Shortcuts", action: #selector(showShortcuts), keyEquivalent: "/"))
        helpMenu.addItem(NSMenuItem(title: "Knowledge Base Template…", action: #selector(saveKnowledgeBaseTemplate), keyEquivalent: ""))
        helpMenu.addItem(.separator())
        helpMenu.addItem(NSMenuItem(title: "Luik on GitHub (README, releases)", action: #selector(openRepository), keyEquivalent: ""))
        helpMenuItem.submenu = helpMenu
        mainMenu.addItem(helpMenuItem)
        NSApp.helpMenu = helpMenu

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Menu actions

    @objc private func openEvidenceFolder() {
        try? FileManager.default.createDirectory(at: EvidenceCapture.folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(EvidenceCapture.folder)
    }

    @objc private func newFinding() {
        showDropdown()
        UIState.shared.module = .findings
        FindingsStore.shared.newFinding()
    }

    @objc private func manageEngagements() {
        showDropdown()
        EngagementStore.shared.showManager = true
    }

    @objc private func editChecklists() {
        showDropdown()
        ChecklistStore.shared.showEditor = true
    }

    @objc private func showShortcuts() {
        showDropdown()
        UIState.shared.showShortcuts = true
    }

    @objc private func saveKnowledgeBaseTemplate() {
        KnowledgeBaseTemplate.save()
    }

    @objc private func downloadKnowledgeBase() {
        showDropdown()
        UIState.shared.module = .knowledgeBase
        UIState.shared.showKnowledgeBaseDownload = true
    }

    @objc private func showReverseShell() {
        showDropdown()
        UIState.shared.showReverseShell = true
    }

    @objc private func downloadDocumentation() {
        showDropdown()
        UIState.shared.module = .notes
        UIState.shared.showLibrarySources = true
    }

    @objc private func importCheatSheets() {
        showDropdown()
        UIState.shared.module = .notes
        LibraryStore.shared.importWithPanel()
    }

    @objc private func openRepository() {
        if let url = URL(string: "https://github.com/\(AppInfo.repository)") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func newTerminalTab() {
        UIState.shared.module = .terminal
        TerminalStore.shared.newSession()
    }

    @objc private func closeTerminalTab() {
        guard UIState.shared.module == .terminal, let session = TerminalStore.shared.selected else { return }
        TerminalStore.shared.close(session)
    }

    @objc private func nextTerminalTab() {
        TerminalStore.shared.selectNext()
    }

    @objc private func previousTerminalTab() {
        TerminalStore.shared.selectPrevious()
    }

    /// The View menu follows the tab order of the top bar: ⌘1 is the first tab, and so on.
    func rebuildViewMenu() {
        guard let viewMenu else { return }
        viewMenu.removeAllItems()
        for (index, module) in UIState.shared.tabOrder.enumerated() {
            let item = NSMenuItem(title: module.title, action: #selector(switchModule(_:)), keyEquivalent: index < 9 ? "\(index + 1)" : "")
            item.representedObject = module.rawValue
            viewMenu.addItem(item)
        }
        viewMenu.addItem(.separator())
        viewMenu.addItem(NSMenuItem(title: "Reset Tab Order", action: #selector(resetTabOrder), keyEquivalent: ""))
    }

    @objc private func resetTabOrder() {
        UIState.shared.resetTabOrder()
    }

    @objc private func switchModule(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let module = Module(rawValue: raw) else { return }
        UIState.shared.module = module
        if module == .terminal {
            TerminalStore.shared.focusSelected(afterDelay: true)
        }
    }
}
