import AppKit
import SwiftUI

/// "Download documentation": PayloadsAllTheThings, InternalAllTheThings and any GitHub
/// repository of Markdown files, with Download / Update / Remove per source.
struct LibrarySourcesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.luikTheme) private var theme
    @Environment(LibraryStore.self) private var library
    @State private var newRepository = ""
    @State private var newName = ""
    @State private var newBranch = ""
    @State private var addError: String?
    @State private var removing: LibrarySource?

    var body: some View {
        @Bindable var downloader = LibraryDownloader.shared
        VStack(spacing: 0) {
            HStack {
                Text("Download documentation into the library")
                    .font(.headline)
                Spacer()
                Button {
                    downloader.checkForUpdates()
                } label: {
                    Label("Check for updates", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(downloader.isChecking || !downloader.progress.isEmpty)
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Each source is a GitHub repository of Markdown pages; Luik downloads the repository as an archive, keeps the Markdown files and shows them under Library in the Notes tab — searchable, with every code block one click from the clipboard. Update replaces the copy with the latest commit (your edits to downloaded pages are lost then; keep your own notes in your own collection).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(downloader.sources) { source in
                        sourceRow(source)
                    }
                    Divider()
                    addSection
                    Divider()
                    HStack(spacing: 8) {
                        SecureField("GitHub access token (optional — private repositories, higher rate limit)", text: $downloader.token)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 420)
                            .onSubmit { downloader.saveToken() }
                        Button("Save token") { downloader.saveToken() }
                            .font(.caption)
                        Spacer()
                    }
                    Text("The token is sent as an Authorization header to GitHub only and stored in your login keychain.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(14)
            }
            Divider()
            HStack(spacing: 8) {
                if downloader.isChecking || !downloader.progress.isEmpty {
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
                Button("Show library folder") { library.revealInFinder() }
                    .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 720, height: 600)
        .onAppear {
            LibraryDownloader.shared.prepare()
            library.scanIfNeeded()
        }
        .confirmationDialog("Remove “\(removing?.name ?? "")” from the library?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button("Remove", role: .destructive) {
                if let source = removing {
                    library.removeCollection(source.name)
                    if !source.builtIn {
                        LibraryDownloader.shared.removeCustomSource(source)
                    }
                }
                removing = nil
            }
        } message: {
            Text("The downloaded files are moved to the Bin; you can download them again at any time.")
        }
    }

    private func sourceRow(_ source: LibrarySource) -> some View {
        let downloader = LibraryDownloader.shared
        let info = downloader.isDownloaded(source)
        let busy = downloader.progress[source.id]
        let update = downloader.hasUpdate(source)
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: "books.vertical")
                .foregroundStyle(theme.accentColor)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(source.name)
                        .font(.callout.weight(.semibold))
                    if let url = URL(string: source.pageURL) {
                        Link(source.repository, destination: url)
                            .font(.caption)
                    }
                    if update {
                        Text("update available")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.3), in: Capsule())
                    } else if info != nil, downloader.latestCommit[source.id] != nil {
                        Text("up to date")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.white.opacity(0.1), in: Capsule())
                    }
                }
                if !source.summary.isEmpty {
                    Text(source.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let info {
                    Text("\(info.documentCount) documents · downloaded \(info.downloadedAt.formatted(date: .abbreviated, time: .shortened)) · commit \(info.shortCommit)\(info.commitDate.map { " of \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "") · branch \(info.branch)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if let busy {
                    Text(busy)
                        .font(.caption)
                        .foregroundStyle(theme.accentColor)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Button {
                    downloader.download(source)
                } label: {
                    Label(info == nil ? "Download" : (update ? "Update" : "Download again"), systemImage: "icloud.and.arrow.down")
                        .frame(width: 128)
                }
                .buttonStyle(.borderedProminent)
                .tint(info == nil || update ? theme.accentColor : Color.gray)
                .disabled(busy != nil)
                if info != nil || !source.builtIn {
                    Button(role: .destructive) {
                        removing = source
                    } label: {
                        Text(info != nil ? "Remove" : "Forget")
                            .frame(width: 128)
                    }
                    .disabled(busy != nil)
                }
            }
        }
        .padding(8)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }

    private var addSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add a repository")
                .font(.subheadline.weight(.semibold))
            Text("Your own cheat-sheet repository, a team wiki exported as Markdown, or another documentation project on GitHub: owner/name (a github.com link works too). Only the Markdown files are kept.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                TextField("owner/repository", text: $newRepository)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .frame(minWidth: 220)
                TextField("Name in the library (optional)", text: $newName)
                    .textFieldStyle(.roundedBorder)
                TextField("Branch (optional)", text: $newBranch)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 130)
                Button("Add") {
                    addError = LibraryDownloader.shared.addCustomSource(repository: newRepository, name: newName, branch: newBranch)
                    if addError == nil {
                        newRepository = ""
                        newName = ""
                        newBranch = ""
                    }
                }
                .disabled(newRepository.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let addError {
                Text(addError)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }
}
