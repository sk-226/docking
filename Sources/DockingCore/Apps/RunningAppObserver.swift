import AppKit
import Foundation

@MainActor
final class RunningAppObserver {
    struct Snapshot: Equatable {
        var runningBundleIDs: Set<String>
        var activeBundleID: String?
    }

    var onChange: ((Snapshot) -> Void)?
    private var tokens: [NSObjectProtocol] = []

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
        let running = Set(
            NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        )
        let active = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        onChange?(Snapshot(runningBundleIDs: running, activeBundleID: active))
    }
}
