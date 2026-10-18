import AppKit
import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// A standard playbook: not new content, but a bundle of what Luik already has, chosen for one
/// kind of engagement — the plan template, the checklists and one-liners of the services that
/// matter, a diagram template and the library topics to read. "Use" sets the engagement up with
/// it; "Export" writes that subset as a .luikplaybook.json to share.
struct StandardPlaybook: Identifiable {
    let id: String
    let name: String
    let summary: String
    let planTemplate: String
    let diagramTemplate: String?
    /// nmap service names / port numbers; selects checklists and one-liners.
    let services: [String]
    /// One-liner categories taken as a whole (besides the services).
    let categories: [String]
    let libraryTopics: [String]

    static let all: [StandardPlaybook] = [
        StandardPlaybook(id: "external", name: "External network", summary: "Internet-facing infrastructure: DNS and mail, web servers, remote access, exposed services.",
                         planTemplate: "External network penetration test", diagramTemplate: "net-dmz",
                         services: ["dns", "smtp", "http", "https", "ssh", "ftp", "vpn", "rdp", "telnet", "snmp"],
                         categories: ["Recon", "Reconnaissance", "Web", "Scanning"],
                         libraryTopics: ["DNS", "SMTP", "Web", "SSH", "FTP"]),
        StandardPlaybook(id: "internal", name: "Internal network and AD", summary: "From the LAN to the domain: SMB, LDAP, Kerberos, WinRM, MSSQL, RDP, file services.",
                         planTemplate: "Internal network and Active Directory", diagramTemplate: "net-segmented",
                         services: ["microsoft-ds", "smb", "netbios-ssn", "ldap", "ldaps", "kerberos-sec", "kerberos", "msrpc", "winrm", "ms-sql-s", "mssql", "ms-wbt-server", "rdp", "nfs", "rpcbind"],
                         categories: ["Active Directory", "AD", "Windows", "SMB", "Credentials", "Lateral movement", "Privilege escalation"],
                         libraryTopics: ["Active Directory", "SMB", "LDAP", "Kerberos", "WinRM", "MSSQL"]),
        StandardPlaybook(id: "webapp", name: "Web application", summary: "One application end to end: discovery, authentication, authorisation, injection, logic.",
                         planTemplate: "Web application", diagramTemplate: "web-spa-api",
                         services: ["http", "https", "http-proxy", "http-alt", "ssl/http"],
                         categories: ["Web", "Web application", "Fuzzing"],
                         libraryTopics: ["SQL Injection", "Cross-Site Scripting", "Server Side Request Forgery", "File Inclusion", "Upload Insecure Files", "Insecure Direct Object References", "JSON Web Token", "OAuth"]),
        StandardPlaybook(id: "api", name: "API", summary: "REST / GraphQL APIs: tokens, object- and function-level authorisation, input handling.",
                         planTemplate: "API assessment", diagramTemplate: "auth-oauth-pkce",
                         services: ["http", "https", "http-alt", "8080", "8443", "3000", "5000"],
                         categories: ["Web", "API", "Fuzzing"],
                         libraryTopics: ["API Key Leaks", "GraphQL Injection", "JSON Web Token", "OAuth", "Insecure Direct Object References", "Mass Assignment"]),
        StandardPlaybook(id: "cloud", name: "Cloud configuration review", summary: "Azure / AWS / GCP: identity, exposure, storage, logging — a review with read access.",
                         planTemplate: "Cloud configuration review", diagramTemplate: "net-hybrid-cloud",
                         services: ["https", "ssh", "rdp", "docker", "kubernetes"],
                         categories: ["Cloud", "Azure", "AWS", "GCP", "Kubernetes"],
                         libraryTopics: ["Cloud", "Azure", "AWS", "GCP", "Kubernetes", "Docker"]),
        StandardPlaybook(id: "wireless", name: "Wireless", summary: "Wi-Fi of a site: encryption, 802.1X, guest isolation, what a connected device reaches.",
                         planTemplate: "Wireless assessment", diagramTemplate: "net-small-office",
                         services: ["radius", "1812", "http", "https", "ssh"],
                         categories: ["Wireless", "Wi-Fi", "Network"],
                         libraryTopics: ["Wireless", "Wi-Fi", "Network Discovery"]),
        StandardPlaybook(id: "mobile", name: "Mobile application", summary: "iOS / Android app and its backend: local storage, transport, tokens, platform interaction.",
                         planTemplate: "Mobile application assessment", diagramTemplate: "web-spa-api",
                         services: ["http", "https"],
                         categories: ["Mobile", "Android", "iOS", "Web"],
                         libraryTopics: ["Android", "iOS", "Mobile", "JSON Web Token", "OAuth"]),
        StandardPlaybook(id: "retest", name: "Retest", summary: "Verifying an earlier report: the Retest plan, the imported findings, the same evidence standard.",
                         planTemplate: "Retest", diagramTemplate: nil,
                         services: [],
                         categories: [],
                         libraryTopics: []),
    ]

    // MARK: - What it selects

    var planTemplateObject: PlanTemplate? {
        PlanStore.shared.templates.first { $0.name == planTemplate }
    }

    var diagramTemplateObject: DiagramTemplate? {
        guard let diagramTemplate else { return nil }
        return DiagramTemplate.all.first { $0.id == diagramTemplate }
    }

    var checklists: [Checklist] {
        let keys = Set(services.map { $0.lowercased() })
        return ChecklistStore.shared.lists.services.filter { list in list.keys.contains { keys.contains($0.lowercased()) } }
    }

    var snippets: [Snippet] {
        let keys = Set(services.map { $0.lowercased() })
        let cats = Set(categories.map { $0.lowercased() })
        return SnippetStore.shared.snippets.filter { snippet in
            cats.contains(snippet.category.lowercased()) || snippet.services.contains { keys.contains($0.lowercased()) }
        }
    }

    var libraryDocuments: [LibraryDocument] {
        var seen = Set<String>()
        var result: [LibraryDocument] = []
        for topic in libraryTopics {
            if let document = LibraryLink.resolve(topic), !seen.contains(document.id) {
                seen.insert(document.id)
                result.append(document)
            }
        }
        return result
    }

    /// The bundle as a playbook file (checklists as a set with the generic lists included).
    func asPlaybook() -> Playbook {
        var playbook = Playbook(name: "Luik — \(name)")
        playbook.snippets = snippets
        let lists = ChecklistStore.shared.lists
        playbook.checklists = ChecklistSet(host: lists.host, port: lists.port, services: checklists)
        if let template = planTemplateObject {
            var copy = template
            copy.builtIn = false
            playbook.planTemplates = [copy]
        }
        return playbook
    }

    /// Sets the engagement up: a plan from the template (unless one from it exists), the diagram
    /// template as a new diagram (optional). Returns a summary.
    @discardableResult
    func apply(createDiagram: Bool) -> String {
        var parts: [String] = []
        let plans = PlanStore.shared
        if let template = planTemplateObject {
            if plans.plans.contains(where: { $0.templateName == template.name }) {
                parts.append("plan already present")
            } else {
                _ = plans.createPlan(from: template, name: "\(template.name) — \(EngagementStore.shared.current.displayName)")
                parts.append("plan created")
            }
        }
        if createDiagram, let template = diagramTemplateObject {
            if DiagramStore.shared.diagrams.contains(where: { $0.name.hasPrefix(template.name) }) {
                parts.append("diagram already present")
            } else {
                DiagramStore.shared.newDiagram(from: template)
                parts.append("diagram added")
            }
        }
        ActivityLog.shared.record(.action, "Playbook “\(name)” applied: \(parts.joined(separator: ", "))", source: "Playbooks")
        return parts.isEmpty ? "Nothing to set up." : parts.joined(separator: ", ").capitalizedFirst
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

/// Your own playbook files, kept in <data folder>/Playbooks/.
@Observable
final class PlaybookLibrary {
    static let shared = PlaybookLibrary()

    struct Entry: Identifiable, Hashable {
        let url: URL
        let playbook: Playbook

        var id: String { url.path }
        static func == (a: Entry, b: Entry) -> Bool { a.url == b.url }
        func hash(into hasher: inout Hasher) { hasher.combine(url) }
    }

    var entries: [Entry] = []

    static var folder: URL {
        let url = Storage.url(for: "Playbooks")
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    func rescan() {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: PlaybookLibrary.folder, includingPropertiesForKeys: nil) else { entries = []; return }
        entries = items
            .filter { $0.pathExtension.lowercased() == "json" }
            .compactMap { url in (try? PlaybookTransfer.read(url)).map { Entry(url: url, playbook: $0) } }
            .sorted { $0.playbook.exportedAt > $1.playbook.exportedAt }
    }

    /// Writes a playbook into the folder. Returns the file.
    @discardableResult
    func save(_ playbook: Playbook) -> URL? {
        guard let data = try? JSONEncoder.iso.encode(playbook) else { return nil }
        let slug = playbook.name.map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined().trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        var url = PlaybookLibrary.folder.appendingPathComponent((slug.isEmpty ? "playbook" : slug) + ".luikplaybook.json")
        var counter = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = PlaybookLibrary.folder.appendingPathComponent("\(slug)-\(counter).luikplaybook.json")
            counter += 1
        }
        do {
            try data.write(to: url, options: .atomic)
            rescan()
            return url
        } catch {
            return nil
        }
    }

    func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = true
        panel.message = "Choose .luikplaybook.json files to add to your playbooks"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let playbook = try? PlaybookTransfer.read(url) else { continue }
            save(playbook)
        }
    }

    func remove(_ entry: Entry) {
        try? FileManager.default.trashItem(at: entry.url, resultingItemURL: nil)
        rescan()
    }
}

/// Tools › Playbooks: the standard bundles and your own playbook files.
struct PlaybooksView: View {
    @Environment(UIState.self) private var ui
    @Environment(PlanStore.self) private var plans
    @Environment(SnippetStore.self) private var snippets
    @Environment(LibraryStore.self) private var library
    @State private var selection: String? = StandardPlaybook.all.first?.id
    @State private var createDiagram = true
    @State private var status: String?
    @State private var showExport = false

    private var selectedStandard: StandardPlaybook? { StandardPlaybook.all.first { $0.id == selection } }
    private var selectedOwn: PlaybookLibrary.Entry? { PlaybookLibrary.shared.entries.first { $0.id == selection } }

    var body: some View {
        SplitPane(storageKey: "playbooksSplitFraction", defaultFraction: 0.3, minFraction: 0.2, maxFraction: 0.5) {
            sidebar
        } trailing: {
            if let standard = selectedStandard {
                standardDetail(standard)
            } else if let own = selectedOwn {
                ownDetail(own)
            } else {
                VStack {
                    Spacer()
                    Text("Pick a playbook.")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            PlaybookLibrary.shared.rescan()
            library.scanIfNeeded()
        }
        .sheet(isPresented: $showExport) {
            PlaybookView(mode: .export)
        }
    }

    private var sidebar: some View {
        let own = PlaybookLibrary.shared.entries
        return List(selection: $selection) {
            Section("Standard playbooks") {
                ForEach(StandardPlaybook.all) { playbook in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(playbook.name)
                        Text(playbook.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .tag(playbook.id)
                }
            }
            Section {
                if own.isEmpty {
                    Text("Your exported or imported playbook files appear here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(own) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.playbook.name)
                        Text(entry.playbook.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .tag(entry.id)
                    .contextMenu {
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) }
                        Button("Remove (to Trash)", role: .destructive) { PlaybookLibrary.shared.remove(entry) }
                    }
                }
            } header: {
                HStack {
                    Text("Your playbooks")
                    Spacer()
                    Menu {
                        Button("Save what you know as a playbook…") { showExport = true }
                        Button("Add playbook file(s)…") { PlaybookLibrary.shared.importFile() }
                        Divider()
                        Button("Show folder in Finder") { NSWorkspace.shared.activateFileViewerSelecting([PlaybookLibrary.folder]) }
                        Button("Rescan") { PlaybookLibrary.shared.rescan() }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }

    private func standardDetail(_ playbook: StandardPlaybook) -> some View {
        let checklists = playbook.checklists
        let oneLiners = playbook.snippets
        let documents = playbook.libraryDocuments
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(playbook.name)
                        .font(.title2.weight(.semibold))
                    Text(playbook.summary)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 10) {
                    Button {
                        status = playbook.apply(createDiagram: createDiagram)
                        ui.flash(status ?? "")
                    } label: {
                        Label("Use for this engagement", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .help("Creates the plan from the template (and the diagram from the template) in the current engagement")
                    Toggle("with diagram", isOn: $createDiagram)
                        .toggleStyle(.checkbox)
                        .disabled(playbook.diagramTemplateObject == nil)
                    Button {
                        if let url = PlaybookLibrary.shared.save(playbook.asPlaybook()) {
                            ui.flash("Saved as \(url.lastPathComponent) — in Your playbooks.")
                        }
                    } label: {
                        Label("Save as playbook file", systemImage: "shippingbox")
                    }
                    .help("Writes this bundle (one-liners, checklists, plan template) as a .luikplaybook.json into Your playbooks, to share or edit")
                    if let status {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                section("Plan template", icon: "list.bullet.clipboard") {
                    if let template = playbook.planTemplateObject {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(template.name).font(.callout.weight(.semibold))
                                Text("\(template.phases.count) phases · \(template.phases.reduce(0) { $0 + $1.items.count }) items · \(template.fields.count) fields")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Open Plan tab") { ui.open(.plan) }
                                .controlSize(.small)
                        }
                    } else {
                        Text("Template “\(playbook.planTemplate)” not found.").font(.caption).foregroundStyle(.orange)
                    }
                }
                if let template = playbook.diagramTemplateObject {
                    section("Diagram template", icon: "point.3.connected.trianglepath.dotted") {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(template.name).font(.callout.weight(.semibold))
                                Text(template.summary).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Open as new diagram") {
                                DiagramStore.shared.newDiagram(from: template)
                                ui.open(.diagram)
                            }
                            .controlSize(.small)
                        }
                    }
                }
                section("Checklists (\(checklists.count))", icon: "checklist") {
                    if checklists.isEmpty {
                        Text(playbook.services.isEmpty ? "No service checklists for this playbook." : "No checklist matches these services yet — add them in the checklist editor.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(checklists) { list in
                        HStack {
                            Text(list.name)
                            Text("\(list.items.count) items · \(list.keys.joined(separator: ", "))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer()
                        }
                    }
                }
                section("One-liners (\(oneLiners.count))", icon: "terminal") {
                    if oneLiners.isEmpty {
                        Text("No one-liners tagged with these services or categories yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(oneLiners.prefix(40)) { snippet in
                        HStack(spacing: 8) {
                            Text(snippet.title)
                                .lineLimit(1)
                            Text(snippet.category)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.white.opacity(0.1), in: Capsule())
                            Spacer()
                            Text(snippets.resolve(snippet.command))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: 320, alignment: .trailing)
                        }
                    }
                    if oneLiners.count > 40 {
                        Text("… and \(oneLiners.count - 40) more in the One-liners tab").font(.caption).foregroundStyle(.secondary)
                    }
                }
                section("Library pages (\(documents.count) of \(playbook.libraryTopics.count) topics found)", icon: "books.vertical") {
                    if documents.isEmpty {
                        Text(library.isEmpty ? "Download the documentation first (Notes › Library › ⋯)." : "None of the topics match a page in your library.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(documents) { document in
                        LibraryLinkButton(document: document)
                    }
                    if !playbook.libraryTopics.isEmpty {
                        Text("Topics: " + playbook.libraryTopics.joined(separator: " · "))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func ownDetail(_ entry: PlaybookLibrary.Entry) -> some View {
        let playbook = entry.playbook
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(playbook.name)
                        .font(.title2.weight(.semibold))
                    Text("Exported \(playbook.exportedAt.formatted(date: .abbreviated, time: .shortened)) with Luik \(playbook.luikVersion) · \(playbook.summary)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(entry.url.lastPathComponent)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                HStack(spacing: 10) {
                    Button {
                        let result = PlaybookTransfer.apply(playbook, options: PlaybookTransfer.Options())
                        status = result
                        ui.flash(result)
                    } label: {
                        Label("Merge into Luik", systemImage: "arrow.down.doc")
                    }
                    .buttonStyle(.borderedProminent)
                    .help("One-liners and knowledge records added, same-named checklists replaced, plan templates added")
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) }
                    if let status {
                        Text(status).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let snippets = playbook.snippets {
                    section("One-liners (\(snippets.count))", icon: "terminal") {
                        ForEach(snippets.prefix(60)) { snippet in
                            HStack {
                                Text(snippet.title).lineLimit(1)
                                Text(snippet.category).font(.caption2).foregroundStyle(.secondary)
                                Spacer()
                            }
                        }
                    }
                }
                if let checklists = playbook.checklists {
                    section("Checklists (\(checklists.services.count + 2))", icon: "checklist") {
                        ForEach(checklists.services) { list in
                            Text("\(list.name) · \(list.items.count) items")
                        }
                    }
                }
                if let templates = playbook.planTemplates, !templates.isEmpty {
                    section("Plan templates (\(templates.count))", icon: "list.bullet.clipboard") {
                        ForEach(templates) { template in Text(template.name) }
                    }
                }
                if let knowledge = playbook.knowledge, !knowledge.records.isEmpty {
                    section("Knowledge records (\(knowledge.records.count))", icon: "tablecells") {
                        ForEach(knowledge.records.prefix(30)) { record in Text(record.value("Title")) }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func section<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }
}
