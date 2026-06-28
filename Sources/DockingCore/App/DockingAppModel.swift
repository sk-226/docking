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
    @Published var activeBundleID: String?
    @Published var isPointerInsideDock = false
    @Published var restoreStatusMessage: String = "Docking is currently overlay-only and has not changed Apple Dock settings."
    @Published var dockRestoreStatus = DockRestoreStatus(snapshotCreatedAt: nil, snapshotAppVersion: nil, savedPreferenceCount: 0)
    @Published var launchAtLoginStatusMessage: String = "Launch at login uses macOS Login Items when enabled."
    @Published var appleDockVisibilityStatusMessage: String = AppleDockPreferences.visibilityStatusText()
    @Published var controlCenterSelection: ControlCenterSection = .overview
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
    private let restoreService = DockSettingsRestoreService()
    private let launchAtLoginService = LaunchAtLoginService()
    private let menuBarStatusController = MenuBarStatusController()
    private var controlCenterWindow: NSWindow?
    private var hasStarted = false
    private var environmentObserverTokens: [(NotificationCenter, NSObjectProtocol)] = []
    private var pendingSettingsSaveTask: Task<Void, Never>?
    private var widgetFrames: [DockWidgetKind: NSRect] = [:]
    // Auto-hide should hide after pointer exit, but an explicit Show Dock
    // button/menu command is different from a passive edge reveal. The user has
    // asked to see the dock, so a previously scheduled hide must not win while
    // they are still moving from Control Center or the menu toward the dock.
    // This flag is cleared as soon as the pointer actually enters or exits the
    // dock region, returning control to the normal auto-hide lifecycle.
    private var holdsDockAfterExplicitShow = false
    private static let settingsSaveDelayNanoseconds: UInt64 = 350_000_000

    var enabledWidgetCount: Int {
        (settings.calendarEnabled ? 1 : 0) + (settings.weatherEnabled ? 1 : 0)
    }

    var unpinnedRunningItems: [DockItem] {
        DockRunningItemResolver.unpinnedRunningItems(
            pinnedItems: dockItems,
            runningItems: runningAppItems,
            visibility: settings.unpinnedRunningAppVisibility
        )
    }

    var visibleAppItemCount: Int {
        dockItems.count + unpinnedRunningItems.count
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
        // WeatherKit is the product-preferred provider, but personal unsigned
        // SwiftPM app bundles often lack the entitlement needed for it. The
        // fallback preserves a real-data path without ever showing mock weather
        // in production.
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
            self?.runningBundleIDs = snapshot.runningBundleIDs
            self?.runningAppItems = snapshot.runningItems
            self?.activeBundleID = snapshot.activeBundleID
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
        guard !widgetDetailPanelController.isVisible else {
            return
        }
        dockPanelController.scheduleAutoHide(model: self)
    }

    func icon(for item: DockItem) -> NSImage {
        iconCache.icon(for: item)
    }

    func launch(_ item: DockItem) {
        appLauncherService.open(item)
    }

    func isRunning(_ item: DockItem) -> Bool {
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
                applicationBundleURL: runningItem.appURL
            )
        }
    }

    func showAllWindows(_ item: DockItem) {
        appLauncherService.showAllWindows(item)
    }

    func hideApplication(_ item: DockItem) {
        appLauncherService.hide(item)
    }

    func quit(_ item: DockItem) {
        appLauncherService.quit(item)
    }

    func forceQuit(_ item: DockItem) {
        appLauncherService.forceQuit(item)
    }

    func showInFinder(_ item: DockItem) {
        appLauncherService.showInFinder(item)
    }

    func addApplication() {
        guard let item = appCatalogService.chooseApplication() else {
            return
        }
        insertDockItemIfNeeded(item)
    }

    func addApplication(fromDroppedURL url: URL, before target: DockItem? = nil) {
        guard let item = AppCatalogService.dockItemIfApplication(for: url) else {
            return
        }
        insertDockItemIfNeeded(item, before: target)
    }

    func remove(_ item: DockItem) {
        dockItems.removeAll { $0.id == item.id }
    }

    func pinRunningItem(_ item: DockItem) {
        insertDockItemIfNeeded(
            DockItem(
                title: item.title,
                bundleIdentifier: item.bundleIdentifier,
                appURL: item.appURL,
                iconCacheKey: item.iconCacheKey,
                isPinned: true
            )
        )
    }

    func moveDockItem(from source: IndexSet, to destination: Int) {
        dockItems.move(fromOffsets: source, toOffset: destination)
    }

    func moveDockItem(_ item: DockItem, by offset: Int) {
        guard let sourceIndex = dockItems.firstIndex(of: item) else {
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
        guard item != target,
              let from = dockItems.firstIndex(of: item),
              let to = dockItems.firstIndex(of: target) else {
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

    private func insertDockItemIfNeeded(_ item: DockItem, before target: DockItem? = nil) {
        guard !dockItems.contains(where: { $0.bundleIdentifier == item.bundleIdentifier && $0.appURL == item.appURL }) else {
            return
        }

        if let target, let targetIndex = dockItems.firstIndex(of: target) {
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
                   !self.holdsDockAfterExplicitShow {
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

    func updateWidgetFrame(kind: DockWidgetKind, frame: NSRect) {
        // This frame is runtime geometry, not user-visible state. Keeping it out
        // of @Published storage avoids re-rendering the dock every time AppKit
        // reports the same widget position during layout.
        widgetFrames[kind] = frame
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

        // The Apple Dock app list is not changed by primary mode, so it remains
        // the best source for reproducing the user's original pinned apps even
        // after Docking has already pushed Apple Dock into strong auto-hide.
        let mirroredItems = AppleDockPreferences.persistentAppItems()
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
            restoreStatusMessage = "Docking matched the saved Apple Dock layout: \(mirroredItems.count) pinned apps imported, with original visibility, position, and size applied where available."
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
        dockPanelController.applySettings(settings, itemCount: visibleAppItemCount, widgetCount: enabledWidgetCount)
        switch settings.dockVisibility {
        case .autoHide:
            // Auto-hide is a real visibility mode, not a second checkbox layered
            // on top of "always visible". Once selected, the dock should rest
            // hidden and be revived by the edge trigger, matching standard Dock
            // behavior and avoiding a resident overlay that covers workspace
            // content immediately after launch.
            if !isPointerInsideDock && !holdsDockAfterExplicitShow && !widgetDetailPanelController.isVisible {
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
