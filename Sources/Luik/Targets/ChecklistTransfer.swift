import AppKit
import Foundation
import UniformTypeIdentifiers

/// Save/open panels and the questions around exporting and importing checklists, shared by the
/// editor, the Targets menu and Settings. Every function returns a short status line.
enum ChecklistTransfer {
    enum Format {
        case json
        case markdown
    }

    /// All checklists to a file of the user's choosing.
    @discardableResult
    static func exportAll(as format: Format) -> String? {
        let store = ChecklistStore.shared
        switch format {
        case .json:
            guard let data = store.exportJSON() else { return "Nothing to export." }
            return save(data, suggestedName: "luik-checklists.json", type: .json)
        case .markdown:
            return save(Data(store.markdown().utf8), suggestedName: "luik-checklists.md", type: UTType(filenameExtension: "md") ?? .plainText)
        }
    }

    /// One or more checklists (e.g. the selected one) as JSON.
    @discardableResult
    static func export(_ checklists: [Checklist]) -> String? {
        guard !checklists.isEmpty, let data = ChecklistStore.shared.exportJSON(checklists: checklists) else { return "Nothing to export." }
        let slug = checklists.count == 1
            ? String(checklists[0].name.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" })
            : "selection"
        return save(data, suggestedName: "luik-checklist-\(slug).json", type: .json)
    }

    /// Asks for a file, works out what it contains and how the user wants it applied.
    /// Returns a status line, or nil when the user cancelled.
    @discardableResult
    static func importWithPrompt() -> String? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.json, .plainText, UTType(filenameExtension: "md") ?? .plainText]
        panel.message = "Choose a checklists file exported from Luik (.json or .md)"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        let payload: ChecklistStore.ImportPayload
        do {
            payload = try ChecklistStore.decodeImport(try Data(contentsOf: url))
        } catch {
            return "Import failed: \(error.localizedDescription)"
        }

        let store = ChecklistStore.shared
        switch payload {
        case .set(let set):
            let alert = NSAlert()
            alert.messageText = "Import \(url.lastPathComponent)?"
            alert.informativeText = "The file holds a complete set: “\(set.host.name)”, “\(set.port.name)” and \(set.services.count) service checklist(s).\n\nMerge keeps your other service lists and replaces the ones with the same name; Replace everything throws your current checklists away (export them first if in doubt)."
            alert.addButton(withTitle: "Merge")
            alert.addButton(withTitle: "Replace everything")
            alert.addButton(withTitle: "Cancel")
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                store.importSet(set, mode: .merge)
                return "Merged \(set.services.count) service checklist(s) from \(url.lastPathComponent)."
            case .alertSecondButtonReturn:
                store.importSet(set, mode: .replaceAll)
                return "Replaced all checklists with \(url.lastPathComponent)."
            default:
                return nil
            }
        case .lists(let lists):
            let alert = NSAlert()
            alert.messageText = "Add \(lists.count == 1 ? "“\(lists[0].name)”" : "\(lists.count) checklists") from \(url.lastPathComponent)?"
            alert.informativeText = "A checklist with the same name as one you already have is replaced; others are added. Lists named “Every system” or “Every port” replace those."
            alert.addButton(withTitle: "Add")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return nil }
            store.importLists(lists)
            return "Imported \(lists.count) checklist(s) from \(url.lastPathComponent)."
        }
    }

    private static func save(_ data: Data, suggestedName: String, type: UTType) -> String? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = [type]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            try data.write(to: url)
            ActivityLog.shared.record(.action, "Checklists exported to \(url.path)", source: "Checklists")
            return "Exported to \(url.lastPathComponent)."
        } catch {
            return "Export failed: \(error.localizedDescription)"
        }
    }
}
