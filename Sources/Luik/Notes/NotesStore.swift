import Foundation
import Observation
import SwiftUI

struct Note: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var body: String
    var updatedAt = Date()
}

/// Notes are stored in notes.json in the engagement's folder.
@Observable
final class NotesStore {
    static let shared = NotesStore()

    private static let fileName = "notes.json"

    var notes: [Note] = []
    var selectedID: UUID? = nil
    @ObservationIgnored private var saver = Debouncer()

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
                          This is your notepad for this engagement. Everything is saved automatically.

                          Tips:
                          - Create a new note per topic or per day (+ button top left).
                          - Notes about a specific host or port are better kept in the Targets tab,
                            where they are attached to the right node.
                          - Each engagement has its own notes, targets, findings and log; switch
                            engagements in the top bar. The files live as JSON in
                            ~/Library/Application Support/Luik/Engagements/
                          """)]
        }
        selectedID = notes.first?.id
    }

    func add() {
        let note = Note(title: "New note", body: "")
        notes.insert(note, at: 0)
        selectedID = note.id
        scheduleSave()
    }

    func delete(_ id: UUID) {
        notes.removeAll { $0.id == id }
        if selectedID == id {
            selectedID = notes.first?.id
        }
        scheduleSave()
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
