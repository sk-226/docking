import AppKit
import Foundation

@MainActor
final class AppLauncherService {
    func open(_ item: DockItem) {
        guard let url = resolvedURL(for: item) else {
            DockingLog.dock.error("Could not resolve URL for \(item.title)")
            return
        }

        guard item.isApplication else {
            // Folder stack clicks are handled by FolderStackPanelController.
            // Context-menu Open should use Finder, matching the Apple Dock's
            // separation between "show me the stack contents" and "open this
            // folder as a normal Finder location."
            NSWorkspace.shared.open(url)
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        // NSWorkspace handles activation, app reuse, and bundle semantics better
        // than shelling out to `open`. Avoiding shell commands also keeps launch
        // behavior testable and avoids surprising quoting/path edge cases.
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            if let error {
                DockingLog.dock.error("Failed to launch \(item.title): \(error.localizedDescription)")
            }
        }
    }

    func showInFinder(_ item: DockItem) {
        guard let url = resolvedURL(for: item) else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openFile(_ fileURL: URL, with item: DockItem) {
        guard item.isApplication,
              let applicationURL = resolvedURL(for: item) else {
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        // This is the public Dock-equivalent path for "drag a document onto an
        // app icon". We deliberately do not turn the document into a Docking
        // item: apps/folders are Dock contents, while ordinary files dropped on
        // an app are inputs for that app. Letting NSWorkspace broker the open
        // keeps LaunchServices' type checks, activation, and app reuse intact.
        NSWorkspace.shared.open([fileURL], withApplicationAt: applicationURL, configuration: configuration) { _, error in
            if let error {
                DockingLog.dock.error("Failed to open \(fileURL.lastPathComponent) with \(item.title): \(error.localizedDescription)")
            }
        }
    }

    func showAllWindows(_ item: DockItem) {
        guard let application = runningApplication(for: item) else {
            open(item)
            return
        }

        // Apple's Dock can expose "Show All Windows". Public AppKit does not
        // give third-party apps the same window-picker UI, so the closest safe
        // behavior is to activate the app and ask macOS to bring all of its
        // windows forward. This preserves the core task-switching intent without
        // private Mission Control or Dock APIs.
        // We intentionally do not force frontmost activation here. On the
        // Tahoe-only baseline, `activateAllWindows` is the public behavior that
        // maps to the Dock action without pretending we can recreate Mission
        // Control's private window picker.
        let options: NSApplication.ActivationOptions = [.activateAllWindows]
        if !application.activate(options: options) {
            DockingLog.dock.error("Could not show windows for \(item.title).")
        }
    }

    func hide(_ item: DockItem) {
        guard let application = runningApplication(for: item) else {
            DockingLog.dock.notice("Hide ignored because \(item.title) is not running.")
            return
        }

        // Hide is a reversible Dock-style action. It should not terminate the
        // app or mutate Docking's pinned list; it only asks the target process
        // to hide through the system-managed NSRunningApplication API.
        if !application.hide() {
            DockingLog.dock.error("Could not hide \(item.title).")
        }
    }

    @discardableResult
    func quit(_ item: DockItem) -> [pid_t] {
        let applications = runningApplications(for: item, selectionPolicy: .termination)
        guard !applications.isEmpty else {
            DockingLog.dock.notice("Quit ignored because \(item.title) is not running.")
            return []
        }

        var requestedProcessIdentifiers: [pid_t] = []
        for application in applications {
            // This mirrors the normal Dock's Quit action for a single visible
            // Dock icon: ask that app process to terminate cleanly first so
            // document-based apps can save state or present their own
            // confirmation. We intentionally do not fan pid-bound live tiles
            // out to every process with the same bundle identifier. The
            // standard Dock was observed with Calculator and TextEdit launched
            // twice via `open -n`: it displayed two icons, so each icon needs
            // its own process boundary. A bundle-wide Quit would be simpler,
            // and it briefly looked like a fix for "the app stayed visible",
            // but it is not the OS model the user asked us to match.
            //
            // We deliberately do not chase accessory/menu-bar resident
            // processes here. Notion Calendar is the concrete edge case: its
            // ordinary Quit can leave a menu-bar app alive, while "Quit
            // Completely" is a separate app-specific command. Docking's normal
            // Quit should match the system Dock/App-menu contract, not invent a
            // stronger app-specific full-exit action.
            //
            // We still use NSRunningApplication rather than synthesized menu
            // commands or AppleEvents because it is the public process-level
            // API AppKit provides. The trade-off is that apps that reject a
            // clean quit can remain running; Docking reconciles that state
            // shortly after the request instead of pretending the quit was a
            // force kill.
            if application.terminate() {
                requestedProcessIdentifiers.append(application.processIdentifier)
            } else {
                DockingLog.dock.error("Could not request quit for \(item.title) process \(application.processIdentifier).")
            }
        }

        return requestedProcessIdentifiers
    }

    @discardableResult
    func forceQuit(_ item: DockItem) -> [pid_t] {
        let applications = runningApplications(for: item, selectionPolicy: .termination)
        guard !applications.isEmpty else {
            DockingLog.dock.notice("Force Quit ignored because \(item.title) is not running.")
            return []
        }

        var requestedProcessIdentifiers: [pid_t] = []
        for application in applications {
            // Force Quit can lose unsaved work. The UI owns the confirmation;
            // this service stays small and does only the public AppKit process
            // action once the user has explicitly chosen it. It follows the
            // same per-icon targeting as Quit; Force Quit is stronger about
            // how the selected process exits, not broader about which sibling
            // instances it selects.
            if application.forceTerminate() {
                requestedProcessIdentifiers.append(application.processIdentifier)
            } else {
                DockingLog.dock.error("Could not force quit \(item.title) process \(application.processIdentifier).")
            }
        }

        return requestedProcessIdentifiers
    }

    private func resolvedURL(for item: DockItem) -> URL? {
        if let itemURL = item.url {
            return itemURL
        }
        if let bundleIdentifier = item.bundleIdentifier {
            return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        }
        return nil
    }

    private func runningApplication(for item: DockItem) -> NSRunningApplication? {
        runningApplications(for: item, selectionPolicy: .foregroundPresentation).first
    }

    private func runningApplications(
        for item: DockItem,
        selectionPolicy: RunningApplicationSelectionPolicy
    ) -> [NSRunningApplication] {
        guard item.isApplication else {
            return []
        }

        let matches: [NSRunningApplication]
        if let bundleIdentifier = item.bundleIdentifier {
            matches = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
                .filter { application in
                    RunningApplicationSelector.matches(
                        item: item,
                        application: application,
                        selectionPolicy: selectionPolicy
                    )
                }
        } else {
            matches = NSWorkspace.shared.runningApplications.filter { application in
                RunningApplicationSelector.matches(
                    item: item,
                    application: application,
                    selectionPolicy: selectionPolicy
                )
            }
        }

        if item.runningProcessIdentifier != nil {
            return matches
        }

        // A persisted/pinned DockItem is an app identity, not a live process.
        // When multiple regular instances exist, the standard Dock accounts
        // for one instance with the pinned icon and exposes siblings as extra
        // icons. Choosing only the first match keeps this identity item to one
        // icon's worth of behavior. The additional live items carry pids and
        // can be acted on independently.
        return Array(matches.prefix(1))
    }
}

struct RunningApplicationSnapshot: Equatable {
    var processIdentifier: pid_t
    var activationPolicy: NSApplication.ActivationPolicy
    var bundleIdentifier: String?
    var bundleURL: URL?

    init(
        processIdentifier: pid_t,
        activationPolicy: NSApplication.ActivationPolicy,
        bundleIdentifier: String?,
        bundleURL: URL?
    ) {
        self.processIdentifier = processIdentifier
        self.activationPolicy = activationPolicy
        self.bundleIdentifier = bundleIdentifier
        self.bundleURL = bundleURL
    }

    init(application: NSRunningApplication) {
        self.init(
            processIdentifier: application.processIdentifier,
            activationPolicy: application.activationPolicy,
            bundleIdentifier: application.bundleIdentifier,
            bundleURL: application.bundleURL
        )
    }
}

enum RunningApplicationSelectionPolicy {
    case foregroundPresentation
    case termination

    func accepts(_ activationPolicy: NSApplication.ActivationPolicy) -> Bool {
        switch self {
        case .foregroundPresentation:
            // Show/Hide are window-presentation actions. Accessory apps can be
            // real user apps, but AppKit does not guarantee they have ordinary
            // windows to activate or hide. Keeping this path regular-only
            // preserves the old behavior for presentation commands and avoids
            // turning a Dock click into a surprising relaunch request.
            return activationPolicy == .regular
        case .termination:
            // The system Dock's ordinary Quit acts on the visible app identity;
            // it is not the same as every app's optional "quit completely"
            // command. Keeping termination regular-only preserves that line for
            // resident apps such as Notion Calendar, where accessory/menu-bar
            // state can intentionally survive a normal Quit.
            return activationPolicy == .regular
        }
    }
}

enum RunningApplicationSelector {
    static func matches(
        item: DockItem,
        application: NSRunningApplication,
        selectionPolicy: RunningApplicationSelectionPolicy = .foregroundPresentation,
        currentProcessIdentifier: pid_t = ProcessInfo.processInfo.processIdentifier
    ) -> Bool {
        matches(
            item: item,
            snapshot: RunningApplicationSnapshot(application: application),
            selectionPolicy: selectionPolicy,
            currentProcessIdentifier: currentProcessIdentifier
        )
    }

    static func matches(
        item: DockItem,
        snapshot: RunningApplicationSnapshot,
        selectionPolicy: RunningApplicationSelectionPolicy = .foregroundPresentation,
        currentProcessIdentifier: pid_t
    ) -> Bool {
        guard selectionPolicy.accepts(snapshot.activationPolicy),
              snapshot.processIdentifier != currentProcessIdentifier else {
            return false
        }

        if let itemProcessIdentifier = item.runningProcessIdentifier,
           itemProcessIdentifier != snapshot.processIdentifier {
            return false
        }

        // Selection is identity-based with an optional pid boundary. Live
        // running items carry a pid because the standard Dock exposes duplicate
        // regular app instances as duplicate icons; pinned items do not carry a
        // pid because they are durable app shortcuts. The caller supplies the
        // activation-policy boundary because the policy is part of the user
        // contract, not just process metadata. In particular, normal Quit stays
        // regular-only so it does not become an app-specific "quit completely"
        // command for resident menu-bar apps. In every mode we still exclude
        // Docking itself and require a bundle/path identity match so helpers
        // with unrelated identities do not get swept up accidentally.
        return RunningApplicationMatcher.matches(
            item: item,
            applicationBundleIdentifier: snapshot.bundleIdentifier,
            applicationBundleURL: snapshot.bundleURL
        )
    }
}

enum RunningApplicationMatcher {
    static func matches(
        item: DockItem,
        applicationBundleIdentifier: String?,
        applicationBundleURL: URL?
    ) -> Bool {
        guard item.isApplication else {
            return false
        }

        if let itemBundleIdentifier = item.bundleIdentifier,
           itemBundleIdentifier == applicationBundleIdentifier {
            return true
        }

        guard let itemPath = item.url?.standardizedFileURL.path,
              let applicationPath = applicationBundleURL?.standardizedFileURL.path else {
            return false
        }

        // Some user apps, helper-style bundles, or development builds can be
        // missing a stable bundle identifier. The macOS Dock still lets users
        // manage those apps while they are running, so Docking falls back to
        // the standardized bundle path instead of hiding Quit/Force Quit.
        return itemPath == applicationPath
    }
}
