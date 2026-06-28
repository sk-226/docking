import Foundation

struct DockRestoreResult: Equatable {
    var userMessage: String
}

struct DockRestoreStatus: Equatable {
    var snapshotCreatedAt: Date?
    var snapshotAppVersion: String?
    var savedPreferenceCount: Int

    var hasSnapshot: Bool {
        snapshotCreatedAt != nil
    }
}

struct DockManualRestoreInstructions: Equatable {
    var text: String
}

final class DockSettingsRestoreService {
    private let snapshotService: DockSettingsSnapshotService
    private let dockDefaults: UserDefaults?

    init(
        snapshotService: DockSettingsSnapshotService = DockSettingsSnapshotService(),
        dockDefaults: UserDefaults? = UserDefaults(suiteName: "com.apple.dock")
    ) {
        self.snapshotService = snapshotService
        self.dockDefaults = dockDefaults
    }

    func restoreStatus() -> DockRestoreStatus {
        guard let snapshot = try? snapshotService.loadSnapshot() else {
            return DockRestoreStatus(snapshotCreatedAt: nil, snapshotAppVersion: nil, savedPreferenceCount: 0)
        }

        return DockRestoreStatus(
            snapshotCreatedAt: snapshot.createdAt,
            snapshotAppVersion: snapshot.appVersion,
            savedPreferenceCount: snapshot.values.count
        )
    }

    func savedDockPreferenceValues() -> [String: DockPreferenceValue]? {
        try? snapshotService.loadSnapshot()?.values
    }

    func manualRestoreInstructions() -> DockManualRestoreInstructions {
        guard let snapshot = try? snapshotService.loadSnapshot() else {
            return DockManualRestoreInstructions(
                text: "No saved Apple Dock snapshot exists. Docking is overlay-only unless you explicitly enabled primary dock mode."
            )
        }

        let commands = snapshot.values
            .sorted { $0.key < $1.key }
            .map { key, value in
                Self.defaultsCommand(key: key, value: value)
            }
            .joined(separator: "\n")

        return DockManualRestoreInstructions(
            text: """
            If the Restore button fails or Docking has already been removed, these Terminal commands write the saved Apple Dock snapshot back:
            \(commands)
            killall Dock
            """
        )
    }

    func enableReplacementMode() throws -> DockRestoreResult {
        // Replacement mode is intentionally conservative: it makes Apple's Dock
        // step out of the way, but it does not delete Dock contents, rewrite app
        // tiles, or touch system files. The original preference snapshot is
        // captured before the first write so the Restore button has a durable
        // source of truth even if Docking is relaunched later.
        if try snapshotService.loadSnapshot() == nil {
            try snapshotService.saveSnapshot(snapshotService.currentDockSnapshot())
        }

        // The least invasive way to let Docking act as the primary dock is to
        // keep the Apple Dock present but strongly auto-hidden. This avoids
        // private APIs and keeps the system Dock recoverable through normal
        // macOS behavior. We deliberately do not mutate persistent-app arrays
        // or any Dock database-like state because those changes are harder for
        // users to audit and unnecessary for a personal overlay dock.
        dockDefaults?.set(true, forKey: "autohide")
        dockDefaults?.set(1000.0, forKey: "autohide-delay")
        dockDefaults?.set(0.0, forKey: "autohide-time-modifier")
        dockDefaults?.synchronize()

        return DockRestoreResult(
            userMessage: "Docking primary dock mode is enabled. Your original Apple Dock settings were saved. Reload Apple Dock or log out/in if macOS has not applied the auto-hide changes yet."
        )
    }

    func restoreIfSnapshotExists() throws -> DockRestoreResult {
        guard let snapshot = try snapshotService.loadSnapshot() else {
            return DockRestoreResult(
                userMessage: "No Dock restore snapshot exists. Docking 0.0.0 has not changed Apple Dock settings."
            )
        }

        // The defaults store is injected so validation can prove restore
        // semantics against a temporary suite. The production default remains
        // Apple's Dock domain, but tests never need to write there.
        for (key, value) in snapshot.values {
            switch value {
            case .bool(let bool):
                dockDefaults?.set(bool, forKey: key)
            case .double(let double):
                dockDefaults?.set(double, forKey: key)
            case .string(let string):
                dockDefaults?.set(string, forKey: key)
            }
        }
        dockDefaults?.synchronize()

        // We deliberately do not run `killall Dock` here. Restarting Apple's
        // Dock is visible and disruptive, and the goal file forbids doing it
        // without explicit confirmation. Writing the saved values plus telling
        // the user how to reload keeps restoration reversible and transparent.
        return DockRestoreResult(
            userMessage: "Saved Dock settings from \(snapshot.createdAt) were written back. Log out/in or restart Dock manually if macOS has not reloaded them."
        )
    }

    func reloadAppleDock() throws -> DockRestoreResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["Dock"]

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw error
        }

        guard process.terminationStatus == 0 else {
            return DockRestoreResult(
                userMessage: "Docking asked macOS to reload Apple Dock, but killall exited with status \(process.terminationStatus). Log out/in to apply Dock preference changes."
            )
        }

        return DockRestoreResult(
            userMessage: "Apple Dock was reloaded so macOS can apply the saved Dock preference changes."
        )
    }

    private static func defaultsCommand(key: String, value: DockPreferenceValue) -> String {
        switch value {
        case .bool(let bool):
            return "defaults write com.apple.dock \(key) -bool \(bool ? "true" : "false")"
        case .double(let double):
            return "defaults write com.apple.dock \(key) -float \(double)"
        case .string(let string):
            return "defaults write com.apple.dock \(key) -string \(shellSingleQuoted(string))"
        }
    }

    private static func shellSingleQuoted(_ value: String) -> String {
        // The restore keys we snapshot are expected to have simple values like
        // "bottom" or "left", but this text can become a Terminal command. A
        // correct single-quote escape costs almost nothing and prevents a future
        // preference value from turning emergency instructions into malformed
        // shell syntax.
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }
}
