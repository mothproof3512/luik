import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// A playbook is what you know, packed to carry to another Mac or to share with a colleague:
/// one-liners, checklists, plan templates and your own knowledge-base records. One JSON file,
/// `<name>.luikplaybook.json`. Usage statistics and engagement data are never part of it.
struct Playbook: Codable {
    var luikPlaybook = 1
    var name: String
    var exportedAt = Date()
    var luikVersion = AppInfo.version
    var snippets: [Snippet]?
    var checklists: ChecklistSet?
    var planTemplates: [PlanTemplate]?
    var knowledge: KBTable?

    var summary: String {
        var parts: [String] = []
        if let snippets { parts.append("\(snippets.count) one-liner\(snippets.count == 1 ? "" : "s")") }
        if let checklists { parts.append("\(checklists.services.count + 2) checklists") }
        if let planTemplates { parts.append("\(planTemplates.count) plan template\(planTemplates.count == 1 ? "" : "s")") }
        if let knowledge { parts.append("\(knowledge.records.count) knowledge record\(knowledge.records.count == 1 ? "" : "s")") }
        return parts.isEmpty ? "nothing" : parts.joined(separator: ", ")
    }
}

enum PlaybookTransfer {
    struct Options {
        var snippets = true
        var checklists = true
        var planTemplates = true
        var knowledge = true
    }

    static func build(name: String, options: Options) -> Playbook {
        var playbook = Playbook(name: name)
        if options.snippets { playbook.snippets = SnippetStore.shared.snippets }
        if options.checklists { playbook.checklists = ChecklistStore.shared.lists }
        if options.planTemplates { playbook.planTemplates = PlanStore.shared.customTemplates.map { template in
            var copy = template
            copy.builtIn = false
            return copy
        } }
        if options.knowledge, !KnowledgeBaseStore.shared.mine.records.isEmpty { playbook.knowledge = KnowledgeBaseStore.shared.mine }
        return playbook
    }

    static func exportWithPanel(name: String, options: Options) -> String? {
        let playbook = build(name: name, options: options)
        guard let data = try? JSONEncoder.iso.encode(playbook) else { return "Could not encode the playbook." }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        let slug = name.map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined().trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        panel.nameFieldStringValue = (slug.isEmpty ? "playbook" : slug) + ".luikplaybook.json"
        panel.message = "Save the playbook (\(playbook.summary))"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            try data.write(to: url, options: .atomic)
            ActivityLog.shared.record(.action, "Playbook exported: \(playbook.summary) → \(url.lastPathComponent)", source: "Playbook")
            return "Playbook saved: \(playbook.summary)."
        } catch {
            return "Could not save: \(error.localizedDescription)"
        }
    }

    static func read(_ url: URL) throws -> Playbook {
        let data = try Data(contentsOf: url)
        guard let playbook = try? JSONDecoder.iso.decode(Playbook.self, from: data), playbook.luikPlaybook >= 1 else {
            throw NSError(domain: "Luik", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not a Luik playbook (expected a .luikplaybook.json file)."])
        }
        return playbook
    }

    /// Merges a playbook: one-liners are added (an existing id with the same title is replaced),
    /// checklists merged by service name, plan templates added, knowledge records appended with
    /// fresh MY-ids. Returns a summary.
    static func apply(_ playbook: Playbook, options: Options) -> String {
        var parts: [String] = []
        if options.snippets, let snippets = playbook.snippets {
            let store = SnippetStore.shared
            var added = 0, replaced = 0
            for snippet in snippets {
                if let index = store.snippets.firstIndex(where: { $0.id == snippet.id }) {
                    if store.snippets[index] != snippet { store.snippets[index] = snippet; replaced += 1 }
                } else if store.snippets.contains(where: { $0.title == snippet.title && $0.allCommands == snippet.allCommands }) {
                    continue
                } else {
                    store.snippets.append(snippet)
                    added += 1
                }
            }
            store.scheduleSave()
            parts.append("\(added) one-liner\(added == 1 ? "" : "s") added\(replaced > 0 ? ", \(replaced) updated" : "")")
        }
        if options.checklists, let checklists = playbook.checklists {
            ChecklistStore.shared.importSet(checklists, mode: .merge)
            parts.append("checklists merged (\(checklists.services.count) service lists)")
        }
        if options.planTemplates, let templates = playbook.planTemplates, !templates.isEmpty,
           let data = try? JSONEncoder.iso.encode(templates), let count = try? PlanStore.shared.importTemplates(from: data) {
            parts.append("\(count) plan template\(count == 1 ? "" : "s") added")
        }
        if options.knowledge, let table = playbook.knowledge, !table.records.isEmpty {
            let count = KnowledgeBaseStore.shared.appendMine(table.records)
            parts.append("\(count) knowledge record\(count == 1 ? "" : "s") added")
        }
        let summary = parts.isEmpty ? "Nothing selected." : parts.joined(separator: " · ")
        ActivityLog.shared.record(.action, "Playbook “\(playbook.name)” imported: \(summary)", source: "Playbook")
        return summary
    }
}

/// Sheet to export or import a playbook with the parts ticked.
struct PlaybookView: View {
    enum Mode: String, Identifiable {
        case export, importFile
        var id: String { rawValue }
    }

    let mode: Mode
    @Environment(\.dismiss) private var dismiss
    @Environment(UIState.self) private var ui
    @State private var name = ""
    @State private var options = PlaybookTransfer.Options()
    @State private var loaded: Playbook?
    @State private var fileName = ""
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(mode == .export ? "Export playbook" : "Import playbook")
                .font(.headline)
            Text(mode == .export
                 ? "What you know, in one file: for another Mac, a colleague or your team's repository. Engagement data, usage statistics and credentials never go in."
                 : "Merge a playbook into yours: one-liners and knowledge records are added, same-named checklists replaced, plan templates added.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if mode == .export {
                TextField("Name (e.g. “Pascal — web & AD”)", text: $name)
                    .textFieldStyle(.roundedBorder)
            } else {
                HStack {
                    Button("Choose file…") { choose() }
                    Text(fileName.isEmpty ? "No file chosen" : fileName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if let loaded {
                    Text("“\(loaded.name)” · exported \(loaded.exportedAt.formatted(date: .abbreviated, time: .shortened)) with Luik \(loaded.luikVersion) · \(loaded.summary)")
                        .font(.caption)
                }
            }
            Divider()
            Toggle(countLabel("One-liners", mode == .export ? SnippetStore.shared.snippets.count : loaded?.snippets?.count), isOn: $options.snippets)
                .disabled(mode == .importFile && loaded?.snippets == nil)
            Toggle(countLabel("Checklists", mode == .export ? ChecklistStore.shared.lists.services.count + 2 : loaded?.checklists.map { $0.services.count + 2 }), isOn: $options.checklists)
                .disabled(mode == .importFile && loaded?.checklists == nil)
            Toggle(countLabel("Plan templates (your own)", mode == .export ? PlanStore.shared.customTemplates.count : loaded?.planTemplates?.count), isOn: $options.planTemplates)
                .disabled(mode == .importFile && (loaded?.planTemplates?.isEmpty ?? true))
            Toggle(countLabel("Knowledge records (My findings)", mode == .export ? KnowledgeBaseStore.shared.mine.records.count : loaded?.knowledge?.records.count), isOn: $options.knowledge)
                .disabled(mode == .importFile && (loaded?.knowledge?.records.isEmpty ?? true))
            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(mode == .export ? "Save…" : "Import") {
                    if mode == .export {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        if let result = PlaybookTransfer.exportWithPanel(name: trimmed.isEmpty ? "Luik playbook" : trimmed, options: options) {
                            ui.flash(result)
                            dismiss()
                        }
                    } else if let loaded {
                        let result = PlaybookTransfer.apply(loaded, options: options)
                        ui.flash(result)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(mode == .importFile && loaded == nil)
            }
        }
        .padding(16)
        .frame(width: 480)
    }

    private func countLabel(_ title: String, _ count: Int?) -> String {
        guard let count else { return title }
        return "\(title) (\(count))"
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.message = "Choose a .luikplaybook.json file"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            loaded = try PlaybookTransfer.read(url)
            fileName = url.lastPathComponent
            message = nil
        } catch {
            loaded = nil
            message = error.localizedDescription
        }
    }
}
