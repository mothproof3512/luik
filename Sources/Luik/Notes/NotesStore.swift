import Foundation
import Observation
import SwiftUI

struct Note: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var body: String
    var updatedAt = Date()
}

/// What is open in the Notes tab: a note of this engagement, or a library document (path).
enum NotesSelection: Hashable {
    case note(UUID)
    case document(String)
}

/// Notes are stored in notes.json in the engagement's folder. The library (cheat sheets and
/// downloaded documentation, shared by all engagements) lives in LibraryStore.
@Observable
final class NotesStore {
    static let shared = NotesStore()

    private static let fileName = "notes.json"

    var notes: [Note] = []
    var selection: NotesSelection? = nil
    /// Filter for the sidebar (notes and library).
    var search: String = ""
    @ObservationIgnored private var saver = Debouncer()

    /// The selected note, when the selection is a note.
    var selectedID: UUID? {
        get {
            if case .note(let id) = selection { return id }
            return nil
        }
        set {
            selection = newValue.map { .note($0) }
        }
    }

    func open(_ document: LibraryDocument) {
        selection = .document(document.id)
    }

    init() {
        load()
    }

    /// Called when the engagement changes.
    func reload() {
        saver.flush()
        load()
    }

    private func load() {
        if let loaded = Storage.load([Note].self, at: EngagementStore.shared.fileURL(NotesStore.fileName)) {
            notes = loaded
        } else {
            notes = [Note(title: "Welcome",
                          body: """
                          # Welcome

                          This is your notepad for this engagement. Everything is saved automatically, and notes are **Markdown**: switch between *Edit* and *Read* with the control at the top right.

                          ## Tips

                          - Create a new note per topic or per day (+ button top left).
                          - Notes about a specific host or port are better kept in the **Targets** tab, where they are attached to the right node.
                          - Each engagement has its own notes, targets, findings and log; switch engagements in the top bar. The files live as JSON in `~/Library/Application Support/Luik/Engagements/`.
                          - **Library** (below the notes) holds what is the same for every engagement: your cheat sheets (⋯ › *Import folder…* copies a folder of `.md` files) and documentation such as PayloadsAllTheThings (⋯ › *Download documentation…*). In Read mode every code block has a copy button.

                          ```bash
                          # a code block, with a copy button in Read mode
                          nmap -sC -sV -oA scans/initial $RHOST
                          ```
                          """)]
        }
        selection = notes.first.map { .note($0.id) }
    }

    func add() {
        let note = Note(title: "New note", body: "")
        notes.insert(note, at: 0)
        selection = .note(note.id)
        scheduleSave()
    }

    func delete(_ id: UUID) {
        notes.removeAll { $0.id == id }
        if selectedID == id {
            selection = notes.first.map { .note($0.id) }
        }
        scheduleSave()
    }

    /// Notes matching the sidebar filter (title or text; all words must occur).
    var filteredNotes: [Note] {
        let words = search.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !words.isEmpty else { return notes }
        return notes.filter { note in
            let haystack = (note.title + "\n" + note.body).lowercased()
            return words.allSatisfy { haystack.contains($0) }
        }
    }

    func contains(_ id: UUID?) -> Bool {
        guard let id else { return false }
        return notes.contains { $0.id == id }
    }

    /// Binding to a single note; every change is saved (debounced).
    func binding(for id: UUID) -> Binding<Note> {
        Binding(
            get: { [weak self] in
                self?.notes.first { $0.id == id } ?? Note(title: "", body: "")
            },
            set: { [weak self] newValue in
                guard let self, let index = self.notes.firstIndex(where: { $0.id == id }) else { return }
                var updated = newValue
                updated.updatedAt = Date()
                self.notes[index] = updated
                self.scheduleSave()
            }
        )
    }

    func scheduleSave() {
        let url = EngagementStore.shared.fileURL(NotesStore.fileName)
        saver.call { [weak self] in
            guard let self else { return }
            Storage.save(self.notes, at: url)
        }
    }

    func flush() {
        saver.flush()
    }
}
