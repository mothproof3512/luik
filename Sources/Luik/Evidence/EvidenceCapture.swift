import AppKit
import Foundation

/// Screenshot evidence: runs macOS's own `screencapture -i` (drag a region, or press space for a
/// window), saves the PNG with a timestamp in the evidence folder, appends a Markdown link to the
/// selected target node and writes an entry to the activity log.
enum EvidenceCapture {
    /// ~/Documents/Luik Evidence unless configured otherwise.
    static var rootFolder: URL {
        let configured = UserDefaults.standard.string(forKey: SettingsKey.evidenceFolder) ?? ""
        let path = configured.trimmingCharacters(in: .whitespaces)
        if !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/Luik Evidence", isDirectory: true)
    }

    /// One subfolder per engagement: <root>/<engagement name>/
    static var folder: URL {
        rootFolder.appendingPathComponent(EngagementStore.shared.current.slug, isDirectory: true)
    }

    /// File name: 2026-10-10_14-32-05_10.10.10.5_445-tcp.png (node title slug when a node is selected).
    static func fileURL(for node: TargetNode?) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        var name = formatter.string(from: Date())
        if let node {
            let context = (TargetStore.shared.host(of: node)?.title ?? "") + (node.kind == .host ? "" : "_" + node.title)
            let slug = context.map { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_" ? $0 : "-" }
            if !slug.isEmpty { name += "_" + String(slug) }
        }
        return folder.appendingPathComponent(name + ".png")
    }

    /// Takes the screenshot. `completion` gets the file URL, or nil when the user cancelled.
    static func capture(completion: @escaping (URL?) -> Void) {
        let node = TargetStore.shared.selectedNode
        let url = fileURL(for: node)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            NSLog("Luik: could not create the evidence folder: %@", String(describing: error))
            completion(nil)
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", url.path]   // interactive: region, or space for a window
        process.terminationHandler = { _ in
            DispatchQueue.main.async {
                guard FileManager.default.fileExists(atPath: url.path) else {
                    completion(nil)   // cancelled with Esc
                    return
                }
                attach(url, to: node)
                completion(url)
            }
        }
        do {
            try process.run()
        } catch {
            NSLog("Luik: screencapture failed: %@", String(describing: error))
            completion(nil)
        }
    }

    /// Appends "![evidence](path)" with a timestamp to the node's notes and logs the capture.
    private static func attach(_ url: URL, to node: TargetNode?) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let stamp = formatter.string(from: Date())
        if let node {
            var notes = node.notes
            if !notes.isEmpty && !notes.hasSuffix("\n") { notes += "\n" }
            notes += "![evidence \(stamp)](\(url.path))\n"
            node.notes = notes
            TargetStore.shared.scheduleSave()
        }
        let context = node.map { " for \($0.title)" } ?? ""
        ActivityLog.shared.record(.evidence, "Screenshot\(context): \(url.path)", source: "Evidence")
    }
}
