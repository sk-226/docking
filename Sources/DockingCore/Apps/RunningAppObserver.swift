import AppKit
import Foundation

@MainActor
final class RunningAppObserver {
    struct Snapshot: Equatable {
        var runningBundleIDs: Set<String>
        var runningItems: [DockItem]
        var activeBundleID: String?
    }

    var onChange: ((Snapshot) -> Void)?
    private var tokens: [NSObjectProtocol] = []
    private var itemIDsByKey: [String: UUID] = [:]

    func start() {
        stop()
        publishCurrentSnapshot()

        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didActivateApplicationNotification
        ]

        tokens = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.publishCurrentSnapshot()
                }
            }
        }
    }

    func refresh() {
        // This is intentionally a single snapshot read, not a polling loop.
        // Wake and display-change events are rare but can leave AppKit process
        // state stale, so the app model asks for one explicit refresh there.
        publishCurrentSnapshot()
    }

    func stop() {
        let center = NSWorkspace.shared.notificationCenter
        for token in tokens {
            center.removeObserver(token)
        }
        tokens.removeAll()
    }

    private func publishCurrentSnapshot() {
        let applications = NSWorkspace.shared.runningApplications
        let running = Set(applications.compactMap(\.bundleIdentifier))
        let items = applications.compactMap(dockItem(for:))
        let active = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        onChange?(Snapshot(runningBundleIDs: running, runningItems: items, activeBundleID: active))
    }

    private func dockItem(for application: NSRunningApplication) -> DockItem? {
        guard application.activationPolicy == .regular,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return nil
        }

        let bundleIdentifier = application.bundleIdentifier
        guard bundleIdentifier != nil || application.bundleURL != nil else {
            return nil
        }

        let title = application.localizedName?.nilIfBlank
            ?? application.bundleURL?.deletingPathExtension().lastPathComponent
            ?? bundleIdentifier
            ?? "Running app"
        let key = bundleIdentifier ?? application.bundleURL?.path ?? title
        let id = itemIDsByKey[key] ?? UUID()
        itemIDsByKey[key] = id

        // These are not persisted as pinned apps. They are live affordances for
        // apps the user chose not to keep in Docking, which is why the same
        // stable ID is reused only while the observer knows about that app. A
        // persisted insert happens explicitly through "Keep in Docking".
        return DockItem(
            id: id,
            kind: .application,
            title: title,
            bundleIdentifier: bundleIdentifier,
            url: application.bundleURL,
            iconCacheKey: key,
            isPinned: false
        )
    }
}
