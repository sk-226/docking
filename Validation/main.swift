import AppKit
import Foundation
@testable import DockingCore

struct ValidationFailure: Error, CustomStringConvertible {
    var description: String
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else {
        throw ValidationFailure(description: message)
    }
}

func validateFormatters() throws {
    let start = Date(timeIntervalSince1970: 0)
    let end = start.addingTimeInterval(100 * 60)
    try expect(DockingFormatters.durationString(from: start, to: end) == "1 hr 40 min", "duration formatter should use compact hour/minute output")

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
    try expect(DockingFormatters.sectionTitle(for: now, calendar: calendar, now: now) == "Today", "today section title should be stable")
    try expect(DockingFormatters.sectionTitle(for: tomorrow, calendar: calendar, now: now) == "Tomorrow", "tomorrow section title should be stable")
}

func validateCalendarGrouping() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let day = Date(timeIntervalSince1970: 1_700_000_000)
    let later = day.addingTimeInterval(3_600)
    let earlier = day.addingTimeInterval(600)
    let events = [
        CalendarEventSummary(id: "later", title: "Later", calendarName: "Work", startDate: later, endDate: later.addingTimeInterval(1_800), location: nil),
        CalendarEventSummary(id: "earlier", title: "Earlier", calendarName: "Work", startDate: earlier, endDate: earlier.addingTimeInterval(1_800), location: nil)
    ]

    let grouped = CalendarGrouping.groupEvents(events, calendar: calendar)
    try expect(grouped.count == 1, "events on the same day should share one section")
    try expect(grouped[0].events.map(\.id) == ["earlier", "later"], "events should sort by start time inside each section")
}

func validateDockLayout() throws {
    let settings = DockingSettings.default
    let appOnly = DockLayout.panelSize(itemCount: 3, widgetCount: 0, settings: settings)
    let withWidgets = DockLayout.panelSize(itemCount: 3, widgetCount: 2, settings: settings)
    try expect(withWidgets.width > appOnly.width, "dock width should grow when widgets are enabled")
    try expect(appOnly.height == settings.dockSize, "dock height should follow settings")

    var verticalSettings = settings
    verticalSettings.dockPosition = .left
    let vertical = DockLayout.panelSize(itemCount: 3, widgetCount: 2, settings: verticalSettings)
    try expect(vertical.width == settings.dockSize, "vertical dock width should use dock size as thickness")
    try expect(vertical.height > vertical.width, "vertical dock should put items on the long vertical axis")
}

func validateDetailPanelAnchoring() throws {
    guard let screen = NSScreen.main ?? NSScreen.screens.first else {
        // The product is a macOS GUI app, so a screen normally exists. Keeping
        // this validation non-fatal lets package checks still run in unusual
        // headless contexts while the app build remains the real AppKit gate.
        print("SKIP detail panel anchoring (no screen)")
        return
    }

    let visible = screen.visibleFrame
    let dockFrame = NSRect(x: visible.midX - 220, y: visible.minY + 10, width: 440, height: 72)
    let anchorFrame = NSRect(x: dockFrame.maxX - 96, y: dockFrame.minY + 8, width: 58, height: 58)
    let detailFrame = ScreenPlacementService.detailFrame(
        size: CGSize(width: 280, height: 200),
        dockFrame: dockFrame,
        anchorFrame: anchorFrame,
        on: screen
    )

    try expect(abs(detailFrame.midX - anchorFrame.midX) < 1, "detail panel should center on the widget anchor when there is room")
    try expect(detailFrame.minY > dockFrame.maxY, "detail panel should open above the dock")
}

func validateSpecificDisplaySelection() throws {
    guard let display = ScreenPlacementService.availableDisplays().first else {
        print("SKIP specific display selection (no display)")
        return
    }

    var settings = DockingSettings.default
    settings.displayMode = .specific
    settings.dockDisplayID = display.id

    let frame = ScreenPlacementService.dockFrame(
        size: CGSize(width: 320, height: 72),
        on: ScreenPlacementService.dockScreen(for: settings)
    )

    try expect(frame.width > 0, "specific display mode should resolve to a usable dock frame")
}

func validateDockPositionFrames() throws {
    guard let screen = NSScreen.main ?? NSScreen.screens.first else {
        print("SKIP dock position frames (no display)")
        return
    }

    let visible = screen.visibleFrame
    for position in DockPosition.allCases {
        var settings = DockingSettings.default
        settings.dockPosition = position
        let size = DockLayout.panelSize(itemCount: 4, widgetCount: 2, settings: settings)
        let frame = ScreenPlacementService.dockFrame(size: size, on: screen, position: position)

        try expect(visible.insetBy(dx: -0.5, dy: -0.5).contains(frame), "\(position.label) dock frame should stay inside the visible screen")

        if position.isVertical {
            try expect(frame.width == settings.dockSize, "\(position.label) dock should keep dock size as its thickness")
            try expect(frame.height > frame.width, "\(position.label) dock should be vertical")
        } else {
            try expect(frame.height == settings.dockSize, "\(position.label) dock should keep dock size as its height")
            try expect(frame.width > frame.height, "\(position.label) dock should be horizontal")
        }

        let trigger = ScreenPlacementService.edgeTriggerFrame(dockFrame: frame, position: position, on: screen)
        try expect(screen.frame.insetBy(dx: -0.5, dy: -0.5).contains(trigger), "\(position.label) auto-hide trigger should stay on the physical screen edge")

        switch position {
        case .bottomCenter, .bottomLeft, .bottomRight:
            // The trigger must touch the physical screen edge, not merely fit
            // inside visibleFrame. visibleFrame can be shifted by Apple's Dock,
            // which is exactly what made Docking's auto-hide reveal feel dead
            // when the standard Dock was still visible.
            try expect(abs(trigger.minY - screen.frame.minY) < 0.5, "\(position.label) auto-hide trigger should touch the bottom screen edge")
            try expect(trigger.height >= 4, "\(position.label) auto-hide trigger should have enough thickness to catch pointer entry")
        case .left:
            try expect(abs(trigger.minX - screen.frame.minX) < 0.5, "left auto-hide trigger should touch the left screen edge")
            try expect(trigger.width >= 4, "left auto-hide trigger should have enough thickness to catch pointer entry")
        case .right:
            try expect(abs(trigger.maxX - screen.frame.maxX) < 0.5, "right auto-hide trigger should touch the right screen edge")
            try expect(trigger.width >= 4, "right auto-hide trigger should have enough thickness to catch pointer entry")
        }
    }
}

func validateAppCatalogRecognizesOnlyApplicationBundles() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("AppCatalogValidation-\(UUID().uuidString)", isDirectory: true)
    let appURL = root.appendingPathComponent("Sample.app", isDirectory: true)
    let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
    let plainDirectoryURL = root.appendingPathComponent("NotAnApp", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: plainDirectoryURL, withIntermediateDirectories: true)

    let infoPlist = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>CFBundleIdentifier</key>
      <string>com.example.Sample</string>
      <key>CFBundleName</key>
      <string>Sample App</string>
    </dict>
    </plist>
    """
    try infoPlist.data(using: .utf8)?.write(to: contentsURL.appendingPathComponent("Info.plist"))

    let item = AppCatalogService.dockItemIfApplication(for: appURL)
    try expect(item?.bundleIdentifier == "com.example.Sample", "application bundle drops should preserve bundle identifier")
    try expect(item?.title == "Sample App", "application bundle drops should use bundle display metadata")
    try expect(AppCatalogService.dockItemIfApplication(for: plainDirectoryURL) == nil, "plain directory drops should not create dock items")
}

func validateSettingsStore() throws {
    let suiteName = "docking.validation.\(UUID().uuidString)"
    let dockSuiteName = "docking.validation.apple-dock.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    let appleDockDefaults = UserDefaults(suiteName: dockSuiteName)!
    defer {
        defaults.removePersistentDomain(forName: suiteName)
        appleDockDefaults.removePersistentDomain(forName: dockSuiteName)
    }

    appleDockDefaults.set(false, forKey: "autohide")
    let store = SettingsStore(defaults: defaults, appleDockDefaults: appleDockDefaults)
    try expect(store.load().dockVisibility == .alwaysVisible, "first-run settings should mirror visible Apple Dock")

    appleDockDefaults.set(true, forKey: "autohide")
    defaults.removePersistentDomain(forName: suiteName)
    try expect(store.load().dockVisibility == .autoHide, "first-run settings should mirror auto-hide Apple Dock")

    var settings = DockingSettings.default
    settings.dockVisibility = .alwaysVisible
    settings.widgetSize = 66
    store.save(settings)
    try expect(store.load() == settings, "settings should round-trip through UserDefaults")
}

func validateSettingsRefreshKeys() throws {
    var appearanceOnly = DockingSettings.default
    appearanceOnly.dockSize = 88
    appearanceOnly.iconSize = 60
    appearanceOnly.cornerRadius = 28
    appearanceOnly.opacity = 0.8
    appearanceOnly.dockPosition = .left
    appearanceOnly.calendarShowsLocation = false
    appearanceOnly.weatherShowsHumidity = false
    appearanceOnly.weatherShowsAQI = false

    try expect(appearanceOnly.calendarRefreshKey == DockingSettings.default.calendarRefreshKey, "appearance-only settings should not trigger calendar data refresh")
    try expect(appearanceOnly.weatherRefreshKey == DockingSettings.default.weatherRefreshKey, "appearance-only settings should not trigger weather data refresh")

    var calendarData = DockingSettings.default
    calendarData.calendarLookaheadDays = 14
    try expect(calendarData.calendarRefreshKey != DockingSettings.default.calendarRefreshKey, "calendar query settings should trigger calendar data refresh")

    var weatherData = DockingSettings.default
    weatherData.weatherManualLocation = "Tokyo"
    try expect(weatherData.weatherRefreshKey != DockingSettings.default.weatherRefreshKey, "weather request settings should trigger weather data refresh")
}

func validateDefaultSettingsFitEditableRanges() throws {
    let settings = DockingSettings.default

    try expect(DockingSettingLimits.autoHideDelay.contains(settings.autoHideDelay), "default auto-hide delay should be editable in Settings")
    try expect(DockingSettingLimits.dockSize.contains(settings.dockSize), "default dock size should be editable in Settings")
    try expect(DockingSettingLimits.iconSize.contains(settings.iconSize), "default icon size should be editable in Settings")
    try expect(DockingSettingLimits.widgetSize.contains(settings.widgetSize), "default widget size should be editable in Settings")
    try expect(DockingSettingLimits.spacing.contains(settings.spacing), "default spacing should be editable in Settings")
    try expect(DockingSettingLimits.cornerRadius.contains(settings.cornerRadius), "default corner radius should be editable in Settings")
    try expect(DockingSettingLimits.materialStrength.contains(settings.materialStrength), "default material strength should be editable in Settings")
    try expect(DockingSettingLimits.opacity.contains(settings.opacity), "default opacity should be editable in Settings")
    try expect(DockingSettingLimits.calendarLookaheadDays.contains(settings.calendarLookaheadDays), "default calendar lookahead should be editable in Settings")
    try expect(DockingSettingLimits.calendarMaxEventCount.contains(settings.calendarMaxEventCount), "default calendar max events should be editable in Settings")
    try expect(DockingSettingLimits.weatherRefreshIntervalMinutes.contains(settings.weatherRefreshIntervalMinutes), "default weather refresh interval should be editable in Settings")
    try expect(
        settings.weatherRefreshIntervalMinutes.isMultiple(of: DockingSettingLimits.weatherRefreshIntervalStep),
        "default weather refresh interval should align with the Settings stepper"
    )
}

func validateDockWidgetMetrics() throws {
    let persistedSmallSize = 44.0
    let editableMinimumSize = DockingSettingLimits.widgetSize.lowerBound

    for size in [persistedSmallSize, editableMinimumSize, DockingSettings.default.widgetSize] {
        let metrics = DockWidgetMetrics(size: size)

        // This guards the specific UI regression the user saw: when SwiftUI was
        // allowed to infer the widget's internal heights, the Calendar icon and
        // labels could occupy the same pixels at compact sizes. The invariant is
        // intentionally mechanical because screenshots are still the final UI
        // check, while this catches impossible geometry during fast validation.
        try expect(metrics.allocatedHeight <= size + 0.001, "compact widget layout should not over-allocate vertical space at \(size)pt")
        try expect(metrics.iconHeight > 0, "compact widget should always reserve an icon row")
        try expect(metrics.contentHeight > 0, "compact widget should always reserve a text content row")
        try expect(metrics.cornerRadius < size / 2, "compact widget corner radius should not collapse the rounded rectangle at \(size)pt")
    }
}

@MainActor
func validateSettingsPersistenceIsDebounced() async throws {
    let suiteName = "docking.validation.debounce.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let appListURL = FileManager.default.temporaryDirectory.appendingPathComponent("DockItemsValidation-\(UUID().uuidString).json")
    let weatherCacheURL = FileManager.default.temporaryDirectory.appendingPathComponent("WeatherCacheDebounceValidation-\(UUID().uuidString).json")
    defer {
        try? FileManager.default.removeItem(at: appListURL)
        try? FileManager.default.removeItem(at: weatherCacheURL)
    }

    let store = SettingsStore(defaults: defaults)
    let model = DockingAppModel(
        settingsStore: store,
        appListStore: AppListStore(fileURL: appListURL),
        calendarViewModel: CalendarWidgetViewModel(provider: EmptyCalendarProvider()),
        weatherViewModel: WeatherWidgetViewModel(
            provider: StaticWeatherProvider(snapshot: validationWeatherSnapshot()),
            cache: WeatherCache(fileURL: weatherCacheURL)
        )
    )

    var first = model.settings
    first.dockSize = 80
    model.settings = first

    var second = model.settings
    second.dockSize = 81
    model.settings = second

    try expect(store.load().dockSize == DockingSettings.default.dockSize, "settings should not persist every transient slider value immediately")
    try await Task.sleep(nanoseconds: 900_000_000)
    try expect(store.load().dockSize == 81, "debounced settings persistence should save the latest visible value")
}

@MainActor
func validateWidgetRefreshCancellation() async throws {
    let calendarViewModel = CalendarWidgetViewModel(provider: DelayedCalendarProvider())
    let calendarTask = Task {
        await calendarViewModel.refresh(settings: .default, reason: "validation")
    }
    try await Task.sleep(nanoseconds: 50_000_000)
    try expect(calendarViewModel.state == .loading, "calendar refresh should enter loading before cancellation")
    calendarViewModel.cancelRefresh()
    _ = await calendarTask.result
    try expect(calendarViewModel.state == .idle, "cancelled calendar refresh should not publish a late loaded/error state")

    let weatherCacheURL = FileManager.default.temporaryDirectory.appendingPathComponent("WeatherCancelValidation-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: weatherCacheURL) }

    let weatherViewModel = WeatherWidgetViewModel(
        provider: DelayedWeatherProvider(),
        cache: WeatherCache(fileURL: weatherCacheURL)
    )
    var weatherSettings = DockingSettings.default
    weatherSettings.weatherManualLocation = "Tokyo"
    let weatherTask = Task {
        await weatherViewModel.refresh(settings: weatherSettings, force: true)
    }
    try await Task.sleep(nanoseconds: 50_000_000)
    try expect(weatherViewModel.state == .loading, "weather refresh should enter loading before cancellation")
    weatherViewModel.cancelRefresh()
    _ = await weatherTask.result
    try expect(weatherViewModel.state == .idle, "cancelled weather refresh should not publish a late loaded/error state")
}

@MainActor
func validateWidgetTaskLifecycle() async throws {
    let calendarViewModel = CalendarWidgetViewModel(provider: CountingCalendarProvider())
    await calendarViewModel.refresh(settings: .default, reason: "validation-complete")
    try expect(!calendarViewModel.isRefreshing, "completed calendar refresh should release its task reference")

    await calendarViewModel.refreshAvailableCalendars(settings: .default)
    try expect(!calendarViewModel.isLoadingSources, "completed calendar source load should release its task reference")

    let weatherCacheURL = FileManager.default.temporaryDirectory.appendingPathComponent("WeatherLifecycleValidation-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: weatherCacheURL) }

    let weatherViewModel = WeatherWidgetViewModel(
        provider: StaticWeatherProvider(snapshot: validationWeatherSnapshot(locationName: "Lifecycle")),
        cache: WeatherCache(fileURL: weatherCacheURL)
    )
    var settings = DockingSettings.default
    settings.weatherManualLocation = "Tokyo"

    await weatherViewModel.refresh(settings: settings, force: true)
    try expect(!weatherViewModel.isRefreshing, "completed weather refresh should release its task reference")
}

@MainActor
func validateCalendarLaunchDoesNotRequestPermission() async throws {
    let provider = CountingCalendarProvider(authorizationState: .notDetermined)
    let viewModel = CalendarWidgetViewModel(provider: provider)

    await viewModel.refreshIfNeeded(settings: .default)

    try expect(provider.upcomingEventRequestCount == 0, "launch/stale calendar refresh should not request EventKit permission")
    try expect(provider.availableCalendarRequestCount == 0, "launch/stale calendar refresh should not enumerate calendars before permission")
}

@MainActor
func validateDisabledCalendarIgnoresStoreChanges() async throws {
    let provider = CountingCalendarProvider()
    let viewModel = CalendarWidgetViewModel(provider: provider)

    var disabledSettings = DockingSettings.default
    disabledSettings.calendarEnabled = false
    viewModel.disable(settings: disabledSettings)

    await viewModel.refresh(settings: disabledSettings, reason: "validation-disabled")
    try expect(provider.upcomingEventRequestCount == 0, "disabled calendar widget should ignore direct refresh calls")

    await viewModel.refreshAvailableCalendars(settings: disabledSettings)
    try expect(provider.availableCalendarRequestCount == 0, "disabled calendar widget should ignore calendar source refresh calls")

    NotificationCenter.default.post(name: provider.changeNotificationName, object: provider.changeNotificationObject)
    try await Task.sleep(nanoseconds: 100_000_000)

    try expect(provider.upcomingEventRequestCount == 0, "disabled calendar widget should ignore EventKit store-change notifications")
}

func validateAccentColorOptionsCoverDefault() throws {
    let rawValues = Set(DockingAccentColor.allCases.map(\.rawValue))
    try expect(rawValues.contains(DockingSettings.default.accentColorName), "default accent color should be a selectable option")
}

func validateWeatherCache() throws {
    let snapshot = WeatherSnapshot(
        locationName: "Tokyo",
        fetchedAt: Date(timeIntervalSince1970: 1_000),
        unit: .celsius,
        current: CurrentWeatherSummary(temperature: 23, feelsLike: 25, conditionCode: 0, conditionLabel: "Clear", symbolName: "sun.max"),
        hourly: [],
        daily: [],
        humidity: nil,
        airQualityLabel: nil
    )
    try expect(WeatherCache.isFresh(snapshot, intervalMinutes: 1, now: Date(timeIntervalSince1970: 1_600)), "weather cache should enforce a 15 minute minimum freshness interval")
    try expect(!WeatherCache.isFresh(snapshot, intervalMinutes: 15, now: Date(timeIntervalSince1970: 2_000)), "weather cache should expire after the configured interval")

    let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("WeatherCacheValidation-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: fileURL) }
    let cache = WeatherCache(fileURL: fileURL)
    cache.save(snapshot)
    try expect(cache.load() == snapshot, "weather cache should round-trip snapshots")
}

func validationWeatherSnapshot(locationName: String = "Fallback City") -> WeatherSnapshot {
    WeatherSnapshot(
        locationName: locationName,
        fetchedAt: Date(timeIntervalSince1970: 1_000),
        unit: .celsius,
        current: CurrentWeatherSummary(temperature: 20, feelsLike: 21, conditionCode: nil, conditionLabel: "Clear", symbolName: "sun.max"),
        hourly: [],
        daily: [],
        humidity: nil,
        airQualityLabel: nil
    )
}

func validateCompositeWeatherFallback() async throws {
    let expected = validationWeatherSnapshot()
    let provider = CompositeWeatherProvider(
        primary: ThrowingWeatherProvider(error: WeatherProviderError.providerUnavailable("WeatherKit entitlement unavailable")),
        fallback: StaticWeatherProvider(snapshot: expected)
    )

    let loaded = try await provider.fetchWeather(
        configuration: WeatherRequestConfiguration(manualLocation: "Tokyo", usesCurrentLocation: false, unit: .celsius)
    )

    try expect(loaded == expected, "composite provider should use fallback when primary provider is unavailable")
}

func validateCompositeWeatherDoesNotHideLocationDenial() async throws {
    let provider = CompositeWeatherProvider(
        primary: ThrowingWeatherProvider(error: WeatherProviderError.locationDenied),
        fallback: StaticWeatherProvider(snapshot: validationWeatherSnapshot())
    )

    do {
        _ = try await provider.fetchWeather(
            configuration: WeatherRequestConfiguration(manualLocation: nil, usesCurrentLocation: true, unit: .celsius)
        )
        throw ValidationFailure(description: "location denial should not be hidden by fallback data")
    } catch WeatherProviderError.locationDenied {
        return
    }
}

@MainActor
func validateWeatherManualLocationMissingStaysLocal() async throws {
    let provider = CountingWeatherProvider()
    let cacheURL = FileManager.default.temporaryDirectory.appendingPathComponent("WeatherManualMissingValidation-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: cacheURL) }

    let viewModel = WeatherWidgetViewModel(
        provider: provider,
        cache: WeatherCache(fileURL: cacheURL)
    )
    var settings = DockingSettings.default
    settings.weatherEnabled = true
    settings.weatherUsesCurrentLocation = false
    settings.weatherManualLocation = "   "

    await viewModel.refresh(settings: settings, force: true)

    try expect(provider.requestCount == 0, "missing manual weather location should not call provider")
    try expect(viewModel.state == .manualLocationNotSet, "missing manual weather location should show local configuration state")
}

private struct ThrowingWeatherProvider: WeatherProvider {
    let error: Error

    func fetchWeather(configuration: WeatherRequestConfiguration) async throws -> WeatherSnapshot {
        throw error
    }
}

private struct StaticWeatherProvider: WeatherProvider {
    let snapshot: WeatherSnapshot

    func fetchWeather(configuration: WeatherRequestConfiguration) async throws -> WeatherSnapshot {
        snapshot
    }
}

private final class CountingWeatherProvider: WeatherProvider {
    private(set) var requestCount = 0

    func fetchWeather(configuration: WeatherRequestConfiguration) async throws -> WeatherSnapshot {
        requestCount += 1
        return validationWeatherSnapshot(locationName: "Counting")
    }
}

private final class EmptyCalendarProvider: CalendarProviding {
    var changeNotificationName: Notification.Name {
        Notification.Name("ValidationCalendarProviderChanged")
    }

    var changeNotificationObject: Any? {
        nil
    }

    let authorizationState: CalendarAuthorizationState = .granted

    func availableCalendars() async throws -> [CalendarSourceSummary] {
        []
    }

    func upcomingEvents(lookaheadDays: Int, maxEvents: Int, selectedCalendarIDs: [String]) async throws -> [CalendarEventSummary] {
        []
    }
}

private final class DelayedCalendarProvider: CalendarProviding {
    var changeNotificationName: Notification.Name {
        Notification.Name("DelayedCalendarProviderChanged")
    }

    var changeNotificationObject: Any? {
        nil
    }

    let authorizationState: CalendarAuthorizationState = .granted

    func availableCalendars() async throws -> [CalendarSourceSummary] {
        []
    }

    func upcomingEvents(lookaheadDays: Int, maxEvents: Int, selectedCalendarIDs: [String]) async throws -> [CalendarEventSummary] {
        try await Task.sleep(nanoseconds: 500_000_000)
        return [
            CalendarEventSummary(
                id: "delayed",
                title: "Delayed",
                calendarName: "Validation",
                startDate: Date(),
                endDate: Date().addingTimeInterval(1_800),
                location: nil
            )
        ]
    }
}

private final class CountingCalendarProvider: CalendarProviding {
    let changeNotificationName = Notification.Name("CountingCalendarProviderChanged")
    var changeNotificationObject: Any? {
        nil
    }
    let authorizationState: CalendarAuthorizationState
    private(set) var upcomingEventRequestCount = 0
    private(set) var availableCalendarRequestCount = 0

    init(authorizationState: CalendarAuthorizationState = .granted) {
        self.authorizationState = authorizationState
    }

    func availableCalendars() async throws -> [CalendarSourceSummary] {
        availableCalendarRequestCount += 1
        return []
    }

    func upcomingEvents(lookaheadDays: Int, maxEvents: Int, selectedCalendarIDs: [String]) async throws -> [CalendarEventSummary] {
        upcomingEventRequestCount += 1
        return []
    }
}

private struct DelayedWeatherProvider: WeatherProvider {
    func fetchWeather(configuration: WeatherRequestConfiguration) async throws -> WeatherSnapshot {
        try await Task.sleep(nanoseconds: 500_000_000)
        return validationWeatherSnapshot(locationName: "Delayed")
    }
}

func validateRestoreSnapshot() throws {
    try expect(AppMetadata.version == "0.0.0", "app metadata should keep the explicit pre-release version")

    let suiteName = "docking.validation.restore.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let snapshot = DockRestoreSnapshot(
        createdAt: Date(timeIntervalSince1970: 123),
        appVersion: AppMetadata.version,
        values: [
            "autohide": .bool(true),
            "tilesize": .double(42),
            "orientation": .string("bottom")
        ]
    )

    let data = try JSONEncoder().encode(snapshot)
    let decoded = try JSONDecoder().decode(DockRestoreSnapshot.self, from: data)
    try expect(decoded == snapshot, "restore snapshot should preserve value types")
    try expect(decoded.appVersion == AppMetadata.version, "restore snapshot should carry the current app version")

    let snapshotURL = FileManager.default.temporaryDirectory.appendingPathComponent("DockRestoreValidation-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: snapshotURL) }

    let snapshotService = DockSettingsSnapshotService(fileURL: snapshotURL, dockDefaults: defaults)
    defaults.set(false, forKey: "autohide")
    defaults.set(36.0, forKey: "tilesize")
    defaults.set("left", forKey: "orientation")
    defaults.set(0.4, forKey: "autohide-delay")

    let emptySnapshotURL = FileManager.default.temporaryDirectory.appendingPathComponent("DockRestoreEmptyValidation-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: emptySnapshotURL) }

    let emptySnapshotService = DockSettingsSnapshotService(fileURL: emptySnapshotURL, dockDefaults: defaults)
    let emptyRestoreService = DockSettingsRestoreService(snapshotService: emptySnapshotService, dockDefaults: defaults)
    let emptyResult = try emptyRestoreService.restoreIfSnapshotExists()
    try expect(emptyResult.userMessage.contains("No Dock restore snapshot exists"), "restore without a snapshot should explain that nothing changed")
    try expect(defaults.object(forKey: "autohide") as? Bool == false, "restore without a snapshot should not modify bool preferences")
    try expect(defaults.object(forKey: "tilesize") as? Double == 36.0, "restore without a snapshot should not modify numeric preferences")
    try expect(defaults.object(forKey: "orientation") as? String == "left", "restore without a snapshot should not modify string preferences")

    let primaryModeSnapshotURL = FileManager.default.temporaryDirectory.appendingPathComponent("DockPrimaryModeValidation-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: primaryModeSnapshotURL) }
    let primaryModeSnapshotService = DockSettingsSnapshotService(fileURL: primaryModeSnapshotURL, dockDefaults: defaults)
    let primaryModeService = DockSettingsRestoreService(snapshotService: primaryModeSnapshotService, dockDefaults: defaults)
    try expect(!primaryModeService.restoreStatus().hasSnapshot, "primary mode status should start without a snapshot")
    _ = try primaryModeService.enableReplacementMode()
    let savedPrimaryModeSnapshot = try primaryModeSnapshotService.loadSnapshot()
    let enabledStatus = primaryModeService.restoreStatus()
    try expect(enabledStatus.snapshotCreatedAt == savedPrimaryModeSnapshot?.createdAt, "primary mode status should expose snapshot creation time")
    try expect(enabledStatus.savedPreferenceCount == savedPrimaryModeSnapshot?.values.count, "primary mode status should expose saved preference count")
    try expect(savedPrimaryModeSnapshot?.values["autohide"] == .bool(false), "primary mode should snapshot original autohide before changing it")
    try expect(defaults.object(forKey: "autohide") as? Bool == true, "primary mode should make Apple Dock auto-hide")
    try expect(defaults.object(forKey: "autohide-delay") as? Double == 1000.0, "primary mode should move Apple Dock out of the way with a long delay")
    _ = try primaryModeService.restoreIfSnapshotExists()
    try expect(defaults.object(forKey: "autohide") as? Bool == false, "primary mode restore should put original autohide back")
    try expect(defaults.object(forKey: "autohide-delay") as? Double == 0.4, "primary mode restore should put original autohide delay back")

    let current = snapshotService.currentDockSnapshot()
    try expect(current.values["autohide"] == .bool(false), "current Dock snapshot should read bool preferences")
    try expect(current.values["tilesize"] == .double(36.0), "current Dock snapshot should read numeric preferences")
    try expect(current.values["orientation"] == .string("left"), "current Dock snapshot should read string preferences")

    try snapshotService.saveSnapshot(snapshot)
    defaults.set(false, forKey: "autohide")
    defaults.set(20.0, forKey: "tilesize")
    defaults.set("left", forKey: "orientation")

    let restoreService = DockSettingsRestoreService(snapshotService: snapshotService, dockDefaults: defaults)
    let result = try restoreService.restoreIfSnapshotExists()
    try expect(result.userMessage.contains("Saved Dock settings"), "restore should report that a snapshot was written back")
    try expect(defaults.object(forKey: "autohide") as? Bool == true, "restore should write bool preferences")
    try expect(defaults.object(forKey: "tilesize") as? Double == 42.0, "restore should write numeric preferences")
    try expect(defaults.object(forKey: "orientation") as? String == "bottom", "restore should write string preferences")
}

let validations: [(String, () throws -> Void)] = [
    ("formatters", validateFormatters),
    ("calendar grouping", validateCalendarGrouping),
    ("dock layout", validateDockLayout),
    ("detail panel anchoring", validateDetailPanelAnchoring),
    ("specific display selection", validateSpecificDisplaySelection),
    ("dock position frames", validateDockPositionFrames),
    ("app catalog bundle recognition", validateAppCatalogRecognizesOnlyApplicationBundles),
    ("settings store", validateSettingsStore),
    ("settings refresh keys", validateSettingsRefreshKeys),
    ("default settings fit editable ranges", validateDefaultSettingsFitEditableRanges),
    ("dock widget metrics", validateDockWidgetMetrics),
    ("accent color options", validateAccentColorOptionsCoverDefault),
    ("weather cache", validateWeatherCache),
    ("restore snapshot", validateRestoreSnapshot)
]

let asyncValidations: [(String, () async throws -> Void)] = [
    ("settings persistence debounce", { try await validateSettingsPersistenceIsDebounced() }),
    ("widget refresh cancellation", { try await validateWidgetRefreshCancellation() }),
    ("widget task lifecycle", { try await validateWidgetTaskLifecycle() }),
    ("calendar launch does not request permission", { try await validateCalendarLaunchDoesNotRequestPermission() }),
    ("disabled calendar ignores store changes", { try await validateDisabledCalendarIgnoresStoreChanges() }),
    ("weather provider fallback", validateCompositeWeatherFallback),
    ("weather provider permission boundary", validateCompositeWeatherDoesNotHideLocationDenial),
    ("weather manual location missing stays local", { try await validateWeatherManualLocationMissingStaysLocal() })
]

do {
    for (name, validation) in validations {
        try validation()
        print("PASS \(name)")
    }
    for (name, validation) in asyncValidations {
        try await validation()
        print("PASS \(name)")
    }
    print("All Docking validation checks passed.")
} catch {
    fputs("FAIL \(error)\n", stderr)
    exit(1)
}
