import Foundation

final class DockSettingsSnapshotService {
    private let fileURL: URL
    private let dockDefaults: UserDefaults?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileURL: URL? = nil, dockDefaults: UserDefaults? = UserDefaults(suiteName: "com.apple.dock")) {
        // The Dock preferences domain is a real system-facing store. Injecting
        // it keeps production behavior direct while letting validation use a
        // temporary suite instead of reading or writing the user's Apple Dock
        // preferences.
        self.dockDefaults = dockDefaults
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let directory = (try? AppSupportDirectory.url()) ?? FileManager.default.temporaryDirectory
            self.fileURL = directory.appendingPathComponent("DockRestoreSnapshot.json")
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func loadSnapshot() throws -> DockRestoreSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        return try decoder.decode(DockRestoreSnapshot.self, from: Data(contentsOf: fileURL))
    }

    func saveSnapshot(_ snapshot: DockRestoreSnapshot) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoder.encode(snapshot).write(to: fileURL, options: .atomic)
    }

    func currentDockSnapshot() -> DockRestoreSnapshot {
        let keys = [
            "autohide",
            "tilesize",
            "largesize",
            "magnification",
            "orientation",
            "show-recents",
            "autohide-delay",
            "autohide-time-modifier"
        ]

        var values: [String: DockPreferenceValue] = [:]
        for key in keys {
            if let value = dockDefaults?.object(forKey: key) as? Bool {
                values[key] = .bool(value)
            } else if let value = dockDefaults?.object(forKey: key) as? Double {
                values[key] = .double(value)
            } else if let value = dockDefaults?.object(forKey: key) as? Int {
                values[key] = .double(Double(value))
            } else if let value = dockDefaults?.object(forKey: key) as? String {
                values[key] = .string(value)
            }
        }

        return DockRestoreSnapshot(createdAt: Date(), appVersion: AppMetadata.version, values: values)
    }
}
