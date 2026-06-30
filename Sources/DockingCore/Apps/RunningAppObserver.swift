import AppKit
import Foundation

@MainActor
final class RunningAppObserver {
    struct Snapshot: Equatable {
        var runningBundleIDs: Set<String>
        var runningItems: [DockItem]
        var activeBundleID: String?
        var activeProcessIdentifier: pid_t?
    }

    var onChange: ((Snapshot) -> Void)?
    private var tokens: [NSObjectProtocol] = []
    private var itemIDsByKey: [String: UUID] = [:]
    private var singleDockTileByAppKey: [String: Bool] = [:]

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
        let keyedItems = applications.compactMap(dockItem(for:))
        var seenInstanceKeys: Set<String> = []
        let uniqueKeyedItems = keyedItems.filter { keyedItem in
            seenInstanceKeys.insert(keyedItem.instanceKey).inserted
        }
        let liveInstanceKeys = Set(uniqueKeyedItems.map(\.instanceKey))
        itemIDsByKey = itemIDsByKey.filter { liveInstanceKeys.contains($0.key) }

        let items = uniqueKeyedItems.map(\.item)
        let running = Set(items.compactMap(\.bundleIdentifier))
        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        let active = frontmostApplication?.bundleIdentifier
        let activeProcessIdentifier = frontmostApplication?.processIdentifier
        onChange?(
            Snapshot(
                runningBundleIDs: running,
                runningItems: items,
                activeBundleID: active,
                activeProcessIdentifier: activeProcessIdentifier
            )
        )
    }

    private func dockItem(for application: NSRunningApplication) -> (instanceKey: String, item: DockItem)? {
        guard Self.isDockVisibleRunningApplication(
            activationPolicy: application.activationPolicy,
            processIdentifier: application.processIdentifier
        ) else {
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
        let appKey = bundleIdentifier ?? application.bundleURL?.path ?? title
        let usesSingleDockTile = usesSingleDockTile(for: application, appKey: appKey)
        let instanceKey = Self.dockInstanceKey(
            appKey: appKey,
            processIdentifier: application.processIdentifier,
            usesSingleDockTile: usesSingleDockTile
        )
        let id = itemIDsByKey[instanceKey] ?? UUID()
        itemIDsByKey[instanceKey] = id

        // These are not persisted as pinned apps. They are live affordances for
        // apps the user chose not to keep in Docking, which is why the same
        // stable ID is reused only while the observer knows about the same
        // standard-Dock tile. Most apps use pid-level tiles when launched with
        // `open -n`: Calculator and TextEdit were observed as two standard Dock
        // icons for two regular processes, so Docking keeps those pids
        // addressable too. Ghostty is the counterexample that made a pure pid
        // rule wrong: its bundle declares NSDockTilePlugIn and the standard
        // Dock presents two regular Ghostty processes as one tile with the
        // app-provided Dock menu. For those apps we intentionally drop the pid
        // from the live item so active/running state follows the shared app
        // identity, matching the one-icon OS presentation.
        return (
            instanceKey,
            DockItem(
                id: id,
                kind: .application,
                title: title,
                bundleIdentifier: bundleIdentifier,
                url: application.bundleURL,
                iconCacheKey: appKey,
                runningProcessIdentifier: Self.runningProcessIdentifier(
                    processIdentifier: application.processIdentifier,
                    usesSingleDockTile: usesSingleDockTile
                ),
                isPinned: false
            )
        )
    }

    private func usesSingleDockTile(for application: NSRunningApplication, appKey: String) -> Bool {
        if let cached = singleDockTileByAppKey[appKey] {
            return cached
        }

        guard let bundleURL = application.bundleURL,
              let bundle = Bundle(url: bundleURL) else {
            singleDockTileByAppKey[appKey] = false
            return false
        }

        let usesSingleDockTile = Self.usesSingleDockTile(infoDictionary: bundle.infoDictionary)
        singleDockTileByAppKey[appKey] = usesSingleDockTile
        return usesSingleDockTile
    }

    nonisolated static func usesSingleDockTile(infoDictionary: [String: Any]?) -> Bool {
        // NSDockTilePlugIn is the public bundle-level signal that an app wants
        // to provide custom Dock-tile behavior. Empirically on this macOS
        // version, Ghostty uses that key and the standard Dock collapses two
        // `open -n` regular processes into one icon, while Calculator and
        // TextEdit omit the key and appear as two icons. We avoid asking the
        // Dock process itself for layout because Accessibility state is
        // user-permission-sensitive, localized, and not a stable app model API.
        infoDictionary?["NSDockTilePlugIn"] != nil
    }

    nonisolated static func dockInstanceKey(
        appKey: String,
        processIdentifier: pid_t,
        usesSingleDockTile: Bool
    ) -> String {
        if usesSingleDockTile {
            return appKey
        }
        return "\(appKey)#pid:\(processIdentifier)"
    }

    nonisolated static func runningProcessIdentifier(
        processIdentifier: pid_t,
        usesSingleDockTile: Bool
    ) -> pid_t? {
        usesSingleDockTile ? nil : processIdentifier
    }

    nonisolated static func isDockVisibleRunningApplication(
        activationPolicy: NSApplication.ActivationPolicy,
        processIdentifier: pid_t,
        currentProcessIdentifier: pid_t = ProcessInfo.processInfo.processIdentifier
    ) -> Bool {
        // Docking's running state should mirror the system Dock's visible app
        // model, not NSWorkspace's raw process list. Resident apps such as
        // Notion Calendar can keep an accessory/menu-bar process after a normal
        // Quit, and that process is still useful to the app, but it should not
        // keep a running dot or a transient running tile alive in Docking. The
        // app-specific "Quit Completely" path remains outside Docking's normal
        // Quit contract.
        activationPolicy == .regular && processIdentifier != currentProcessIdentifier
    }
}
