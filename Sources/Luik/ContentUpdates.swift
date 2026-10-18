import AppKit
import Foundation
import Observation
import SwiftUI

/// One thing that can be updated: a library source with new commits, a newer knowledge base in
/// the catalogue, or a newer Luik.
struct ContentUpdate: Identifiable, Hashable {
    enum Kind: Hashable { case library, knowledgeBase, app }

    let id: String
    let kind: Kind
    let title: String
    let detail: String
}

/// The silent daily check of everything that can be downloaded: library sources (GitHub commit
/// behind the downloaded one), the knowledge-base catalogue (newer version of the imported file)
/// and Luik itself. Runs at most once a day, only when enabled in Settings, and never downloads
/// anything by itself — it only shows a badge.
@Observable
final class ContentUpdates {
    static let shared = ContentUpdates()

    var updates: [ContentUpdate] = []
    var isChecking = false
    var lastChecked: Date?
    var lastError: String?

    /// At launch: once per day, when the setting allows it.
    func checkAtLaunchIfDue() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: SettingsKey.checkContentUpdates) else { return }
        let last = defaults.double(forKey: SettingsKey.lastContentCheck)
        guard Date().timeIntervalSince1970 - last > 24 * 3600 else { return }
        // A little after launch, so the panel is up first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            self?.checkNow(includeApp: defaults.bool(forKey: SettingsKey.checkForUpdates))
        }
    }

    /// Checks everything; `includeApp` also asks GitHub for the latest Luik release.
    func checkNow(includeApp: Bool) {
        guard !isChecking else { return }
        isChecking = true
        lastError = nil
        Task { @MainActor in
            var found: [ContentUpdate] = []
            var failures: [String] = []

            // Library sources that are downloaded.
            let downloader = LibraryDownloader.shared
            for source in downloader.sources {
                guard let info = downloader.isDownloaded(source) else { continue }
                do {
                    let branch = try await downloader.resolveBranch(source)
                    let commit = try await downloader.fetchLatestCommit(repository: source.repository, branch: branch)
                    downloader.latestCommit[source.id] = commit
                    if commit.sha != info.commit {
                        let when = commit.date.map { " (" + $0.formatted(date: .abbreviated, time: .omitted) + ")" } ?? ""
                        found.append(ContentUpdate(id: "lib-" + source.id, kind: .library, title: source.name,
                                                   detail: "New commits on GitHub\(when); you have \(info.shortCommit) from \(info.downloadedAt.formatted(date: .abbreviated, time: .omitted))."))
                    }
                } catch {
                    failures.append("\(source.name): \(error.localizedDescription)")
                }
            }

            // Knowledge base from the catalogue.
            if let kb = KnowledgeBaseStore.shared.knowledgeBase, let catalogID = kb.catalogID {
                do {
                    if let url = KnowledgeBaseDownloader.normalize(KnowledgeBaseDownloader.configuredCatalogURL) {
                        let data = try await KnowledgeBaseDownloader.shared.fetch(url)
                        let catalog = try KnowledgeBaseDownloader.decodeCatalog(data)
                        if let entry = catalog.entries.first(where: { $0.id == catalogID }),
                           let latest = entry.version, !latest.isEmpty, latest != (kb.version ?? ""),
                           UpdateCheck.isVersion(latest, newerThan: kb.version ?? "0") {
                            found.append(ContentUpdate(id: "kb-" + catalogID, kind: .knowledgeBase, title: entry.name,
                                                       detail: "Version \(latest) in the catalogue; you have \(kb.version ?? "an older version")."))
                        }
                    }
                } catch {
                    failures.append("Knowledge base catalogue: \(error.localizedDescription)")
                }
            }

            // Luik itself.
            if includeApp {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    UpdateCheck.check { outcome in
                        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: SettingsKey.lastUpdateCheck)
                        if case .success(let release) = outcome, release.isNewer {
                            UIState.shared.updateAvailable = (release.latest, release.url)
                            found.append(ContentUpdate(id: "app", kind: .app, title: "Luik \(release.latest)",
                                                       detail: "A newer release is on GitHub; you run \(AppInfo.version)."))
                        }
                        continuation.resume()
                    }
                }
            }

            self.updates = found
            self.lastChecked = Date()
            self.lastError = failures.isEmpty ? nil : failures.joined(separator: " · ")
            self.isChecking = false
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: SettingsKey.lastContentCheck)
            if !found.isEmpty {
                ActivityLog.shared.record(.action, "Updates available: " + found.map { $0.title }.joined(separator: ", "), source: "Updates")
            }
        }
    }

    func dismiss(_ update: ContentUpdate) {
        updates.removeAll { $0.id == update.id }
    }
}

/// Top-bar badge "Updates (n)" with a popover listing what is new and where to get it.
struct ContentUpdatesButton: View {
    @Environment(UIState.self) private var ui
    @State private var showPopover = false

    var body: some View {
        let store = ContentUpdates.shared
        if !store.updates.isEmpty {
            Button {
                showPopover.toggle()
            } label: {
                Label("Updates (\(store.updates.count))", systemImage: "arrow.down.circle")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.green)
            .help("New versions of what you downloaded: click to see")
            .popover(isPresented: $showPopover, arrowEdge: .bottom) {
                ContentUpdatesList()
                    .padding(14)
                    .frame(width: 440)
            }
        }
    }
}

struct ContentUpdatesList: View {
    @Environment(UIState.self) private var ui

    var body: some View {
        let store = ContentUpdates.shared
        VStack(alignment: .leading, spacing: 10) {
            Text("Updates")
                .font(.headline)
            if store.updates.isEmpty {
                Text(store.isChecking ? "Checking…" : "Everything you downloaded is up to date.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(store.updates) { update in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: update.kind == .app ? "app.badge" : (update.kind == .library ? "books.vertical" : "tablecells"))
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(update.title)
                            .font(.callout.weight(.semibold))
                        Text(update.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button(update.kind == .app ? "Releases" : "Download…") {
                        switch update.kind {
                        case .library: ui.showLibrarySources = true
                        case .knowledgeBase: ui.showKnowledgeBaseDownload = true
                        case .app:
                            if let url = URL(string: ui.updateAvailable?.url ?? UpdateCheck.releasesPage) { NSWorkspace.shared.open(url) }
                        }
                    }
                    .controlSize(.small)
                    Button {
                        store.dismiss(update)
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Hide until the next check")
                }
            }
            if let error = store.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if let last = store.lastChecked {
                    Text("Checked \(last.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Button(store.isChecking ? "Checking…" : "Check now") {
                    store.checkNow(includeApp: UserDefaults.standard.bool(forKey: SettingsKey.checkForUpdates))
                }
                .disabled(store.isChecking)
                .controlSize(.small)
            }
        }
    }
}
