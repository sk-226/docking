import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
public final class DockingAppModel: ObservableObject {
    public static let shared = DockingAppModel()

    @Published var settings: DockingSettings {
        didSet {
            let shouldRefreshCalendar = oldValue.calendarRefreshKey != settings.calendarRefreshKey
            let shouldRefreshWeather = oldValue.weatherRefreshKey != settings.weatherRefreshKey

            scheduleSettingsSave()
            applySettingsToWindows()
            handleDisabledWidgetsAfterSettingsChange()
            refreshWidgetsAfterSettingsChange(calendar: shouldRefreshCalendar, weather: shouldRefreshWeather)
        }
    }

    @Published var dockItems: [DockItem] {
        didSet {
            appListStore.save(dockItems)
            applySettingsToWindows()
        }
    }

    @Published var runningBundleIDs: Set<String> = []
    @Published var runningAppItems: [DockItem] = [] {
        didSet {
            applySettingsToWindows()
        }
    }
    @Published private var terminationPendingItemKeys: Set<String> = [] {
        didSet {
            guard oldValue != terminationPendingItemKeys else {
                return
            }
            applySettingsToWindows()
        }
    }
    @Published private var terminationPendingItemIDs: Set<UUID> = [] {
        didSet {
            guard oldValue != terminationPendingItemIDs else {
                return
            }
            applySettingsToWindows()
        }
    }
    @Published var activeBundleID: String?
    @Published var activeProcessIdentifier: pid_t?
    @Published var restoreStatusMessage: String = "Docking is currently overlay-only and has not changed Apple Dock settings."
    @Published var dockRestoreStatus = DockRestoreStatus(snapshotCreatedAt: nil, snapshotAppVersion: nil, savedPreferenceCount: 0)
    @Published var launchAtLoginStatusMessage: String = "Launch at login uses macOS Login Items when enabled."
    @Published var appleDockVisibilityStatusMessage: String = AppleDockPreferences.visibilityStatusText()
    // Control Center is primarily a settings surface. Opening it directly into
    // General matches the menu-bar entry point and keeps the first screen on
    // everyday settings instead of diagnostic status.
    @Published var controlCenterSelection: ControlCenterSection = .general
    @Published var manualRestoreInstructions: String = "No saved Apple Dock snapshot exists. Docking is overlay-only unless you explicitly enabled primary dock mode."

    let calendarViewModel: CalendarWidgetViewModel
    let weatherViewModel: WeatherWidgetViewModel

    private let settingsStore: SettingsStore
    private let appListStore: AppListStore
    private let appCatalogService = AppCatalogService()
    private let appLauncherService = AppLauncherService()
    private let runningObserver = RunningAppObserver()
    private let iconCache = AppIconCache()
    private let dockPanelController = DockPanelController()
    private let widgetDetailPanelController = WidgetDetailPanelController()
    private let folderStackPanelController = FolderStackPanelController()
    private let restoreService = DockSettingsRestoreService()
    private let launchAtLoginService = LaunchAtLoginService()
    private let menuBarStatusController = MenuBarStatusController()
    private var controlCenterWindow: NSWindow?
    private var hasStarted = false
    private var environmentObserverTokens: [(NotificationCenter, NSObjectProtocol)] = []
    private var pendingSettingsSaveTask: Task<Void, Never>?
    private var terminationReconciliationTasks: [String: Task<Void, Never>] = [:]
    private var terminationPendingKeysByItemID: [UUID: Set<String>] = [:]
    private var widgetFrames: [DockWidgetKind: NSRect] = [:]
    private var dockItemFrames: [UUID: NSRect] = [:]
    // Pointer residency is an auto-hide controller invariant, not presentation
    // state. Publishing it looked convenient while debugging, but no SwiftUI
    // view reads it directly; sending ObservableObject changes from hover or
    // tracking-area callbacks can collide with SwiftUI's own layout pass during
    // launch. Keeping it ordinary MainActor state preserves the behavior while
    // avoiding a noisy and unnecessary view invalidation path.
    var isPointerInsideDock = false
    // Auto-hide should hide after pointer exit, but an explicit Show Dock
    // button/menu command is different from a passive edge reveal. The user has
    // asked to see the dock, so a previously scheduled hide must not win while
    // they are still moving from Control Center or the menu toward the dock.
    // This flag is cleared as soon as the pointer actually enters or exits the
    // dock region, returning control to the normal auto-hide lifecycle.
    private var holdsDockAfterExplicitShow = false
    private static let settingsSaveDelayNanoseconds: UInt64 = 350_000_000
    private static let terminationObservationDelayNanoseconds: UInt64 = 750_000_000
    private static let terminationReconciliationDelayNanoseconds: UInt64 = 2_500_000_000

    var enabledWidgetCount: Int {
        (settings.calendarEnabled ? 1 : 0) + (settings.weatherEnabled ? 1 : 0)
    }

    var unpinnedRunningItems: [DockItem] {
        // Pending Quit state is not a display filter. The system Dock keeps an
        // app icon tied to the real process/window lifecycle: Ghostty vanishes
        // when the process terminates, while resident apps such as Notion
        // Calendar may briefly change presentation policy or intentionally
        // remain alive. Hiding a running item before NSWorkspace agrees makes
        // Docking look faster, but it is a self-invented behavior and it caused
        // the next click to be interpreted as Open during shutdown. Keep the
        // item visible, block accidental launch while pending, and let the
        // observer's refreshed process snapshot decide whether the icon stays.
        DockRunningItemResolver.unpinnedRunningItems(
            pinnedItems: dockItems,
            runningItems: runningAppItems,
            visibility: settings.unpinnedRunningAppVisibility
        )
    }

    var visibleAppItemCount: Int {
        dockItems.count + unpinnedRunningItems.count
    }

    var hasSeparatedRunningItems: Bool {
        !unpinnedRunningItems.isEmpty
    }

    private var isDockAnchoredPanelVisible: Bool {
        widgetDetailPanelController.isVisible || folderStackPanelController.isVisible
    }

    public var showsMenuBarIcon: Bool {
        settings.showMenuBarIcon
    }

    // The executable target needs only command enablement, not the full
    // DockingSettings value. Keeping these as narrow public booleans preserves
    // the package boundary while still letting the native menu reflect widget
    // availability.
    public var canOpenCalendarPanel: Bool {
        settings.calendarEnabled
    }

    public var canOpenWeatherPanel: Bool {
        settings.weatherEnabled
    }

    public var appPreferredColorScheme: ColorScheme? {
        settings.theme.colorScheme
    }

    public var appAccentColor: Color {
        settings.accentColor
    }

    var availableDisplays: [DisplaySummary] {
        ScreenPlacementService.availableDisplays()
    }

    init(
        settingsStore: SettingsStore = SettingsStore(),
        appListStore: AppListStore = AppListStore(),
        calendarViewModel: CalendarWidgetViewModel? = nil,
        weatherViewModel: WeatherWidgetViewModel? = nil
    ) {
        self.settingsStore = settingsStore
        self.appListStore = appListStore
        self.settings = settingsStore.load()
        self.dockItems = appListStore.load()
        // The widget view models are MainActor-bound because they publish
        // SwiftUI state. Creating the defaults inside the initializer, instead
        // of as default argument expressions, keeps Swift's concurrency model
        // honest: default arguments are evaluated from the caller context and
        // would otherwise look like nonisolated UI object construction.
        self.calendarViewModel = calendarViewModel ?? CalendarWidgetViewModel(provider: EventKitCalendarProvider())
        self.weatherViewModel = weatherViewModel ?? WeatherWidgetViewModel(provider: Self.defaultWeatherProvider())
    }

    private static func defaultWeatherProvider() -> WeatherProvider {
        let sharedLocationProvider = CoreLocationProvider()
        // WeatherKit is the product-preferred provider only for builds that
        // Apple has explicitly provisioned for the WeatherKit entitlement. A
        // locally cloned SwiftPM build, or a copy shared without that signed
        // provisioning profile, cannot make WeatherKit work merely because this
        // code imports WeatherKit.framework. Keeping Open-Meteo as the fallback
        // is therefore not just a developer convenience: it is the normal
        // real-data path for users who run an unsigned/local build, while a
        // properly signed distribution can still take the Apple path first.
        return CompositeWeatherProvider(
            primary: WeatherKitProvider(locationProvider: sharedLocationProvider),
            fallback: OpenMeteoWeatherProvider(locationProvider: sharedLocationProvider)
        )
    }

    public func start() {
        guard !hasStarted else {
            return
        }
        hasStarted = true

        runningObserver.onChange = { [weak self] snapshot in
            guard let self else {
                return
            }
            self.clearCompletedTerminationRequests(runningItems: snapshot.runningItems)
            self.runningBundleIDs = snapshot.runningBundleIDs
            self.runningAppItems = snapshot.runningItems
            self.activeBundleID = snapshot.activeBundleID
            self.activeProcessIdentifier = snapshot.activeProcessIdentifier
        }
        runningObserver.start()
        installEnvironmentObservers()
        syncLaunchAtLoginState()
        syncRestoreStatus()
        restoreStatusMessage = defaultRestoreStatusMessage()
        appleDockVisibilityStatusMessage = AppleDockPreferences.visibilityStatusText()
        dockPanelController.show(model: self)
        applySettingsToWindows()

        Task {
            await calendarViewModel.refreshIfNeeded(settings: settings)
            await weatherViewModel.refreshIfNeeded(settings: settings)
        }
    }

    public func showDock() {
        holdsDockAfterExplicitShow = true
        dockPanelController.show(model: self)
    }

    public func openCalendarPanel() {
        guard settings.calendarEnabled else {
            return
        }
        toggleWidgetPanel(.calendar)
    }

    public func openWeatherPanel() {
        guard settings.weatherEnabled else {
            return
        }
        toggleWidgetPanel(.weather)
    }

    public func hideDock() {
        holdsDockAfterExplicitShow = false
        dockPanelController.hide()
    }

    func toggleDock() {
        // There is no separate hidden-state source of truth because the NSPanel
        // can be hidden by auto-hide and external app lifecycle events. Ordering
        // the panel front is idempotent and keeps menu actions predictable.
        showDock()
    }

    func pointerEnteredDock() {
        isPointerInsideDock = true
        holdsDockAfterExplicitShow = false
        dockPanelController.show(model: self)
    }

    func pointerExitedDock() {
        isPointerInsideDock = false
        holdsDockAfterExplicitShow = false
        guard !isDockAnchoredPanelVisible else {
            return
        }
        dockPanelController.scheduleAutoHide(model: self)
    }

    func icon(for item: DockItem) -> NSImage {
        iconCache.icon(for: item)
    }

    func launch(_ item: DockItem) {
        guard !isTerminationPending(item) else {
            // Quit is asynchronous and some resident apps briefly relaunch or
            // keep helper-driven state alive after accepting the request. A
            // second click during that handoff should not be interpreted as a
            // fresh Open command, because that is exactly how the user ends up
            // with "it closed, then immediately opened again." We ignore only
            // the short reconciliation window; if the app is still running
            // afterwards, Docking shows the real state again and the user can
            // choose Open/Force Quit intentionally.
            DockingLog.dock.notice("Open ignored because \(item.title) is reconciling a Quit request.")
            return
        }

        appLauncherService.open(item)
    }

    func isRunning(_ item: DockItem) -> Bool {
        guard item.isApplication else {
            return false
        }

        if let runningProcessIdentifier = item.runningProcessIdentifier {
            return runningAppItems.contains { runningItem in
                runningItem.runningProcessIdentifier == runningProcessIdentifier
            }
        }

        if let bundleIdentifier = item.bundleIdentifier {
            return runningBundleIDs.contains(bundleIdentifier)
        }

        // SwiftUI asks this during view rendering. Use the observer's cached
        // snapshot instead of querying NSWorkspace from every dock item body;
        // process discovery remains event-driven, while path-only apps still
        // get correct running-state and context-menu actions.
        return runningAppItems.contains { runningItem in
            RunningApplicationMatcher.matches(
                item: item,
                applicationBundleIdentifier: runningItem.bundleIdentifier,
                applicationBundleURL: runningItem.url
            )
        }
    }

    func isActive(_ item: DockItem) -> Bool {
        guard item.isApplication,
              !isTerminationPending(item) else {
            return false
        }
        if let runningProcessIdentifier = item.runningProcessIdentifier {
            return runningProcessIdentifier == activeProcessIdentifier
        }
        return item.bundleIdentifier == activeBundleID
    }

    func isTerminationPending(_ item: DockItem) -> Bool {
        // Process keys let a rebuilt transient running item continue to show
        // pending state after an NSWorkspace refresh; item IDs let a durable
        // pinned icon remember that it initiated the request even though it has
        // no pid of its own. Using both avoids two tempting but wrong shortcuts:
        // bundle-wide pending would block a sibling Ghostty instance, while
        // pid-only pending would leave the pinned icon clickable during the
        // exact shutdown window that triggered this bug.
        terminationPendingItemIDs.contains(item.id) ||
        DockTerminationState.isPending(item, pendingKeys: terminationPendingItemKeys)
    }

    func showAllWindows(_ item: DockItem) {
        appLauncherService.showAllWindows(item)
    }

    func hideApplication(_ item: DockItem) {
        appLauncherService.hide(item)
    }

    func quit(_ item: DockItem) {
        let requestedProcessIdentifiers = appLauncherService.quit(item)
        if !requestedProcessIdentifiers.isEmpty {
            markTerminationPending(item, processIdentifiers: requestedProcessIdentifiers)
        }
    }

    func forceQuit(_ item: DockItem) {
        let requestedProcessIdentifiers = appLauncherService.forceQuit(item)
        if !requestedProcessIdentifiers.isEmpty {
            markTerminationPending(item, processIdentifiers: requestedProcessIdentifiers)
        }
    }

    private func markTerminationPending(_ item: DockItem, processIdentifiers: [pid_t]) {
        let keys = processIdentifiers.compactMap { processIdentifier in
            DockTerminationState.identityKey(for: item, processIdentifier: processIdentifier)
        }
        let pendingKeys = Set(keys)

        guard !pendingKeys.isEmpty else {
            markTerminationPending(item)
            return
        }

        // The standard Dock treats duplicate regular app instances as separate
        // icons. Pending state therefore follows the process(es) AppKit actually
        // accepted a Quit/Force Quit request for, instead of the durable app
        // identity used by pinned items. The fallback below exists for unusual
        // LaunchServices cases where AppKit cannot report a pid, but the normal
        // path is per-process so a sibling Ghostty/Calculator icon remains
        // visible and independently actionable.
        rememberTerminationRequest(from: item, keys: pendingKeys)
        for key in pendingKeys {
            scheduleTerminationReconciliation(for: key)
        }
        terminationPendingItemKeys.formUnion(pendingKeys)
    }

    private func markTerminationPending(_ item: DockItem) {
        guard let key = DockTerminationState.identityKey(for: item) else {
            runningObserver.refresh()
            return
        }

        scheduleTerminationReconciliation(for: key)
        rememberTerminationRequest(from: item, keys: [key])
        terminationPendingItemKeys.insert(key)
    }

    private func rememberTerminationRequest(from item: DockItem, keys: Set<String>) {
        guard !keys.isEmpty else {
            return
        }

        terminationPendingItemIDs.insert(item.id)
        terminationPendingKeysByItemID[item.id, default: []].formUnion(keys)
    }

    private func scheduleTerminationReconciliation(for key: String) {
        terminationReconciliationTasks[key]?.cancel()
        terminationReconciliationTasks[key] = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: Self.terminationObservationDelayNanoseconds)
            } catch {
                return
            }

            guard let self else {
                return
            }

            // Notion Calendar demonstrates why termination needs an explicit
            // post-request refresh: its normal AppKit termination request can
            // change the same pid from a regular Dock-visible app to an
            // accessory resident process, which does not necessarily produce a
            // didTerminate notification. A short one-shot refresh catches that
            // policy change without polling indefinitely or force-killing the
            // resident app. If the refresh proves the process disappeared, the
            // onChange path below cancels this task before the final timeout.
            self.runningObserver.refresh()

            do {
                try await Task.sleep(
                    nanoseconds: Self.terminationReconciliationDelayNanoseconds -
                    Self.terminationObservationDelayNanoseconds
                )
            } catch {
                return
            }

            // A clean Quit is a request, not a kill. Electron-style resident
            // apps can acknowledge it and then rebuild their foreground
            // process, while terminal apps can take a moment to close sessions.
            // Holding the pending state forever would make Docking lie about an
            // app that intentionally stayed alive; clearing it immediately
            // would let the next click relaunch during the shutdown handoff.
            // This short reconciliation window blocks accidental re-open, then
            // refreshes from NSWorkspace so the dock settles on the actual
            // process state instead of our optimistic request state.
            self.clearTerminationPendingKey(key)
            self.runningObserver.refresh()
        }
    }

    private func clearCompletedTerminationRequests(runningItems: [DockItem]) {
        let completedKeys = DockTerminationState.completedPendingKeys(
            pendingKeys: terminationPendingItemKeys,
            runningItems: runningItems
        )
        guard !completedKeys.isEmpty else {
            return
        }

        for key in completedKeys {
            terminationReconciliationTasks[key]?.cancel()
        }
        for key in completedKeys {
            clearTerminationPendingKey(key)
        }
    }

    private func clearTerminationPendingKey(_ key: String) {
        terminationReconciliationTasks[key] = nil
        terminationPendingItemKeys.remove(key)

        let trackedItemIDs = Array(terminationPendingKeysByItemID.keys)
        for itemID in trackedItemIDs {
            guard let keys = terminationPendingKeysByItemID[itemID] else {
                continue
            }
            let remainingKeys = keys.subtracting([key])
            if remainingKeys.isEmpty {
                terminationPendingKeysByItemID[itemID] = nil
                terminationPendingItemIDs.remove(itemID)
            } else {
                terminationPendingKeysByItemID[itemID] = remainingKeys
            }
        }
    }

    func showInFinder(_ item: DockItem) {
        appLauncherService.showInFinder(item)
    }

    func addDockItem() {
        guard let item = appCatalogService.chooseDockItem() else {
            return
        }
        insertDockItemIfNeeded(item)
    }

    func addDockItem(fromDroppedURL url: URL, before target: DockItem? = nil) {
        guard let item = AppCatalogService.dockItemIfSupported(for: url) else {
            return
        }
        insertDockItemIfNeeded(item, before: target)
    }

    func dropFile(_ url: URL, onto item: DockItem) {
        if item.isFolder {
            dropFile(url, ontoFolder: item)
            return
        }

        guard item.isApplication else {
            return
        }

        if AppCatalogService.dockItemIfSupported(for: url) != nil {
            // A dragged app bundle or directory is still a Docking item being
            // placed near another item. Treating every file URL on an app icon
            // as an app input would make adding folders/apps by drag feel
            // unpredictable and would diverge from the existing Docking model.
            addDockItem(fromDroppedURL: url, before: item)
        } else {
            // Ordinary documents dropped onto an app icon follow the macOS Dock
            // contract: open this document with that app. This path is separate
            // from `addDockItem` because Docking intentionally does not keep
            // arbitrary documents as permanent dock items yet.
            appLauncherService.openFile(url, with: item)
        }
    }

    func dropFile(_ url: URL, ontoFolder item: DockItem) {
        // A drop directly on a Dock folder should behave like dropping onto a
        // Finder folder proxy. We keep this separate from `addDockItem` because
        // the two gestures look similar in SwiftUI, but one mutates the
        // Docking item list while the other mutates the user's filesystem.
        guard item.isFolder, let targetFolderURL = item.url else {
            return
        }

        do {
            _ = try FolderDropService.performDrop(sourceURL: url, into: targetFolderURL)
        } catch {
            presentFolderDropFailure(error, sourceURL: url, target: item)
        }
    }

    func remove(_ item: DockItem) {
        if item.isFolder {
            folderStackPanelController.close()
        }
        dockItems.removeAll { $0.id == item.id }
    }

    func pinRunningItem(_ item: DockItem) {
        insertDockItemIfNeeded(
            DockItem(
                kind: .application,
                title: item.title,
                bundleIdentifier: item.bundleIdentifier,
                url: item.url,
                iconCacheKey: item.iconCacheKey,
                isPinned: true
            )
        )
    }

    func moveDockItem(from source: IndexSet, to destination: Int) {
        dockItems.move(fromOffsets: source, toOffset: destination)
    }

    func moveDockItem(_ item: DockItem, by offset: Int) {
        guard let sourceIndex = dockItems.firstIndex(where: { $0.id == item.id }) else {
            return
        }

        let destinationIndex = min(max(sourceIndex + offset, 0), dockItems.count - 1)
        guard sourceIndex != destinationIndex else {
            return
        }

        // This helper backs explicit up/down buttons in Control Center. We keep
        // it separate from SwiftUI's `move(fromOffsets:toOffset:)` because that
        // API uses insertion indexes after removal, which is easy to misuse from
        // per-row buttons and would make a one-step move skip rows. Direct
        // remove/insert preserves the user's visible row order exactly.
        let moved = dockItems.remove(at: sourceIndex)
        dockItems.insert(moved, at: destinationIndex)
    }

    func moveDockItem(_ item: DockItem, before target: DockItem) {
        guard item.id != target.id,
              let from = dockItems.firstIndex(where: { $0.id == item.id }),
              let to = dockItems.firstIndex(where: { $0.id == target.id }) else {
            return
        }

        let moved = dockItems.remove(at: from)
        let adjustedIndex = from < to ? to - 1 : to
        dockItems.insert(moved, at: adjustedIndex)
    }

    func resetAppList() {
        dockItems = AppListStore.defaultItems()
        iconCache.clear()
    }

    private func updateDockItem(_ item: DockItem, update: (inout DockItem) -> Void) {
        guard let index = dockItems.firstIndex(where: { $0.id == item.id }) else {
            return
        }

        // DockItem carries user-facing per-item preferences now, not only app
        // identity. Updating in place preserves order, UUID, drag targets, and
        // Control Center row identity while still letting AppListStore persist
        // the new folder stack choice through the normal @Published didSet.
        update(&dockItems[index])
    }

    private func insertDockItemIfNeeded(_ item: DockItem, before target: DockItem? = nil) {
        guard !dockItems.contains(where: { $0.identityKey == item.identityKey }) else {
            return
        }

        if let target, let targetIndex = dockItems.firstIndex(where: { $0.id == target.id }) {
            dockItems.insert(item, at: targetIndex)
        } else {
            dockItems.append(item)
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try launchAtLoginService.setEnabled(enabled)
            settings.launchAtLogin = launchAtLoginService.isEnabled
            launchAtLoginStatusMessage = settings.launchAtLogin
                ? "Docking will open at login."
                : "Docking will not open at login."
        } catch {
            settings.launchAtLogin = launchAtLoginService.isEnabled
            launchAtLoginStatusMessage = error.localizedDescription
        }
    }

    func matchAppleDockVisibility() {
        settings.dockVisibility = AppleDockPreferences.visibilityMode()
        appleDockVisibilityStatusMessage = AppleDockPreferences.visibilityStatusText()
    }

    func toggleWidgetPanel(_ kind: DockWidgetKind) {
        switch kind {
        case .calendar:
            Task { await calendarViewModel.refresh(settings: settings, reason: "panel-open") }
        case .weather:
            Task { await weatherViewModel.refresh(settings: settings, force: false) }
        }

        widgetDetailPanelController.toggle(
            kind: kind,
            model: self,
            dockFrame: dockPanelController.frame,
            anchorFrame: widgetFrames[kind],
            onClose: { [weak self] in
                guard let self else {
                    return
                }
                if self.settings.dockVisibility == .autoHide,
                   !self.isPointerInsideDock,
                   !self.holdsDockAfterExplicitShow,
                   !self.isDockAnchoredPanelVisible {
                    self.dockPanelController.scheduleAutoHide(model: self)
                }
            }
        )
        if widgetDetailPanelController.isVisible {
            // A widget detail panel is anchored to the Dock. Keeping the Dock
            // visible while the panel is open preserves the user's path back to
            // the same widget, which is the intended close control. Letting
            // auto-hide order the Dock out underneath the panel made the
            // "click the widget again" behavior depend on timing.
            dockPanelController.cancelScheduledAutoHide()
        }
    }

    func toggleFolderStack(_ item: DockItem) {
        guard item.isFolder else {
            launch(item)
            return
        }

        folderStackPanelController.toggle(
            item: item,
            model: self,
            dockFrame: dockPanelController.frame,
            anchorFrame: dockItemFrames[item.id],
            onClose: { [weak self] in
                guard let self else {
                    return
                }
                if self.settings.dockVisibility == .autoHide,
                   !self.isPointerInsideDock,
                   !self.holdsDockAfterExplicitShow,
                   !self.isDockAnchoredPanelVisible {
                    self.dockPanelController.scheduleAutoHide(model: self)
                }
            }
        )

        if folderStackPanelController.isVisible {
            // Folder stacks are Dock-attached panels just like widgets. Hiding
            // the dock while the stack is visible would remove the user's
            // source control for the open panel and break the standard "click
            // the same dock item again to close" interaction.
            dockPanelController.cancelScheduledAutoHide()
        }
    }

    func openFolderStackEntry(_ entry: FolderStackEntry) {
        NSWorkspace.shared.open(entry.url)
        folderStackPanelController.close()
    }

    func showFolderStackEntryInFinder(_ entry: FolderStackEntry) {
        NSWorkspace.shared.activateFileViewerSelecting([entry.url])
        folderStackPanelController.close()
    }

    func openFolderInFinderFromStack(_ item: DockItem) {
        launch(item)
        folderStackPanelController.close()
    }

    func updateFolderDisplayMode(_ mode: DockFolderDisplayMode, for item: DockItem) {
        updateDockItem(item) { dockItem in
            dockItem.folderDisplayMode = mode
        }
        iconCache.clear()
    }

    func updateFolderViewMode(_ mode: DockFolderViewMode, for item: DockItem) {
        updateDockItem(item) { dockItem in
            dockItem.folderViewMode = mode
        }
    }

    func updateFolderSortMode(_ mode: DockFolderSortMode, for item: DockItem) {
        updateDockItem(item) { dockItem in
            dockItem.folderSortMode = mode
        }
        iconCache.clear()
    }

    private func presentFolderDropFailure(_ error: Error, sourceURL: URL, target: DockItem) {
        // Successful Dock folder drops should stay lightweight and non-modal, as
        // in Finder. Failures are different: silently losing a file operation is
        // worse than briefly activating Docking, so we show a plain AppKit alert
        // only when the filesystem rejected the operation.
        let alert = NSAlert()
        alert.messageText = "Could not add \(sourceURL.lastPathComponent) to \(target.title)"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    func updateWidgetFrame(kind: DockWidgetKind, frame: NSRect) {
        // This frame is runtime geometry, not user-visible state. Keeping it out
        // of @Published storage avoids re-rendering the dock every time AppKit
        // reports the same widget position during layout.
        widgetFrames[kind] = frame
    }

    func updateDockItemFrame(itemID: UUID, frame: NSRect) {
        dockItemFrames[itemID] = frame
    }

    public func openControlCenterWindow() {
        controlCenterSelection = .general
        showControlCenterWindow()
    }

    private func showControlCenterWindow() {
        let rootView = ControlCenterView()
            .environmentObject(self)
            .preferredColorScheme(appPreferredColorScheme)
            .tint(appAccentColor)

        if let controlCenterWindow {
            controlCenterWindow.contentView = NSHostingView(rootView: rootView)
            NSApp.activate(ignoringOtherApps: true)
            controlCenterWindow.makeKeyAndOrderFront(nil)
            return
        }

        if let existingWindow = NSApp.windows.first(where: { $0.title == "Docking" }) {
            existingWindow.contentView = NSHostingView(rootView: rootView)
            NSApp.activate(ignoringOtherApps: true)
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }

        // The main Docking window is the single settings/control surface. We
        // still keep this AppKit fallback because status-item and dock-context
        // menu actions can fire after the SwiftUI WindowGroup has been closed,
        // and those AppKit entry points cannot directly call SwiftUI's
        // openWindow environment action. The fallback recreates the same
        // ControlCenterView instead of introducing a second configuration UI.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Docking"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: rootView)
        window.center()
        controlCenterWindow = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func restoreOriginalDockSettings() {
        do {
            let result = try restoreService.restoreIfSnapshotExists()
            settings.dockReplacementModeEnabled = false
            restoreStatusMessage = result.userMessage
            syncRestoreStatus()
        } catch {
            restoreStatusMessage = "Docking could not restore Dock settings automatically. \(error.localizedDescription)"
            syncRestoreStatus()
        }
    }

    func enableDockReplacementMode() {
        do {
            let result = try restoreService.enableReplacementMode()
            settings.dockReplacementModeEnabled = true
            settings.showOnAllSpaces = true
            settings.showOnFullScreenSpaces = true
            matchOriginalAppleDockLayout(updateStatus: false)
            applySettingsToWindows()
            restoreStatusMessage = "\(result.userMessage) Docking also matched the saved Apple Dock layout and pinned apps where they were readable."
            syncRestoreStatus()
        } catch {
            restoreStatusMessage = "Docking could not enable primary dock mode. \(error.localizedDescription)"
            syncRestoreStatus()
        }
    }

    func matchOriginalAppleDockLayout(updateStatus: Bool = true) {
        var mirroredSettings = settings
        let didApplyPreferences = AppleDockPreferences.mirrorOriginalDock(
            into: &mirroredSettings,
            savedValues: restoreService.savedDockPreferenceValues()
        )

        // The Apple Dock item list is not changed by primary mode, so it
        // remains the best source for reproducing the user's original pinned
        // apps and folder stacks even after Docking has pushed Apple Dock into
        // strong auto-hide.
        let mirroredItems = AppleDockPreferences.persistentDockItems()
        if !mirroredItems.isEmpty {
            dockItems = mirroredItems
        }

        mirroredSettings.dockReplacementModeEnabled = settings.dockReplacementModeEnabled
        mirroredSettings.showOnAllSpaces = true
        mirroredSettings.showOnFullScreenSpaces = true
        settings = mirroredSettings

        guard updateStatus else {
            return
        }

        if didApplyPreferences || !mirroredItems.isEmpty {
            restoreStatusMessage = "Docking matched the saved Apple Dock layout: \(mirroredItems.count) Dock items imported, with original visibility, position, and size applied where available."
        } else {
            restoreStatusMessage = "Docking could not read enough Apple Dock layout data to mirror it. Use the manual restore instructions if Apple Dock itself needs to be restored."
        }
    }

    func disableDockReplacementMode() {
        guard settings.dockReplacementModeEnabled else {
            restoreStatusMessage = "Replacement mode is not enabled. Docking is only showing its own overlay dock, so there is no replacement mode to disable."
            return
        }

        restoreOriginalDockSettings()
    }

    func reloadAppleDockToApplyPreferences() {
        do {
            restoreStatusMessage = try restoreService.reloadAppleDock().userMessage
        } catch {
            restoreStatusMessage = "Docking could not reload Apple Dock automatically. \(error.localizedDescription)"
        }
    }

    private func refreshWidgetsAfterSettingsChange(calendar: Bool, weather: Bool) {
        guard calendar || weather else {
            return
        }

        // Appearance and windowing preferences must not wake EventKit or the
        // weather provider. Those services can involve permission prompts,
        // network work, or synchronous framework calls, so only settings that
        // change the data request are allowed to trigger a refresh.
        Task {
            if calendar {
                await calendarViewModel.refreshIfNeeded(settings: settings)
            }
            if weather {
                await weatherViewModel.refreshIfNeeded(settings: settings)
            }
        }
    }

    private func handleDisabledWidgetsAfterSettingsChange() {
        if !settings.calendarEnabled {
            calendarViewModel.disable(settings: settings)
            widgetDetailPanelController.close(kind: .calendar)
        }
        if !settings.weatherEnabled {
            weatherViewModel.cancelRefresh()
            widgetDetailPanelController.close(kind: .weather)
        }
    }

    func flushPendingSettingsSave() {
        pendingSettingsSaveTask?.cancel()
        pendingSettingsSaveTask = nil
        settingsStore.save(settings)
    }

    private func scheduleSettingsSave() {
        let settingsToSave = settings
        pendingSettingsSaveTask?.cancel()

        // Control Center sliders can emit many intermediate values while the
        // user drags. Window updates should remain live, but writing every
        // transient value to UserDefaults would violate the resident-app
        // requirement to avoid needless disk churn. A short debounce keeps
        // persistence simple while preserving the final value the user sees.
        pendingSettingsSaveTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: Self.settingsSaveDelayNanoseconds)
            } catch {
                return
            }

            self?.settingsStore.save(settingsToSave)
            self?.pendingSettingsSaveTask = nil
        }
    }

    private func installEnvironmentObservers() {
        guard environmentObserverTokens.isEmpty else {
            return
        }

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        observe(workspaceCenter, name: NSWorkspace.didWakeNotification) { [weak self] in
            self?.handleWake()
        }
        observe(workspaceCenter, name: NSWorkspace.activeSpaceDidChangeNotification) { [weak self] in
            self?.handleDisplayEnvironmentChanged(shouldRestoreVisibleDock: false)
        }
        observe(NotificationCenter.default, name: NSApplication.didChangeScreenParametersNotification) { [weak self] in
            self?.handleDisplayEnvironmentChanged(shouldRestoreVisibleDock: true)
        }
    }

    private func observe(_ center: NotificationCenter, name: Notification.Name, handler: @escaping @MainActor () -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
            Task { @MainActor in
                handler()
            }
        }
        environmentObserverTokens.append((center, token))
    }

    private func handleWake() {
        handleDisplayEnvironmentChanged(shouldRestoreVisibleDock: true)
        Task {
            await calendarViewModel.refreshIfNeeded(settings: settings)
            await weatherViewModel.refreshIfNeeded(settings: settings)
        }
    }

    private func handleDisplayEnvironmentChanged(shouldRestoreVisibleDock: Bool) {
        // Sleep/wake, display attach/detach, and Space switches can leave
        // borderless panels with stale frames even though SwiftUI state did not
        // change. Re-applying the current settings is cheaper and simpler than
        // maintaining a parallel screen/Space model.
        runningObserver.refresh()
        applySettingsToWindows()

        guard shouldRestoreVisibleDock, settings.dockVisibility == .alwaysVisible else {
            return
        }

        // Only the "always visible" mode is restored to the front. Auto-hide
        // users may intentionally leave the dock hidden until they hit the edge
        // trigger, so forcing it open on every Space change would feel noisy.
        showDock()
    }

    private func applySettingsToWindows() {
        dockPanelController.applySettings(
            settings,
            itemCount: visibleAppItemCount,
            hasSeparatedRunningItems: hasSeparatedRunningItems
        )
        switch settings.dockVisibility {
        case .autoHide:
            // Auto-hide is a real visibility mode, not a second checkbox layered
            // on top of "always visible". Once selected, the dock should rest
            // hidden and be revived by the edge trigger, matching standard Dock
            // behavior and avoiding a resident overlay that covers workspace
            // content immediately after launch.
            if !isPointerInsideDock && !holdsDockAfterExplicitShow && !isDockAnchoredPanelVisible {
                dockPanelController.hide()
            }
        case .alwaysVisible:
            dockPanelController.orderFront()
        }
        // SwiftUI's MenuBarExtra is scene-declared and not a good fit for a
        // user-toggleable status item in this toolchain. AppKit's NSStatusItem
        // gives us exact create/remove control while leaving all app state in
        // the SwiftUI model.
        menuBarStatusController.update(isVisible: settings.showMenuBarIcon, model: self)
    }

    private func syncLaunchAtLoginState() {
        let actualState = launchAtLoginService.isEnabled
        if settings.launchAtLogin != actualState {
            // UserDefaults records the user's last saved setting, but
            // ServiceManagement is authoritative. Syncing on launch prevents a
            // stale checkbox after the user changes Login Items in System
            // Settings or after registration fails for an unsigned dev bundle.
            settings.launchAtLogin = actualState
        }
    }

    private func syncRestoreStatus() {
        dockRestoreStatus = restoreService.restoreStatus()
        manualRestoreInstructions = restoreService.manualRestoreInstructions().text
    }

    private func defaultRestoreStatusMessage() -> String {
        if settings.dockReplacementModeEnabled {
            return "Docking primary dock mode is enabled. Apple Dock settings can be restored from the Restore section."
        }

        return dockRestoreStatus.hasSnapshot
            ? "A saved Apple Dock snapshot is available. Restore Apple Dock or match the saved layout into Docking if the current setup does not look right."
            : "Docking is currently overlay-only and has not changed Apple Dock settings."
    }
}
