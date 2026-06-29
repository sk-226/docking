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

    func quit(_ item: DockItem) {
        guard let application = runningApplication(for: item) else {
            DockingLog.dock.notice("Quit ignored because \(item.title) is not running.")
            return
        }

        // This mirrors the normal Dock's Quit action: ask the app to terminate
        // cleanly first so document-based apps can save state or present their
        // own confirmation. We do not synthesize menu commands or AppleEvents
        // because `NSRunningApplication.terminate()` is the public API designed
        // for this process-level request.
        if !application.terminate() {
            DockingLog.dock.error("Could not request quit for \(item.title).")
        }
    }

    func forceQuit(_ item: DockItem) {
        guard let application = runningApplication(for: item) else {
            DockingLog.dock.notice("Force Quit ignored because \(item.title) is not running.")
            return
        }

        // Force Quit can lose unsaved work. The UI owns the confirmation; this
        // service stays small and does only the public AppKit process action
        // once the user has explicitly chosen it.
        if !application.forceTerminate() {
            DockingLog.dock.error("Could not force quit \(item.title).")
        }
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
        guard item.isApplication else {
            return nil
        }

        if let bundleIdentifier = item.bundleIdentifier {
            return NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
                .first { application in
                    application.activationPolicy == .regular &&
                    application.processIdentifier != ProcessInfo.processInfo.processIdentifier
                }
        }

        return NSWorkspace.shared.runningApplications.first { application in
            guard application.activationPolicy == .regular,
                  application.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
                return false
            }
            return RunningApplicationMatcher.matches(
                item: item,
                applicationBundleIdentifier: application.bundleIdentifier,
                applicationBundleURL: application.bundleURL
            )
        }
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
