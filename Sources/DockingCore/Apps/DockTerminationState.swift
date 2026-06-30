import Foundation

enum DockTerminationState {
    static func appIdentityKey(for item: DockItem) -> String? {
        guard item.isApplication else {
            return nil
        }

        if let bundleIdentifier = item.bundleIdentifier {
            return "app:\(bundleIdentifier)"
        }

        if let url = item.url {
            return "application:\(url.standardizedFileURL.path)"
        }

        return nil
    }

    static func identityKey(for item: DockItem) -> String? {
        guard item.isApplication else {
            return nil
        }

        if let runningInstanceKey = item.runningInstanceKey {
            return runningInstanceKey
        }

        // Bundle identifiers are the stable path for ordinary apps, but
        // Docking also supports unsigned/development bundles where
        // LaunchServices cannot give us a durable identifier. Falling back to
        // the standardized app path keeps Quit/Force Quit state aligned with
        // `RunningApplicationMatcher` without making the UI depend on a
        // localized title that can change between launches.
        return appIdentityKey(for: item)
    }

    static func identityKey(for item: DockItem, processIdentifier: pid_t) -> String? {
        guard item.isApplication else {
            return nil
        }

        // Quit reconciliation follows the Dock icon that initiated the action,
        // not the whole bundle. For transient running items the pid is already
        // stored on the item; for pinned items AppLauncherService reports the
        // process it actually asked to terminate. Using the same key shape in
        // both paths lets one Calculator/TextEdit instance reconcile without
        // blocking a sibling icon, matching the standard Dock's per-instance
        // behavior for apps it exposes as separate tiles.
        if let runningInstanceKey = item.runningInstanceKey,
           item.runningProcessIdentifier == processIdentifier {
            return runningInstanceKey
        }

        if let bundleIdentifier = item.bundleIdentifier {
            return "app:\(bundleIdentifier)#pid:\(processIdentifier)"
        }

        if let url = item.url {
            return "application:\(url.standardizedFileURL.path)#pid:\(processIdentifier)"
        }

        return nil
    }

    static func isPending(_ item: DockItem, pendingKeys: Set<String>) -> Bool {
        guard let key = identityKey(for: item) else {
            return false
        }
        return pendingKeys.contains(key)
    }

    static func completedPendingKeys(pendingKeys: Set<String>, runningItems: [DockItem]) -> Set<String> {
        let activeKeys = Set(
            runningItems.flatMap { item in
                [
                    identityKey(for: item),
                    appIdentityKey(for: item)
                ].compactMap { $0 }
            }
        )
        return pendingKeys.subtracting(activeKeys)
    }
}
