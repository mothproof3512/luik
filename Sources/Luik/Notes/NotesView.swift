import AppKit
import SwiftUI

/// Notes of the engagement (Markdown, editable) plus the library: cheat sheets and downloaded
/// documentation shared by all engagements, in an outline per collection.
struct NotesView: View {
    @Environment(NotesStore.self) private var store
    @Environment(LibraryStore.self) private var library
    @Environment(UIState.self) private var ui
    @Environment(\.luikTheme) private var theme
    @State private var removingCollection: LibraryCollection?
    @State private var importStatus: String?

    var body: some View {
        @Bindable var ui = ui
        SplitPane(storageKey: "notesSplitFraction", defaultFraction: 0.28, minFraction: 0.16, maxFraction: 0.5) {
            sidebar
        } trailing: {
            detail
        }
        .onAppear { library.scanIfNeeded() }
        .sheet(isPresented: $ui.showLibrarySources) {
            LibrarySourcesView()
        }
        .confirmationDialog("Remove “\(removingCollection?.name ?? "")” from the library?",
                            isPresented: Binding(get: { removingCollection != nil }, set: { if !$0 { removingCollection = nil } })) {
            Button("Remove", role: .destructive) {
                if let collection = removingCollection {
                    if case .document(let id) = store.selection, id.hasPrefix(collection.id + "/") {
                        store.selection = nil
                    }
                    library.removeCollection(collection.id)
                }
                removingCollection = nil
            }
        } message: {
            Text("The files are moved to the Bin. A downloaded collection can be downloaded again; an imported one can be imported again from its original folder.")
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        @Bindable var store = store
        return VStack(spacing: 0) {
            HStack(spacing: 6) {
                TextField("Filter notes and library…", text: $store.search)
                    .textFieldStyle(.roundedBorder)
                Button {
                    store.add()
                } label: {
                    Image(systemName: "plus")
                }
                .help("New note (Markdown)")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            List(selection: $store.selection) {
                Section {
                    let notes = store.filteredNotes
                    if notes.isEmpty {
                        Text(store.search.isEmpty ? "No notes yet — press +." : "No notes match.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(notes) { note in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(note.title.isEmpty ? "Untitled" : note.title)
                                .lineLimit(1)
                            Text(note.updatedAt, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(NotesSelection.note(note.id))
                        .contextMenu {
                            Button("Delete", role: .destructive) {
                                store.delete(note.id)
                            }
                        }
                    }
                } header: {
                    Text("Notes — \(EngagementStore.shared.current.displayName)")
                }

                Section {
                    if !store.search.isEmpty {
                        let hits = library.search(store.search, limit: 60)
                        if hits.isEmpty {
                            Text(library.isEmpty ? "The library is empty." : "No documents match.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(hits) { document in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(document.title)
                                    .lineLimit(1)
                                Text(document.breadcrumb)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .tag(NotesSelection.document(document.id))
                        }
                    } else if library.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(library.isScanning ? "Reading the library…" : "Cheat sheets and documentation, shared by all engagements.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if !library.isScanning {
                                Button("Import folder…") { importFolder() }
                                    .font(.caption)
                                Button("Download documentation…") { ui.showLibrarySources = true }
                                    .font(.caption)
                            }
                        }
                    } else {
                        ForEach(library.collections) { collection in
                            DisclosureGroup {
                                OutlineGroup(collection.tree, id: \.id, children: \.children) { node in
                                    if let document = node.document {
                                        Text(node.title)
                                            .lineLimit(1)
                                            .tag(NotesSelection.document(document.id))
                                            .help(document.id)
                                    } else {
                                        Label(node.title, systemImage: "folder")
                                            .lineLimit(1)
                                    }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: collection.source == nil ? "doc.text" : "books.vertical")
                                        .foregroundStyle(theme.accentColor)
                                    Text(collection.name)
                                        .font(.callout.weight(.semibold))
                                        .lineLimit(1)
                                    Text("\(collection.documents.count)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    if let source = collection.source, LibraryDownloader.shared.hasUpdate(LibrarySource(id: source.sourceID, name: collection.name, repository: source.repository, summary: "")) {
                                        Text("update")
                                            .font(.caption2)
                                            .padding(.horizontal, 4)
                                            .background(Color.orange.opacity(0.3), in: Capsule())
                                    }
                                }
                                .contextMenu {
                                    Button("Show in Finder") { library.revealInFinder(collection) }
                                    if collection.source != nil {
                                        Button("Download documentation…") { ui.showLibrarySources = true }
                                    }
                                    Divider()
                                    Button("Remove from library…", role: .destructive) { removingCollection = collection }
                                }
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("Library")
                        Spacer()
                        Menu {
                            Button("Import folder or files…") { importFolder() }
                            Button("Download documentation…") { ui.showLibrarySources = true }
                            Divider()
                            Button("Show library folder in Finder") { library.revealInFinder() }
                            Button("Rescan") { library.rescan() }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .help("Import cheat sheets, download documentation, open the folder")
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            if let importStatus {
                Text(importStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }
            if let error = library.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
            }
        }
    }

    private func importFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.message = "Choose a folder of Markdown cheat sheets (subfolders are kept), or individual .md files"
        panel.prompt = "Import"
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        importStatus = library.importItems(panel.urls)
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { importStatus = nil }
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        switch store.selection {
        case .note(let id) where store.contains(id):
            NoteEditor(note: store.binding(for: id), onDelete: { store.delete(id) })
                .id(id)
        case .document(let path):
            if let document = library.document(id: path) {
                LibraryDocumentView(document: document)
                    .id(document.id)
            } else {
                placeholder("That document is no longer in the library.")
            }
        default:
            placeholder(library.isEmpty
                        ? "Select a note or create one with +.\nCheat sheets and documentation go into the Library (⋯ in the sidebar)."
                        : "Select a note or a library document.")
        }
    }

    private func placeholder(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Edit / Read switch shared by notes and library documents.
enum NoteMode: String {
    case edit
    case read
}

struct NoteModePicker: View {
    @Binding var mode: NoteMode

    var body: some View {
        Picker("", selection: $mode) {
            Label("Edit", systemImage: "pencil").tag(NoteMode.edit)
            Label("Read", systemImage: "doc.richtext").tag(NoteMode.read)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 150)
        .help("Edit the Markdown, or read it rendered (code blocks get a copy button)")
    }
}

struct NoteEditor: View {
    @Binding var note: Note
    let onDelete: () -> Void
    @AppStorage("notesDefaultMode") private var defaultMode = NoteMode.edit.rawValue
    @State private var mode: NoteMode = .edit

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                TextField("Title", text: $note.title)
                    .textFieldStyle(.plain)
                    .font(.title2.weight(.semibold))
                NoteModePicker(mode: $mode)
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Delete this note")
            }
            if mode == .edit {
                TextEditor(text: $note.body)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
            } else {
                MarkdownView(text: note.body)
                    .background(Color.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { mode = NoteMode(rawValue: defaultMode) ?? .edit }
        .onChange(of: mode) { _, newValue in defaultMode = newValue.rawValue }
    }
}

/// A library document: read by default, editable in place (saved to the .md file).
struct LibraryDocumentView: View {
    let document: LibraryDocument
    @Environment(LibraryStore.self) private var library
    @Environment(NotesStore.self) private var notes
    @State private var mode: NoteMode = .read
    @State private var text: String = ""
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(document.title)
                        .font(.title2.weight(.semibold))
                        .lineLimit(1)
                    Text(document.breadcrumb)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                NoteModePicker(mode: $mode)
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([document.url])
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Show the file in Finder")
            }
            if mode == .edit {
                TextEditor(text: $text)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
                    .onChange(of: text) { _, newValue in
                        if loaded { library.update(document, text: newValue) }
                    }
            } else {
                MarkdownView(text: text, onLink: { url in
                    openLink(url)
                })
                .background(Color.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            text = library.text(of: document)
            // The first change is this load, not an edit.
            DispatchQueue.main.async { loaded = true }
        }
    }

    /// Relative links point at other pages of the same collection; anchors stay on the page.
    private func openLink(_ url: URL) -> OpenURLAction.Result {
        let raw = url.absoluteString
        if raw.hasPrefix("#") { return .handled }
        let path = url.scheme == nil ? raw : url.path
        if let target = library.document(linked: path, from: document) {
            notes.open(target)
            return .handled
        }
        return .discarded
    }
}
