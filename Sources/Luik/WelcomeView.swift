import AppKit
import SwiftUI

/// First-start sheet (Help › Welcome to Luik… later): the four things that make Luik useful on
/// a new Mac, each with a button and a tick when it is done. Nothing happens without a click.
struct WelcomeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(UIState.self) private var ui
    @Environment(EngagementStore.self) private var engagements
    @AppStorage(SettingsKey.welcomeShown) private var welcomeShown = false
    @State private var shellMessage: String?

    private var hasKnowledgeBase: Bool { KnowledgeBaseStore.shared.knowledgeBase != nil }
    private var hasLibrary: Bool { LibraryStore.shared.collections.contains { $0.source != nil } }
    private var hasShell: Bool { ShellIntegration.isInstalled(.zsh) || ShellIntegration.isInstalled(.bash) }
    private var hasEngagement: Bool { engagements.engagements.count > 1 || !engagements.current.scope.isEmpty || !engagements.current.client.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "terminal.fill")
                    .font(.title)
                Text("Welcome to Luik")
                    .font(.title2.weight(.semibold))
            }
            Text("Luik is empty on a new Mac on purpose — everything it knows is downloaded or yours. Four steps make it useful; each is one click and can be done later from the menus.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            step(done: hasKnowledgeBase, icon: "tablecells", title: "Knowledge base",
                 text: "Attack vectors with description, impact and recommendation (English or Dutch) — Create finding on a record fills the report text.") {
                Button("Download…") { ui.showKnowledgeBaseDownload = true }
            }
            step(done: hasLibrary, icon: "books.vertical", title: "Documentation",
                 text: "PayloadsAllTheThings and InternalAllTheThings into the library, searchable and linked from one-liners and checklist items; updates with one click.") {
                Button("Download…") { ui.showLibrarySources = true }
            }
            step(done: hasShell, icon: "terminal", title: "Shell integration",
                 text: "One line in ~/.zshrc so Luik knows exactly where a command's output starts and ends, and its exit status. Only active inside Luik's tabs.") {
                Button(hasShell ? "Installed" : "Install for zsh") {
                    shellMessage = ShellIntegration.install(.zsh)
                }
                .disabled(hasShell)
            }
            step(done: hasEngagement, icon: "folder.badge.person.crop", title: "Engagement",
                 text: "Client, scope and exclusions per engagement: Targets, findings, log, notes and diagrams live inside it, and commands naming a host outside the scope get a warning.") {
                Button("Set up…") { engagements.showManager = true }
            }
            step(done: DemoEngagement.exists, icon: "sparkles", title: "Or look at the demo first",
                 text: "A fictional engagement with hosts, findings, a plan, a diagram and log lines, so you see how the tabs hang together. Delete it from Manage engagements afterwards.") {
                Button(DemoEngagement.exists ? "Open demo" : "Create demo") {
                    DemoEngagement.create()
                    welcomeShown = true
                    dismiss()
                }
            }
            if let shellMessage {
                Text(shellMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                Text("Later: Help › Welcome to Luik…, or ⌘K “welcome”.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Close") {
                    welcomeShown = true
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 560)
    }

    private func step<Action: View>(done: Bool, icon: String, title: String, text: String, @ViewBuilder action: () -> Action) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : icon)
                .foregroundStyle(done ? Color.green : Color.secondary)
                .frame(width: 22)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            action()
                .controlSize(.small)
        }
    }
}
