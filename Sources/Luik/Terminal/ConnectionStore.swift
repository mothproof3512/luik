import Foundation
import Observation
import SwiftUI

/// A saved connection: a name and either the command that opens it in a terminal tab (ssh, a
/// jump host, a VPN box, …) or an RDP target that opens in Windows App / Microsoft Remote Desktop.
struct Connection: Identifiable, Codable, Equatable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case command, rdp
        var id: String { rawValue }
        var label: String { self == .command ? "Command (ssh, …)" : "RDP (Windows App)" }
    }

    var id = UUID()
    var name: String
    var command: String
    var kind: Kind = .command
    /// RDP: host[:port] and user name (DOMAIN\\user or user@domain) — $RHOST is filled in.
    var host = ""
    var username = ""

    init(id: UUID = UUID(), name: String, command: String, kind: Kind = .command, host: String = "", username: String = "") {
        self.id = id
        self.name = name
        self.command = command
        self.kind = kind
        self.host = host
        self.username = username
    }

    enum CodingKeys: String, CodingKey { case id, name, command, kind, host, username }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        command = try container.decodeIfPresent(String.self, forKey: .command) ?? ""
        kind = try container.decodeIfPresent(Kind.self, forKey: .kind) ?? .command
        host = try container.decodeIfPresent(String.self, forKey: .host) ?? ""
        username = try container.decodeIfPresent(String.self, forKey: .username) ?? ""
    }

    /// What the list shows under the name.
    var summary: String {
        kind == .rdp ? "rdp://\(host)\(username.isEmpty ? "" : " as \(username)")" : command
    }

    /// The `rdp://` link Windows App (and Microsoft Remote Desktop) open: full address, user, full screen.
    var rdpURL: URL? {
        let resolvedHost = SnippetStore.shared.resolve(host).trimmingCharacters(in: .whitespaces)
        guard !resolvedHost.isEmpty else { return nil }
        var query = "full%20address=s:\(resolvedHost.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? resolvedHost)"
        let user = SnippetStore.shared.resolve(username).trimmingCharacters(in: .whitespaces)
        if !user.isEmpty { query += "&username=s:\(user.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? user)" }
        query += "&screen%20mode%20id=i:2"
        return URL(string: "rdp://\(query)")
    }

    /// An .rdp file for clients that do not take the URL scheme.
    var rdpFileContents: String {
        let resolvedHost = SnippetStore.shared.resolve(host).trimmingCharacters(in: .whitespaces)
        let user = SnippetStore.shared.resolve(username).trimmingCharacters(in: .whitespaces)
        var lines = ["full address:s:\(resolvedHost)", "screen mode id:i:2", "prompt for credentials:i:1", "authentication level:i:0"]
        if !user.isEmpty { lines.append("username:s:\(user)") }
        return lines.joined(separator: "\n") + "\n"
    }
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

    /// Opens the connection: a terminal tab with its command, or the RDP client for an RDP target.
    func open(_ connection: Connection, in terminals: TerminalStore) {
        if connection.kind == .rdp { openRDP(connection); return }
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

    /// Hands the target to Windows App / Microsoft Remote Desktop (rdp:// link; an .rdp file as
    /// fallback) and records the session in the Log, because nothing inside RDP is visible to Luik.
    func openRDP(_ connection: Connection) {
        let host = SnippetStore.shared.resolve(connection.host).trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else { UIState.shared.flash("The RDP connection has no host.", seconds: 3); return }
        let address = host.split(separator: ":").first.map(String.init) ?? host
        let user = SnippetStore.shared.resolve(connection.username).trimmingCharacters(in: .whitespaces)
        ActivityLog.shared.record(.action, "RDP session to \(host)\(user.isEmpty ? "" : " as \(user)") opened in the RDP client — not visible to Luik; add Log notes or screenshots (⌘⇧E)", source: "Connections: \(connection.name)", host: address)
        TerminalStore.warnIfOutOfScope(host)
        var opened = false
        if let url = connection.rdpURL {
            opened = NSWorkspace.shared.open(url)
        }
        if !opened {
            let folder = Storage.directory.appendingPathComponent("rdp", isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let safe = String(connection.name.map { $0.isLetter || $0.isNumber ? $0 : "-" })
            let file = folder.appendingPathComponent((safe.isEmpty ? "connection" : safe) + ".rdp")
            if (try? connection.rdpFileContents.write(to: file, atomically: true, encoding: .utf8)) != nil {
                opened = NSWorkspace.shared.open(file)
            }
        }
        if opened {
            UIState.shared.flash("RDP → \(host). Luik cannot see inside RDP: note what you do in the Log; ⌘⇧E for screenshots.", seconds: 5)
        } else {
            UIState.shared.flash("No RDP client found — install Windows App (Mac App Store) and try again.", seconds: 5)
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
                    Label(connection.name, systemImage: connection.kind == .rdp ? "display" : "network")
                }
            }
            Divider()
            Button("Manage connections…") { showManager = true }
        } label: {
            Label("Connect", systemImage: "point.3.connected.trianglepath.dotted")
        }
        .fixedSize()
        .help("Open a saved connection: ssh and other commands in a new tab, RDP in Windows App")
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
            Text("A command that runs in a new terminal tab (ssh, jump host, …) or an RDP target for Windows App. $RHOST, $LHOST and $LPORT are filled in.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            List {
                ForEach(store.connections) { connection in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(connection.name)
                                .font(.callout.weight(.semibold))
                            Text(connection.summary)
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
            Picker("", selection: $connection.kind) {
                ForEach(Connection.Kind.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            TextField("Name (e.g. jump host, kali box, DC01 console)", text: $connection.name)
                .textFieldStyle(.roundedBorder)
            if connection.kind == .rdp {
                TextField("Host or host:port (e.g. $RHOST, 10.10.10.5:3389)", text: $connection.host)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                TextField("User name (optional, e.g. CORP\\pascal or pascal@corp.local)", text: $connection.username)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                Text("Opens in Windows App (Microsoft Remote Desktop) through an rdp:// link; the password is asked there. Luik cannot see inside the session, so it logs only that it was opened — note what you do in the Log, ⌘⇧E for screenshots.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                TextField("Command (e.g. ssh -J jump user@10.10.10.5)", text: $connection.command)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    var saved = connection
                    if saved.name.trimmingCharacters(in: .whitespaces).isEmpty {
                        saved.name = saved.kind == .rdp ? "RDP \(saved.host)" : String(saved.command.prefix(30))
                    }
                    onSave(saved)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(connection.kind == .rdp ? connection.host.trimmingCharacters(in: .whitespaces).isEmpty : connection.command.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 460)
    }
}
