import Foundation

/// All Luik data lives as JSON in ~/Library/Application Support/Luik/
enum Storage {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("Luik", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static func url(for name: String) -> URL {
        directory.appendingPathComponent(name)
    }

    /// Global files (one per installation) live directly in the data folder.
    static func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        load(type, at: url(for: name))
    }

    static func save<T: Encodable>(_ value: T, to name: String) {
        save(value, at: url(for: name))
    }

    /// Per-engagement files live in Engagements/<id>/ (see EngagementStore.fileURL).
    static func load<T: Decodable>(_ type: T.Type, at fileURL: URL) -> T? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            NSLog("Luik: could not read %@: %@", fileURL.lastPathComponent, String(describing: error))
            // Keep a copy so a read error never loses data.
            let backup = fileURL.deletingLastPathComponent()
                .appendingPathComponent(fileURL.lastPathComponent + ".corrupt-\(Int(Date().timeIntervalSince1970))")
            try? FileManager.default.copyItem(at: fileURL, to: backup)
            return nil
        }
    }

    static func save<T: Encodable>(_ value: T, at fileURL: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            let folder = fileURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: folder.path) {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            }
            let data = try encoder.encode(value)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Luik: could not save %@: %@", fileURL.lastPathComponent, String(describing: error))
        }
    }
}

/// Runs a block only once calls have stopped coming in for a moment (autosave).
final class Debouncer {
    private var workItem: DispatchWorkItem?
    private let delay: TimeInterval

    init(delay: TimeInterval = 0.8) {
        self.delay = delay
    }

    func call(_ block: @escaping () -> Void) {
        workItem?.cancel()
        let item = DispatchWorkItem(block: block)
        workItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    /// Run a pending block right now, if there is one.
    func flush() {
        guard let item = workItem else { return }
        workItem = nil
        item.perform()
        item.cancel()
    }
}
