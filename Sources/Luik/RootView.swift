import AppKit
import SwiftUI

/// Blurs whatever is behind the panel, like a HUD window.
/// The blur layer follows the rounded corners through a maskImage; a layer mask on the
/// parent view is not always enough for that.
struct VisualEffectBackground: NSViewRepresentable {
    var cornerRadius: CGFloat
    var roundTopCorners: Bool

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.maskImage = VisualEffectBackground.maskImage(radius: cornerRadius, topCorners: roundTopCorners)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.maskImage = VisualEffectBackground.maskImage(radius: cornerRadius, topCorners: roundTopCorners)
    }

    /// Stretchable image (with capInsets) shaped like a rounded rectangle.
    static func maskImage(radius: CGFloat, topCorners: Bool) -> NSImage? {
        guard radius > 0 else { return nil }
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            let path: NSBezierPath
            if topCorners {
                path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
            } else {
                // Bottom corners only (non-flipped coordinates: y = 0 is the bottom).
                path = NSBezierPath()
                path.move(to: NSPoint(x: rect.minX, y: rect.maxY))
                path.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
                path.line(to: NSPoint(x: rect.maxX, y: rect.minY + radius))
                path.appendArc(withCenter: NSPoint(x: rect.maxX - radius, y: rect.minY + radius),
                               radius: radius, startAngle: 0, endAngle: -90, clockwise: true)
                path.line(to: NSPoint(x: rect.minX + radius, y: rect.minY))
                path.appendArc(withCenter: NSPoint(x: rect.minX + radius, y: rect.minY + radius),
                               radius: radius, startAngle: -90, endAngle: -180, clockwise: true)
                path.close()
            }
            NSColor.black.setFill()
            path.fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// The background of the whole panel: optional blur, with a dark layer on top whose
/// opacity is adjustable (Settings › Background opacity).
struct PanelBackground: View {
    @AppStorage(SettingsKey.panelOpacity) private var panelOpacity = 0.75
    @AppStorage(SettingsKey.panelBlur) private var panelBlur = true
    @AppStorage(SettingsKey.cornerRadius) private var cornerRadius = 14.0
    @AppStorage(SettingsKey.roundTopCorners) private var roundTopCorners = false

    static let tint = Color(red: 0.07, green: 0.08, blue: 0.10)

    var body: some View {
        ZStack {
            if panelBlur {
                VisualEffectBackground(cornerRadius: CGFloat(min(max(cornerRadius, 0), 60)),
                                       roundTopCorners: roundTopCorners)
            }
            PanelBackground.tint.opacity(min(max(panelOpacity, 0), 1))
        }
        .ignoresSafeArea()
    }
}

struct RootView: View {
    @Environment(UIState.self) private var ui
    @Environment(EngagementStore.self) private var engagements

    var body: some View {
        @Bindable var engagements = engagements
        VStack(spacing: 0) {
            TopBar()
            Divider()
            Group {
                switch ui.module {
                case .terminal:
                    TerminalModuleView()
                case .notes:
                    NotesView()
                case .snippets:
                    SnippetsView()
                case .targets:
                    TargetsView()
                case .findings:
                    FindingsView()
                case .knowledgeBase:
                    KnowledgeBaseView()
                case .exploits:
                    ExploitsView()
                case .chef:
                    ChefView()
                case .activity:
                    ActivityView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(PanelBackground())
        // Rounding/clipping happens at the AppKit level (DropdownController), so the
        // terminal view joins in and the corner radius is adjustable.
        .overlay(alignment: .top) {
            if ui.showPalette {
                ZStack(alignment: .top) {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                        .onTapGesture { ui.showPalette = false }
                    CommandPalette()
                        .padding(.top, 56)
                }
                .transition(.opacity)
            }
        }
        .sheet(isPresented: $engagements.showManager) {
            EngagementsManager()
        }
    }
}

struct TopBar: View {
    @Environment(UIState.self) private var ui

    var body: some View {
        @Bindable var ui = ui
        HStack(spacing: 4) {
            ForEach(Array(Module.allCases.enumerated()), id: \.element) { index, module in
                Button {
                    ui.module = module
                } label: {
                    Label(module.title, systemImage: module.icon)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(ui.module == module ? Color.white.opacity(0.14) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("\(module.title) (⌘\(index + 1))")
            }
            Spacer()
            EngagementMenu()
                .padding(.trailing, 8)
            if let update = ui.updateAvailable {
                Button {
                    if let url = URL(string: update.url) { NSWorkspace.shared.open(url) }
                } label: {
                    Label("Update \(update.version)", systemImage: "arrow.down.circle")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.green)
                .help("A newer Luik release is available on GitHub")
                .padding(.trailing, 8)
            }
            Button {
                ui.showPalette.toggle()
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.plain)
            .help("Search everything (⌘K)")
            .padding(.trailing, 8)
            Button {
                ui.showSettings.toggle()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .help("Settings")
            .popover(isPresented: $ui.showSettings, arrowEdge: .bottom) {
                SettingsView()
            }
            Button {
                AppDelegate.shared?.hideDropdown()
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.plain)
            .help("Hide (the hotkey works too)")
            .padding(.leading, 8)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}

struct SettingsView: View {
    @Environment(UIState.self) private var ui
    @AppStorage(SettingsKey.hotKey) private var hotKey = "cmd+escape"
    @AppStorage(SettingsKey.heightFraction) private var heightFraction = 0.55
    @AppStorage(SettingsKey.widthFraction) private var widthFraction = 1.0
    @AppStorage(SettingsKey.cornerRadius) private var cornerRadius = 14.0
    @AppStorage(SettingsKey.roundTopCorners) private var roundTopCorners = false
    @AppStorage(SettingsKey.animationDuration) private var animationDuration = 0.18
    @AppStorage(SettingsKey.hideOnFocusLoss) private var hideOnFocusLoss = true
    @AppStorage(SettingsKey.fontSize) private var fontSize = 13.0
    @AppStorage(SettingsKey.panelOpacity) private var panelOpacity = 0.75
    @AppStorage(SettingsKey.panelBlur) private var panelBlur = true
    @AppStorage(SettingsKey.terminalExtraOpacity) private var terminalExtraOpacity = 0.0
    @AppStorage(SettingsKey.shellPath) private var shellPath = "/bin/zsh"
    @AppStorage(SettingsKey.hostTemplate) private var hostTemplate = SettingsDefaults.hostTemplate
    @AppStorage(SettingsKey.portTemplate) private var portTemplate = SettingsDefaults.portTemplate
    @AppStorage(SettingsKey.serviceTemplates) private var serviceTemplates = SettingsDefaults.serviceTemplates
    @AppStorage(SettingsKey.showOnLaunch) private var showOnLaunch = true
    @AppStorage(SettingsKey.hotKeyPauseApps) private var hotKeyPauseApps = ""
    @AppStorage(SettingsKey.logTypedCommands) private var logTypedCommands = true
    @AppStorage(SettingsKey.evidenceFolder) private var evidenceFolder = ""
    @AppStorage(SettingsKey.hideWhileCapturing) private var hideWhileCapturing = true
    @AppStorage(SettingsKey.checkForUpdates) private var checkForUpdates = true
    @State private var checkingUpdates = false
    @State private var updateMessage: String? = nil

    struct HotKeySuggestion: Identifiable {
        let label: String
        let value: String
        var id: String { value }
    }

    /// Quick picks in the menu next to the recorder field.
    static let hotKeySuggestions: [HotKeySuggestion] = [
        HotKeySuggestion(label: "⌘ Esc  (default)", value: "cmd+escape"),
        HotKeySuggestion(label: "F12 (like Guake)", value: "f12"),
        HotKeySuggestion(label: "F1", value: "f1"),
        HotKeySuggestion(label: "F10", value: "f10"),
        HotKeySuggestion(label: "⌃ `  (control + backtick)", value: "ctrl+grave"),
        HotKeySuggestion(label: "⌥ `  (option + backtick)", value: "opt+grave"),
        HotKeySuggestion(label: "⌥ Space", value: "opt+space"),
        HotKeySuggestion(label: "⌃⌥ T", value: "ctrl+opt+t"),
        HotKeySuggestion(label: "⌘ §  (command + section sign, ISO keyboards)", value: "cmd+section"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Settings")
                .font(.headline)

            TabView {
                generalTab
                    .tabItem { Text("General") }
                appearanceTab
                    .tabItem { Text("Appearance") }
                terminalTab
                    .tabItem { Text("Terminal") }
                targetsTab
                    .tabItem { Text("Targets") }
                toolsTab
                    .tabItem { Text("Tools") }
            }

            HStack {
                Button("Open data folder") {
                    NSWorkspace.shared.open(Storage.directory)
                }
                Spacer()
                Text("Version \(AppInfo.version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 520, height: 600)
    }

    // MARK: Tabs

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent("Hotkey") {
                HStack(spacing: 6) {
                    HotKeyRecorder(value: $hotKey)
                        .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28)
                    Menu {
                        ForEach(SettingsView.hotKeySuggestions) { suggestion in
                            Button(suggestion.label) {
                                hotKey = suggestion.value
                            }
                        }
                        Divider()
                        Button("No hotkey") {
                            hotKey = ""
                        }
                    } label: {
                        Image(systemName: "list.bullet")
                    }
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Common choices")
                }
            }
            if let error = ui.hotKeyError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            caption("Click the field and press the key or combination you want (e.g. F12, ⌃`, ⌥Space or ⌘⇧T). Esc cancels, ⌫ clears the hotkey. Letters and digits only in combination with ⌃, ⌥ or ⌘. On a MacBook keyboard, function keys usually need fn held down unless \"Use F1, F2, etc. keys as standard function keys\" is enabled in System Settings › Keyboard.")

            LabeledContent("Pause hotkey in") {
                TextField("e.g. Windows App, Remote Desktop, Parallels", text: $hotKeyPauseApps)
                    .textFieldStyle(.roundedBorder)
            }
            caption("While one of these apps (name or bundle id, comma-separated) is active, the hotkey is paused and the key goes straight to that app, e.g. to a remote desktop or VM. Open Luik from the menu bar icon in the meantime.")

            Divider()

            Toggle("Hide when another app gets focus", isOn: $hideOnFocusLoss)
            Toggle("Show Luik at launch", isOn: $showOnLaunch)

            Divider()

            HStack {
                Text("Engagements")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("Manage…") {
                    ui.showSettings = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { EngagementStore.shared.showManager = true }
                }
                .controlSize(.small)
            }
            caption("Targets, notes, findings, the log and evidence screenshots are kept per engagement (briefcase menu in the top bar). One-liners, the knowledge base, Exploit-DB, Chef recipes and connections are shared. Each engagement has a scope list; hosts outside it are flagged in Targets and in the import summary.")

            Spacer(minLength: 0)
        }
        .padding(12)
    }

    private var toolsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Evidence screenshots")
                .font(.subheadline.weight(.semibold))
            LabeledContent("Folder") {
                TextField("~/Documents/Luik Evidence", text: $evidenceFolder)
                    .textFieldStyle(.roundedBorder)
            }
            Toggle("Hide Luik while selecting the screenshot area", isOn: $hideWhileCapturing)
            caption("⌘⇧E takes a screenshot with macOS's own screencapture (drag an area, or press space and click a window). It is saved with a timestamp in a subfolder per engagement, linked in the notes of the selected target node (or the open finding) and written to the Log. macOS asks once for Screen Recording permission for Luik.")

            Divider()

            Text("Search everything")
                .font(.subheadline.weight(.semibold))
            caption("⌘K opens one search box over notes, one-liners, targets, findings, knowledge base, Exploit-DB, Chef operations, the log, engagements and actions. ↑↓ to choose, ↩ to open, esc to close.")

            Divider()

            Text("Updates")
                .font(.subheadline.weight(.semibold))
            HStack {
                Toggle("Check for updates at launch", isOn: $checkForUpdates)
                Spacer()
                Button("Check now") { runUpdateCheck() }
                    .disabled(checkingUpdates)
            }
            if let updateMessage {
                Text(updateMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            caption("Looks at the latest release of \(AppInfo.repository) on GitHub. Nothing else is sent.")
            Spacer(minLength: 0)
        }
        .padding(12)
    }

    private func runUpdateCheck() {
        checkingUpdates = true
        updateMessage = "Checking…"
        UpdateCheck.check { outcome in
            checkingUpdates = false
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: SettingsKey.lastUpdateCheck)
            switch outcome {
            case .success(let release):
                if release.isNewer {
                    updateMessage = "Version \(release.latest) is available (you have \(AppInfo.version)): \(release.url)"
                    ui.updateAvailable = (release.latest, release.url)
                } else {
                    updateMessage = "You have the latest version (\(AppInfo.version); latest release \(release.latest))."
                }
            case .failure(let error):
                updateMessage = "Could not check: \(error.localizedDescription)"
            }
        }
    }

    private var appearanceTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            percentRow("Height", value: $heightFraction, range: 0.25...1.0, step: 0.05)
            percentRow("Width", value: $widthFraction, range: 0.4...1.0, step: 0.05)
            LabeledContent("Corner radius") {
                Slider(value: $cornerRadius, in: 0...40, step: 1)
                Text("\(Int(cornerRadius.rounded())) pt")
                    .monospacedDigit()
                    .frame(width: 52, alignment: .trailing)
            }
            Toggle("Round the top corners too", isOn: $roundTopCorners)
            LabeledContent("Animation") {
                Slider(value: $animationDuration, in: 0...0.6, step: 0.02)
                Text(animationDuration < 0.02 ? "instant" : "\(Int((animationDuration * 1000).rounded())) ms")
                    .monospacedDigit()
                    .frame(width: 52, alignment: .trailing)
            }
            caption("How long the panel takes to slide down; sliding up is slightly faster. All the way left = no animation.")

            Divider()

            percentRow("Background opacity", value: $panelOpacity, range: 0.0...1.0, step: 0.05)
            Toggle("Blur what is behind the panel", isOn: $panelBlur)
            percentRow("Extra terminal opacity", value: $terminalExtraOpacity, range: 0.0...1.0, step: 0.05)
            caption("Background opacity applies to the whole panel, every tab. With blur on, the panel is at least as opaque as the macOS HUD style; turn blur off for full transparency, like Guake. Extra terminal opacity adds a dark layer under the terminal text only.")
            Spacer(minLength: 0)
        }
        .padding(12)
    }

    private var terminalTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent("Font size") {
                Stepper(value: $fontSize, in: 9...24, step: 1) {
                    Text("\(Int(fontSize)) pt")
                        .monospacedDigit()
                }
            }
            LabeledContent("Shell") {
                TextField("/bin/zsh", text: $shellPath)
                    .textFieldStyle(.roundedBorder)
            }
            caption("The shell applies to new tabs; font size and opacity also apply to existing ones right away. The shell is started as a login shell, so your PATH and aliases are loaded.")

            Divider()

            Toggle("Log typed commands to the Log tab", isOn: $logTypedCommands)
            caption("Every line you type in a Luik terminal tab is recorded with a timestamp. Lines typed while the terminal has echo off (password prompts of sudo, ssh, …) are never recorded. Commands pasted from One-liners or Searchsploit are always logged.")
            Spacer(minLength: 0)
        }
        .padding(12)
    }

    private var targetsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Work-item nodes (comma-separated)")
                .font(.subheadline.weight(.semibold))
            LabeledContent("Per system") {
                TextField("", text: $hostTemplate)
                    .textFieldStyle(.roundedBorder)
            }
            LabeledContent("Per port") {
                TextField("", text: $portTemplate)
                    .textFieldStyle(.roundedBorder)
            }
            caption("Used when importing nmap output and by \"Template\" in the Targets tab. Existing nodes are left alone; \"Template\" adds the missing ones.")

            Divider()

            HStack {
                Text("Per service")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("Reset to defaults") { serviceTemplates = SettingsDefaults.serviceTemplates }
                    .controlSize(.small)
            }
            TextEditor(text: $serviceTemplates)
                .font(.system(.caption, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(4)
                .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
                .frame(minHeight: 140)
            caption("One line per service: nmap service names and/or port numbers before the colon, the work items after it. A port gets the first matching line (service name first, then port number) instead of the generic list above.")
        }
        .padding(12)
    }

    // MARK: Helper views

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func percentRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double) -> some View {
        LabeledContent(title) {
            Slider(value: value, in: range, step: step)
            Text("\(Int((value.wrappedValue * 100).rounded()))%")
                .monospacedDigit()
                .frame(width: 52, alignment: .trailing)
        }
    }
}
