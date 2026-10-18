import Foundation
import Observation
import SwiftUI

/// A saved connection: a name and the command that opens it (ssh, a jump host, a VPN box, …).
struct Connection: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var command: String
}

/// Bookmarked connections for the terminal, stored in connections.json.
@Observable
final class ConnectionStore {
    static let shared = ConnectionStore()

    private static let fileName = "connections.json"

    var connections: [Connection] = []

    init() {
        connections = Storage.load([Connection].self, from: ConnectionStore.fileName) ?? []
    }

    func upsert(_ connection: Connection) {
        if let index = connections.firstIndex(where: { $0.id == connection.id }) {
            connections[index] = connection
        } else {
            connections.append(connection)
        }
        save()
    }

    func delete(_ connection: Connection) {
        connections.removeAll { $0.id == connection.id }
        save()
    }

    /// Opens a new terminal tab and runs the connection's command in it.
    func open(_ connection: Connection, in terminals: TerminalStore) {
        let session = terminals.newSession()
        session.title = connection.name
        let command = SnippetStore.shared.resolve(connection.command)
        if var login = RemoteDetect.sshLogin(in: command) {
            login.connectionName = connection.name
            session.remote = login
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            let entryID = ActivityLog.shared.record(.command, command, source: "Connections → Terminal: \(connection.name)", via: session.remote?.shortName)
            session.send(command + "\n", entryID: entryID)
            if session.remote != nil, !UserDefaults.standard.bool(forKey: SettingsKey.remoteHintShown) {
                UserDefaults.standard.set(true, forKey: SettingsKey.remoteHintShown)
                UIState.shared.flash("Logged in? Right-click the tab › Prepare this VM puts Luik's shell integration on it.", seconds: 6)
            }
        }
    }

    private func save() {
        Storage.save(connections, to: ConnectionStore.fileName)
    }
}

/// Menu in the terminal tab bar: saved connections plus "Manage…".
struct ConnectionsMenu: View {
    @Environment(ConnectionStore.self) private var store
    @Environment(TerminalStore.self) private var terminals
    @State private var showManager = false

    var body: some View {
        Menu {
            if store.connections.isEmpty {
                Text("No saved connections yet")
            }
            ForEach(store.connections) { connection in
                Button {
                    store.open(connection, in: terminals)
                } label: {
                    Label(connection.name, systemImage: "network")
                }
            }
            Divider()
            Button("Manage connections…") { showManager = true }
        } label: {
            Label("Connect", systemImage: "point.3.connected.trianglepath.dotted")
        }
        .fixedSize()
        .help("Open a saved connection (ssh, jump host, …) in a new tab")
        .sheet(isPresented: $showManager) {
            ConnectionManager()
        }
    }
}

struct ConnectionManager: View {
    @Environment(ConnectionStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var editing: Connection? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Connections")
                    .font(.headline)
                Spacer()
                Button {
                    editing = Connection(name: "", command: "ssh user@$RHOST")
                } label: {
                    Label("New", systemImage: "plus")
                }
            }
            Text("Each connection is a command that runs in a new terminal tab. $RHOST, $LHOST and $LPORT from One-liners are filled in.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            List {
                ForEach(store.connections) { connection in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(connection.name)
                                .font(.callout.weight(.semibold))
                            Text(connection.command)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button { editing = connection } label: { Image(systemName: "pencil") }
                            .buttonStyle(.plain)
                        Button(role: .destructive) { store.delete(connection) } label: { Image(systemName: "trash") }
                            .buttonStyle(.plain)
                    }
                    .padding(.vertical, 2)
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 200)
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 520, height: 400)
        .sheet(item: $editing) { connection in
            ConnectionEditor(connection: connection) { saved in
                store.upsert(saved)
            }
        }
    }
}

struct ConnectionEditor: View {
    @State var connection: Connection
    let onSave: (Connection) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Connection")
                .font(.headline)
            TextField("Name (e.g. jump host, kali box)", text: $connection.name)
                .textFieldStyle(.roundedBorder)
            TextField("Command (e.g. ssh -J jump user@10.10.10.5)", text: $connection.command)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    var saved = connection
                    if saved.name.trimmingCharacters(in: .whitespaces).isEmpty {
                        saved.name = String(saved.command.prefix(30))
                    }
                    onSave(saved)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(connection.command.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 460)
    }
}
