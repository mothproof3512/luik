import SwiftUI

struct NotesView: View {
    @Environment(NotesStore.self) private var store

    var body: some View {
        @Bindable var store = store
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    Text("Notes")
                        .font(.headline)
                    Spacer()
                    Button {
                        store.add()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.plain)
                    .help("New note")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                List(selection: $store.selectedID) {
                    ForEach(store.notes) { note in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(note.title.isEmpty ? "Untitled" : note.title)
                                .lineLimit(1)
                            Text(note.updatedAt, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(note.id)
                        .contextMenu {
                            Button("Delete", role: .destructive) {
                                store.delete(note.id)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
            .frame(minWidth: 180, idealWidth: 230, maxWidth: 340)

            if let id = store.selectedID, store.contains(id) {
                NoteEditor(note: store.binding(for: id), onDelete: { store.delete(id) })
                    .id(id)
            } else {
                VStack {
                    Spacer()
                    Text("Select a note or create one with +")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

struct NoteEditor: View {
    @Binding var note: Note
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Title", text: $note.title)
                    .textFieldStyle(.plain)
                    .font(.title2.weight(.semibold))
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Delete this note")
            }
            TextEditor(text: $note.body)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
