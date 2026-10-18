import AppKit
import SwiftUI
import UniformTypeIdentifiers

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
                                        if document.isImage {
                                            Label(node.title, systemImage: "photo")
                                                .lineLimit(1)
                                                .tag(NotesSelection.document(document.id))
                                                .help(document.id)
                                        } else {
                                            Text(node.title)
                                                .lineLimit(1)
                                                .tag(NotesSelection.document(document.id))
                                                .help(document.id)
                                        }
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
                            Button("Import images…") { importImages() }
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
        panel.message = "Choose a folder of Markdown cheat sheets and images (subfolders are kept), or individual .md / image files"
        panel.prompt = "Import"
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        importStatus = library.importItems(panel.urls)
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { importStatus = nil }
    }

    /// Pictures (HLDs, network diagrams, architecture drawings) go into the Images collection.
    private func importImages() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.png, .jpeg, .gif, .tiff, .heic, .webP, .svg, .bmp]
        panel.message = "Choose images for the library (they go into the Images collection)"
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
                if document.isImage {
                    LibraryImageView(document: document)
                        .id(document.id)
                } else {
                    LibraryDocumentView(document: document)
                        .id(document.id)
                }
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
    @Environment(LibraryStore.self) private var library
    @Environment(UIState.self) private var ui
    @AppStorage("notesDefaultMode") private var defaultMode = NoteMode.edit.rawValue
    @State private var mode: NoteMode = .edit
    @State private var showFind = false
    @State private var savedTo: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                TextField("Title", text: $note.title)
                    .textFieldStyle(.plain)
                    .font(.title2.weight(.semibold))
                if let savedTo {
                    Text("Saved to Library › \(savedTo)")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                NoteModePicker(mode: $mode)
                if mode == .read {
                    FindToggle(isOn: $showFind, active: ui.module == .notes)
                }
                Menu {
                    ForEach(library.writableCollectionNames, id: \.self) { collection in
                        Button(collection) { saveToLibrary(collection) }
                    }
                    Divider()
                    Text("Writes a copy as a Markdown file; the note stays here too.")
                } label: {
                    Image(systemName: "books.vertical")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Keep this note beyond the engagement: save a copy into the library (Personal, or one of your own collections)")
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
                MarkdownView(text: note.body, showFind: $showFind)
                    .background(Color.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { mode = NoteMode(rawValue: defaultMode) ?? .edit }
        .onChange(of: mode) { _, newValue in defaultMode = newValue.rawValue }
    }

    private func saveToLibrary(_ collection: String) {
        guard library.saveNote(title: note.title, text: note.body, collection: collection) != nil else { return }
        savedTo = collection
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { savedTo = nil }
    }
}

/// ⌘F in Read mode: shows the find bar of the rendered Markdown (only while this tab is open,
/// because every tab stays mounted).
struct FindToggle: View {
    @Binding var isOn: Bool
    let active: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(active ? KeyboardShortcut("f", modifiers: .command) : nil)
        .help("Find in this page (⌘F)")
    }
}

/// A library document: read by default, editable in place (saved to the .md file).
struct LibraryDocumentView: View {
    let document: LibraryDocument
    @Environment(LibraryStore.self) private var library
    @Environment(NotesStore.self) private var notes
    @Environment(UIState.self) private var ui
    @State private var mode: NoteMode = .read
    @State private var text: String = ""
    @State private var loaded = false
    @State private var showFind = false

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
                if mode == .read {
                    FindToggle(isOn: $showFind, active: ui.module == .notes)
                }
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([document.url])
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Show the file in Finder")
            }
            RelatedToDocumentBar(document: document)
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
                }, showFind: $showFind, baseURL: document.url.deletingLastPathComponent())
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


/// A picture in the library (HLD, network diagram, …): fitted to the pane, zoom with the
/// slider or ⌘+/⌘−, double-click opens it in Preview.
struct LibraryImageView: View {
    let document: LibraryDocument
    @Environment(LibraryStore.self) private var library
    @State private var image: NSImage?
    @State private var zoom: CGFloat = 0   // 0 = fit

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(document.title)
                        .font(.title2.weight(.semibold))
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(document.breadcrumb)
                        if let image {
                            Text("· \(Int(image.size.width)) × \(Int(image.size.height))")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                }
                Spacer()
                Picker("", selection: $zoom) {
                    Text("Fit").tag(CGFloat(0))
                    Text("50%").tag(CGFloat(0.5))
                    Text("100%").tag(CGFloat(1))
                    Text("200%").tag(CGFloat(2))
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 220)
                Button {
                    guard let image else { return }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.writeObjects([image])
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Copy the image")
                Button {
                    NSWorkspace.shared.open(document.url)
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Open in Preview")
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([document.url])
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Show the file in Finder")
            }
            GeometryReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    if let image {
                        let size = displaySize(image, in: proxy.size)
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: size.width, height: size.height)
                            .frame(minWidth: proxy.size.width, minHeight: proxy.size.height)
                            .onTapGesture(count: 2) { NSWorkspace.shared.open(document.url) }
                    } else {
                        Text("Could not open \(document.fileName)")
                            .foregroundStyle(.secondary)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                    }
                }
            }
            .background(Color.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: document.id) {
            let url = document.url
            image = await Task.detached(priority: .userInitiated) { NSImage(contentsOf: url) }.value
        }
    }

    private func displaySize(_ image: NSImage, in available: CGSize) -> CGSize {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return available }
        if zoom > 0 { return CGSize(width: size.width * zoom, height: size.height * zoom) }
        let scale = min((available.width - 16) / size.width, (available.height - 16) / size.height, 1)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
}


/// On a library page: the one-liners and checklist items that point here, so the page, the
/// commands and the work items are one thing.
struct RelatedToDocumentBar: View {
    let document: LibraryDocument
    @Environment(SnippetStore.self) private var snippets
    @Environment(TerminalStore.self) private var terminals
    @Environment(UIState.self) private var ui
    @State private var copiedID: UUID?

    var body: some View {
        let related = LibraryLink.snippets(for: document)
        let items = ChecklistStore.shared.items(linkedTo: document)
        if !related.isEmpty || !items.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                if !related.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Label("One-liners", systemImage: "terminal")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(related) { snippet in
                                    HStack(spacing: 3) {
                                        Text(snippet.title)
                                            .font(.caption)
                                            .lineLimit(1)
                                        Button {
                                            snippets.copyToClipboard(snippet)
                                            copiedID = snippet.id
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { if copiedID == snippet.id { copiedID = nil } }
                                        } label: {
                                            Image(systemName: copiedID == snippet.id ? "checkmark" : "doc.on.doc")
                                                .font(.caption2)
                                        }
                                        .buttonStyle(.plain)
                                        .help(snippets.resolve(snippet.command))
                                        Button {
                                            terminals.sendToSelected(snippets.resolve(snippet.command), source: "Library")
                                            UsageStore.shared.recordSnippet(snippet.id, service: "")
                                            ui.open(.terminal)
                                            terminals.focusSelected(afterDelay: true)
                                        } label: {
                                            Image(systemName: "terminal")
                                                .font(.caption2)
                                        }
                                        .buttonStyle(.plain)
                                        .help("Paste into the active terminal")
                                    }
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.white.opacity(0.08), in: Capsule())
                                }
                            }
                        }
                    }
                }
                if !items.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Label("Checklist items", systemImage: "checklist")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(items.map { "\($0.item.title) (\($0.list.name))" }.joined(separator: " · "))
                            .font(.caption)
                            .lineLimit(2)
                    }
                }
            }
            .padding(8)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
