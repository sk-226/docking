import Foundation

final class SettingsStore {
    private let defaults: UserDefaults
    private let appleDockDefaults: UserDefaults?
    private let key = "DockingSettings.v2"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard, appleDockDefaults: UserDefaults? = UserDefaults(suiteName: "com.apple.dock")) {
        self.defaults = defaults
        self.appleDockDefaults = appleDockDefaults
    }

    func load() -> DockingSettings {
        guard let data = defaults.data(forKey: key) else {
            // Docking's first-run behavior should mirror the user's existing
            // Apple Dock visibility instead of imposing an arbitrary app default.
            // We only do this before Docking has saved its own settings; after
            // that, the user's Docking preference is the source of truth.
            return .defaults(matchingAppleDock: appleDockDefaults)
        }

        do {
            return try decoder.decode(DockingSettings.self, from: data)
        } catch {
            // A corrupted settings blob should not prevent a dock from appearing.
            // Because this is still a 0.0.0 app, we intentionally do not carry a
            // compatibility decoder for obsolete settings shapes. Re-seeding from
            // Apple Dock keeps the app usable without touching system settings.
            DockingLog.app.error("Failed to decode settings: \(error.localizedDescription)")
            return .defaults(matchingAppleDock: appleDockDefaults)
        }
    }

    func save(_ settings: DockingSettings) {
        do {
            defaults.set(try encoder.encode(settings), forKey: key)
        } catch {
            DockingLog.app.error("Failed to encode settings: \(error.localizedDescription)")
        }
    }
}
