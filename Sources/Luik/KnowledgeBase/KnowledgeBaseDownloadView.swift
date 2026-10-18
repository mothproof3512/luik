import AppKit
import SwiftUI

/// "Download a knowledge base": the catalogue of the Luik repository (or the one configured in
/// Settings › Integrations) with an Import button per entry, plus a field for any other file or
/// catalogue link — for a team's own GitHub repository, for example.
struct KnowledgeBaseDownloadView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.luikTheme) private var theme
    @Environment(KnowledgeBaseStore.self) private var store

    var body: some View {
        @Bindable var downloader = KnowledgeBaseDownloader.shared
        VStack(spacing: 0) {
            HStack {
                Text("Download a knowledge base")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    catalogSection
                    Divider()
                    customSection(downloader: $downloader)
                }
                .padding(14)
            }
            Divider()
            HStack(spacing: 8) {
                if downloader.isDownloading {
                    ProgressView()
                        .controlSize(.small)
                }
                if let status = downloader.status {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(downloader.statusIsError ? Color.orange : Color.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
                Spacer()
                Text("The data stays on this Mac, in ~/Library/Application Support/Luik/.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 680, height: 560)
        .onAppear {
            KnowledgeBaseDownloader.shared.prepare()
        }
        .onChange(of: downloader.importedAt) { _, imported in
            // Close once a download has been imported, so the new knowledge base is in view.
            if imported != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { dismiss() }
            }
        }
    }

    // MARK: Catalogue

    private var catalogSection: some View {
        let downloader = KnowledgeBaseDownloader.shared
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(downloader.catalog?.name ?? (downloader.isUsingDefaultCatalog ? "From the Luik repository" : "Catalogue"))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if !downloader.isUsingDefaultCatalog, downloader.catalog != nil {
                    Button("Back to the default catalogue") { downloader.loadCatalog() }
                        .buttonStyle(.link)
                        .font(.caption)
                }
                Button {
                    downloader.loadCatalog(from: downloader.catalogURL?.absoluteString)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .disabled(downloader.isLoadingCatalog)
                .help("Reload the catalogue")
            }
            if let url = downloader.catalogURL {
                Text(url.absoluteString)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            if downloader.isLoadingCatalog {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading the catalogue…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let error = downloader.catalogError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Text("No internet access, or the catalogue moved? Check Settings › Integrations › Knowledge base catalogue, or paste a direct link to the file below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let catalog = downloader.catalog {
                if catalog.entries.isEmpty {
                    Text("The catalogue is empty.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(catalog.entries) { entry in
                        entryRow(entry)
                    }
                }
            }
        }
    }

    private func entryRow(_ entry: KBCatalogEntry) -> some View {
        let downloader = KnowledgeBaseDownloader.shared
        let installed = store.knowledgeBase?.catalogID == entry.id
        let sameVersion = installed && (store.knowledgeBase?.version ?? "") == (entry.version ?? "")
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: "tablecells")
                .foregroundStyle(theme.accentColor)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.name)
                        .font(.callout.weight(.semibold))
                    if installed {
                        Text(sameVersion ? "imported" : "imported: version \(store.knowledgeBase?.version ?? "?")")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.white.opacity(0.1), in: Capsule())
                    }
                }
                if !entry.detail.isEmpty {
                    Text(entry.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let description = entry.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            Button {
                downloader.download(entry)
            } label: {
                Label(sameVersion ? "Re-import" : (installed ? "Update" : "Import"), systemImage: "icloud.and.arrow.down")
                    .frame(width: 96)
            }
            .buttonStyle(.borderedProminent)
            .tint(sameVersion ? Color.gray : theme.accentColor)
            .disabled(downloader.isDownloading)
            .help(installed && !sameVersion
                  ? "Replace the imported version \(store.knowledgeBase?.version ?? "?") with version \(entry.version ?? "?")"
                  : "Download and import; replaces the knowledge base that is imported now")
        }
        .padding(8)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Own file or catalogue

    private func customSection(downloader: Bindable<KnowledgeBaseDownloader>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your own file or catalogue")
                .font(.subheadline.weight(.semibold))
            Text("A link to an .xlsx, .csv, .tsv or .json file — on GitHub, GitLab, a web server or a share — or to a catalog.json that lists several files (the format is in knowledge-base/README.md of the repository). GitHub page links (…/blob/…) are turned into downloads automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("https://github.com/you/your-repo/blob/main/findings.xlsx", text: downloader.customURL)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .onSubmit { KnowledgeBaseDownloader.shared.importCustomURL() }
            HStack(spacing: 8) {
                SecureField("Access token (optional — private repositories)", text: downloader.token)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 360)
                    .help("Sent as an Authorization header (GitHub: a fine-grained token with read access to the repository's contents). Stored in your login keychain, not in a settings file.")
                Spacer()
                Button {
                    KnowledgeBaseDownloader.shared.importCustomURL()
                } label: {
                    Label("Import from link", systemImage: "icloud.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .disabled(KnowledgeBaseDownloader.shared.isDownloading
                          || downloader.wrappedValue.customURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text("Tip: a catalogue URL in Settings › Integrations makes your team's repository the default list above.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}
