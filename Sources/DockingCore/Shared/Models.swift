import Foundation

enum DockItemKind: String, Codable, Equatable {
    case application
    case folder

    var label: String {
        switch self {
        case .application:
            return "Application"
        case .folder:
            return "Folder"
        }
    }
}

enum DockFolderDisplayMode: String, CaseIterable, Codable, Identifiable {
    case folder
    case stack

    var id: String { rawValue }

    var label: String {
        switch self {
        case .folder:
            return "Folder"
        case .stack:
            return "Stack"
        }
    }
}

enum DockFolderViewMode: String, CaseIterable, Codable, Identifiable {
    case automatic
    case fan
    case grid
    case list

    var id: String { rawValue }

    var label: String {
        switch self {
        case .automatic:
            return "Automatic"
        case .fan:
            return "Fan"
        case .grid:
            return "Grid"
        case .list:
            return "List"
        }
    }
}

enum DockFolderSortMode: String, CaseIterable, Codable, Identifiable {
    case name
    case dateAdded
    case dateModified
    case dateCreated
    case kind

    var id: String { rawValue }

    var label: String {
        switch self {
        case .name:
            return "Name"
        case .dateAdded:
            return "Date Added"
        case .dateModified:
            return "Date Modified"
        case .dateCreated:
            return "Date Created"
        case .kind:
            return "Kind"
        }
    }
}

struct DockItem: Identifiable, Codable, Equatable {
    var id: UUID
    var kind: DockItemKind
    var title: String
    var bundleIdentifier: String?
    var url: URL?
    var iconCacheKey: String
    var isPinned: Bool
    var groupID: UUID?
    var folderDisplayMode: DockFolderDisplayMode
    var folderViewMode: DockFolderViewMode
    var folderSortMode: DockFolderSortMode

    init(
        id: UUID = UUID(),
        kind: DockItemKind = .application,
        title: String,
        bundleIdentifier: String?,
        url: URL?,
        iconCacheKey: String,
        isPinned: Bool = true,
        groupID: UUID? = nil,
        folderDisplayMode: DockFolderDisplayMode = .folder,
        folderViewMode: DockFolderViewMode = .automatic,
        folderSortMode: DockFolderSortMode = .name
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.bundleIdentifier = bundleIdentifier
        self.url = url
        self.iconCacheKey = iconCacheKey
        self.isPinned = isPinned
        self.groupID = groupID
        self.folderDisplayMode = folderDisplayMode
        self.folderViewMode = folderViewMode
        self.folderSortMode = folderSortMode
    }

    var isApplication: Bool {
        kind == .application
    }

    var isFolder: Bool {
        kind == .folder
    }

    var renderedIconCacheKey: String {
        guard isFolder else {
            return iconCacheKey
        }

        // Folder icons can be a plain folder or a stack preview. The preview is
        // derived from user-controlled folder view state, so the render cache
        // key includes those choices instead of forcing broad cache invalidation
        // every time a folder context-menu option changes.
        return [
            iconCacheKey,
            folderDisplayMode.rawValue,
            folderSortMode.rawValue
        ].joined(separator: "|")
    }

    var identityKey: String {
        if let bundleIdentifier, isApplication {
            return "app:\(bundleIdentifier)"
        }

        if let url {
            return "\(kind.rawValue):\(url.standardizedFileURL.path)"
        }

        // This fallback is not meant to be user-facing identity. It keeps
        // malformed development data from collapsing unrelated items together
        // while AppListStore falls back to defaults on decode failures.
        return "\(kind.rawValue):\(iconCacheKey)"
    }

    var subtitle: String {
        switch kind {
        case .application:
            return bundleIdentifier ?? url?.path ?? "Application"
        case .folder:
            return url?.path ?? "Folder"
        }
    }
}

enum ThemeMode: String, CaseIterable, Codable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }
}

enum TemperatureUnit: String, CaseIterable, Codable, Identifiable {
    case celsius
    case fahrenheit

    var id: String { rawValue }
}

enum DockingAccentColor: String, CaseIterable, Identifiable {
    case blue
    case teal
    case green
    case amber
    case red
    case pink
    case purple
    case graphite

    var id: String { rawValue }

    var label: String {
        switch self {
        case .blue:
            return "Blue"
        case .teal:
            return "Teal"
        case .green:
            return "Green"
        case .amber:
            return "Amber"
        case .red:
            return "Red"
        case .pink:
            return "Pink"
        case .purple:
            return "Purple"
        case .graphite:
            return "Graphite"
        }
    }
}

enum DockDisplayMode: String, CaseIterable, Codable, Identifiable {
    case main
    case pointer
    case specific

    var id: String { rawValue }

    var label: String {
        switch self {
        case .main:
            return "Main display"
        case .pointer:
            return "Follow pointer"
        case .specific:
            return "Chosen display"
        }
    }
}

enum DockPosition: String, CaseIterable, Codable, Identifiable {
    case bottomCenter
    case bottomLeft
    case bottomRight
    case left
    case right

    var id: String { rawValue }

    var isVertical: Bool {
        switch self {
        case .left, .right:
            return true
        case .bottomCenter, .bottomLeft, .bottomRight:
            return false
        }
    }

    var isBottom: Bool {
        !isVertical
    }

    var label: String {
        switch self {
        case .bottomCenter:
            return "Bottom center"
        case .bottomLeft:
            return "Bottom left"
        case .bottomRight:
            return "Bottom right"
        case .left:
            return "Left"
        case .right:
            return "Right"
        }
    }
}

enum DockVisibilityMode: String, CaseIterable, Codable, Identifiable {
    case autoHide
    case alwaysVisible

    var id: String { rawValue }

    var label: String {
        switch self {
        case .autoHide:
            return "Auto-hide"
        case .alwaysVisible:
            return "Always visible"
        }
    }
}

enum UnpinnedRunningAppVisibility: String, CaseIterable, Codable, Identifiable {
    case separated
    case hidden

    var id: String { rawValue }

    var label: String {
        switch self {
        case .separated:
            return "Show separated"
        case .hidden:
            return "Hide"
        }
    }
}

enum DockRunningItemResolver {
    static func unpinnedRunningItems(
        pinnedItems: [DockItem],
        runningItems: [DockItem],
        visibility: UnpinnedRunningAppVisibility
    ) -> [DockItem] {
        guard visibility == .separated else {
            return []
        }

        // Running apps are intentionally resolved from stable app identity,
        // not from DockItem.id. Transient items are rebuilt from
        // NSRunningApplication snapshots, so UUID comparison would treat the
        // same app as new after every observer refresh. Bundle ID is preferred
        // because it survives path changes; the path fallback covers unsigned
        // or helper-like apps that still behave as regular user apps.
        let pinnedKeys = Set(pinnedItems.map(stableKey))
        var seenKeys: Set<String> = []
        return runningItems.filter { item in
            let key = stableKey(for: item)
            guard !pinnedKeys.contains(key), !seenKeys.contains(key) else {
                return false
            }
            seenKeys.insert(key)
            return true
        }
    }

    private static func stableKey(for item: DockItem) -> String {
        item.identityKey
    }
}

struct DockWidgetConfiguration: Codable, Equatable {
    var calendarEnabled: Bool
    var weatherEnabled: Bool
    var calendarWidgetSizePreset: WidgetSizePreset
    var weatherWidgetSizePreset: WidgetSizePreset

    static let `default` = DockWidgetConfiguration(
        calendarEnabled: true,
        weatherEnabled: true,
        calendarWidgetSizePreset: .standard,
        weatherWidgetSizePreset: .standard
    )
}

// Dock scale groups the three dimensions users perceive as one choice: surface
// thickness, app icon size, and spacing. Exposing them independently made the
// settings powerful but hard to reason about; the renderer still stores the
// exact values so validation can guard geometry without another abstraction.
enum DockScalePreset: String, CaseIterable, Identifiable, Codable {
    case compact
    case comfortable
    case large

    var id: String { rawValue }

    var label: String {
        switch self {
        case .compact:
            return "Compact"
        case .comfortable:
            return "Comfortable"
        case .large:
            return "Large"
        }
    }

    var dockSize: Double {
        switch self {
        case .compact:
            return 64
        case .comfortable:
            return 72
        case .large:
            return 88
        }
    }

    var iconSize: Double {
        switch self {
        case .compact:
            return 40
        case .comfortable:
            return 46
        case .large:
            return 58
        }
    }

    var spacing: Double {
        switch self {
        case .compact:
            return 6
        case .comfortable:
            return 8
        case .large:
            return 12
        }
    }

    static func nearest(to settings: DockingSettings) -> DockScalePreset {
        allCases.min { left, right in
            left.distance(to: settings) < right.distance(to: settings)
        } ?? .comfortable
    }

    private func distance(to settings: DockingSettings) -> Double {
        abs(dockSize - settings.dockSize) + abs(iconSize - settings.iconSize) + abs(spacing - settings.spacing)
    }
}

// Widget size remains a semantic preset, not a strict geometry contract. The
// app-icon comparison is only a design calibration point for choosing widths;
// encoding "one/two/three icons" as product semantics would make future layout
// tuning harder and would expose an implementation detail to users.
enum WidgetSizePreset: String, CaseIterable, Identifiable, Codable {
    case compact
    case standard
    case detailed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .compact:
            return "Compact"
        case .standard:
            return "Standard"
        case .detailed:
            return "Detailed"
        }
    }

    func width(iconSize: Double) -> Double {
        switch self {
        case .compact:
            return max(DockingSettingLimits.widgetReadableMinimum, iconSize + 8)
        case .standard:
            return max(88, iconSize * 1.9)
        case .detailed:
            // Detailed widgets should earn their space with side-by-side
            // context, not taller rows. The width is calibrated from the icon
            // rhythm, but we cap the default footprint to roughly the amount
            // of useful context the tile can actually explain. A wider value
            // looked generous at first, but it created blank, unowned space in
            // Weather; the widget should feel intentionally dense before the
            // user clicks through to the full panel.
            return max(196, iconSize * 4.25)
        }
    }
}

// Apple positions Liquid Glass as an adaptive control/navigation material, so
// Docking treats it as a surface style for the dock chrome. We avoid separate
// corner-radius/material/opacity sliders because independent values can easily
// produce non-Apple-looking combinations, while these presets preserve a small
// set of coherent glass treatments.
enum LiquidGlassSurfaceStyle: String, CaseIterable, Identifiable, Codable {
    case clear
    case balanced
    case dense

    var id: String { rawValue }

    var label: String {
        switch self {
        case .clear:
            return "Clear"
        case .balanced:
            return "Balanced"
        case .dense:
            return "Dense"
        }
    }

    var cornerRadius: Double {
        switch self {
        case .clear:
            return 26
        case .balanced:
            return 22
        case .dense:
            return 18
        }
    }

    var materialStrength: Double {
        switch self {
        case .clear:
            return 1.0
        case .balanced:
            return 0.9
        case .dense:
            return 0.58
        }
    }

    var opacity: Double {
        switch self {
        case .clear:
            return 0.92
        case .balanced:
            return 0.96
        case .dense:
            return 0.99
        }
    }
}

struct DockingSettings: Codable, Equatable {
    var launchAtLogin: Bool
    var showMenuBarIcon: Bool
    var dockVisibility: DockVisibilityMode
    var unpinnedRunningAppVisibility: UnpinnedRunningAppVisibility
    var keepAboveOtherWindows: Bool
    var autoHideDelay: Double
    var showOnAllSpaces: Bool
    var showOnFullScreenSpaces: Bool
    var displayMode: DockDisplayMode
    var dockDisplayID: UInt32?
    var dockPosition: DockPosition
    var dockSize: Double
    var iconSize: Double
    var calendarWidgetSizePreset: WidgetSizePreset
    var weatherWidgetSizePreset: WidgetSizePreset
    var spacing: Double
    var liquidGlassSurfaceStyle: LiquidGlassSurfaceStyle
    var theme: ThemeMode
    var accentColorName: String
    var calendarEnabled: Bool
    var calendarLookaheadDays: Int
    var calendarMaxEventCount: Int
    var calendarShowsLocation: Bool
    var calendarSelectedCalendarIDs: [String]
    var weatherEnabled: Bool
    var weatherUsesCurrentLocation: Bool
    var weatherManualLocation: String
    var weatherUnit: TemperatureUnit
    var weatherRefreshIntervalMinutes: Int
    var weatherShowsHumidity: Bool
    var weatherShowsAQI: Bool
    var dockReplacementModeEnabled: Bool

    static let `default` = DockingSettings(
        launchAtLogin: false,
        showMenuBarIcon: true,
        dockVisibility: .autoHide,
        unpinnedRunningAppVisibility: .separated,
        keepAboveOtherWindows: true,
        autoHideDelay: 0.7,
        showOnAllSpaces: true,
        showOnFullScreenSpaces: true,
        displayMode: .main,
        dockDisplayID: nil,
        dockPosition: .bottomCenter,
        dockSize: 72,
        iconSize: 46,
        calendarWidgetSizePreset: .standard,
        weatherWidgetSizePreset: .standard,
        spacing: 8,
        liquidGlassSurfaceStyle: .balanced,
        theme: .system,
        accentColorName: "blue",
        calendarEnabled: true,
        calendarLookaheadDays: 7,
        calendarMaxEventCount: 10,
        calendarShowsLocation: true,
        calendarSelectedCalendarIDs: [],
        weatherEnabled: true,
        weatherUsesCurrentLocation: false,
        weatherManualLocation: "",
        weatherUnit: .celsius,
        weatherRefreshIntervalMinutes: 45,
        weatherShowsHumidity: true,
        weatherShowsAQI: true,
        dockReplacementModeEnabled: false
    )

    static func defaults(matchingAppleDock dockDefaults: UserDefaults?) -> DockingSettings {
        var settings = Self.default
        settings.dockVisibility = AppleDockPreferences.visibilityMode(from: dockDefaults)
        return settings
    }
}

enum DockingSettingLimits {
    // These are product constraints, not persistence migrations. The settings UI
    // and validation share them so a default value cannot drift outside the
    // range the user can later edit back to.
    static let widgetReadableMinimum = 52.0
    // The lower bound stays above zero because an immediate hide makes the dock
    // feel like it is fighting pointer movement, especially while opening
    // widget panels. 0.05s is still fast enough for users who want a near-
    // instant hide without turning the setting into an accidental flicker mode.
    static let autoHideDelay: ClosedRange<Double> = 0.05...2.0
    static let autoHideDelayStep = 0.05
    static let dockSize: ClosedRange<Double> = 58...104
    static let iconSize: ClosedRange<Double> = 32...72
    // 44pt allowed the Calendar icon and two compact text rows to compete for
    // the same vertical space. The app is pre-1.0, so we choose the readable
    // product constraint instead of preserving a size that produced broken UI.
    static let spacing: ClosedRange<Double> = 4...18
    static let calendarLookaheadDays: ClosedRange<Int> = 1...30
    static let calendarMaxEventCount: ClosedRange<Int> = 1...50
    static let weatherRefreshIntervalMinutes: ClosedRange<Int> = 30...180
    static let weatherRefreshIntervalStep = 15
}

struct CalendarRefreshKey: Equatable {
    var enabled: Bool
    var lookaheadDays: Int
    var maxEventCount: Int
    var selectedCalendarIDs: [String]
}

struct WeatherRefreshKey: Equatable {
    var enabled: Bool
    var usesCurrentLocation: Bool
    var manualLocation: String
    var unit: TemperatureUnit
    var refreshIntervalMinutes: Int
}

extension DockingSettings {
    var effectiveDockThickness: Double {
        // Wider widgets should not make Docking vertically greedy. If a user
        // wants dense vertical detail they can click the widget panel; the dock
        // itself should preserve a low horizontal silhouette and spend extra
        // information density across the x-axis.
        max(dockSize, iconSize + 18)
    }

    var widgetTileHeight: Double {
        // This is intentionally capped to the dock's app-icon rhythm. Vertical
        // occupation is much more expensive than horizontal occupation because
        // it reduces the usable workspace even when the user is not reading the
        // widget. Detailed widgets must therefore buy room with width only.
        min(max(DockingSettingLimits.widgetReadableMinimum, iconSize + 8), dockSize - 10)
    }

    var calendarWidgetWidth: Double {
        calendarWidgetSizePreset.width(iconSize: iconSize)
    }

    var weatherWidgetWidth: Double {
        weatherWidgetSizePreset.width(iconSize: iconSize)
    }

    var cornerRadius: Double {
        liquidGlassSurfaceStyle.cornerRadius
    }

    var materialStrength: Double {
        liquidGlassSurfaceStyle.materialStrength
    }

    var opacity: Double {
        liquidGlassSurfaceStyle.opacity
    }

    var enabledWidgetWidths: [Double] {
        var widths: [Double] = []
        if calendarEnabled {
            widths.append(calendarWidgetWidth)
        }
        if weatherEnabled {
            widths.append(weatherWidgetWidth)
        }
        return widths
    }

    var calendarRefreshKey: CalendarRefreshKey {
        CalendarRefreshKey(
            enabled: calendarEnabled,
            lookaheadDays: calendarLookaheadDays,
            maxEventCount: calendarMaxEventCount,
            selectedCalendarIDs: calendarSelectedCalendarIDs
        )
    }

    var weatherRefreshKey: WeatherRefreshKey {
        WeatherRefreshKey(
            enabled: weatherEnabled,
            usesCurrentLocation: weatherUsesCurrentLocation,
            manualLocation: weatherManualLocation,
            unit: weatherUnit,
            refreshIntervalMinutes: weatherRefreshIntervalMinutes
        )
    }
}

struct CalendarEventSummary: Identifiable, Equatable {
    var id: String
    var title: String
    var calendarName: String
    var startDate: Date
    var endDate: Date
    var location: String?
}

struct CalendarSourceSummary: Identifiable, Equatable {
    var id: String
    var title: String
    var colorHex: String?
}

struct DisplaySummary: Identifiable, Equatable {
    var id: UInt32
    var name: String
    var frameDescription: String
}

struct CurrentWeatherSummary: Codable, Equatable {
    var temperature: Double
    var feelsLike: Double?
    var conditionCode: Int?
    var conditionLabel: String
    var symbolName: String
}

struct HourlyWeatherSummary: Identifiable, Codable, Equatable {
    var id: Date { date }
    var date: Date
    var temperature: Double
    var conditionCode: Int?
    var symbolName: String
}

struct DailyWeatherSummary: Identifiable, Codable, Equatable {
    var id: Date { date }
    var date: Date
    var high: Double
    var low: Double
    var conditionCode: Int?
    var symbolName: String
}

enum WeatherDataSource: String, Codable, Equatable {
    case weatherKit
    case openMeteo
    case mock

    var controlCenterLabel: String {
        switch self {
        case .weatherKit:
            return "Apple WeatherKit"
        case .openMeteo:
            return "Open-Meteo fallback"
        case .mock:
            return "Debug mock"
        }
    }

    var controlCenterDetail: String {
        switch self {
        case .weatherKit:
            return "The latest loaded weather came directly from Apple's WeatherKit provider."
        case .openMeteo:
            return "The latest loaded weather came from Open-Meteo after WeatherKit was unavailable or could not complete."
        case .mock:
            return "The latest loaded weather came from Docking's debug-only mock provider, not a production weather service."
        }
    }
}

struct WeatherSnapshot: Codable, Equatable {
    var locationName: String
    var fetchedAt: Date
    var unit: TemperatureUnit
    var current: CurrentWeatherSummary
    var hourly: [HourlyWeatherSummary]
    var daily: [DailyWeatherSummary]
    var humidity: Double?
    var airQualityLabel: String?
    // This is optional for cache compatibility. Users may already have a
    // WeatherSnapshot.json written by older Docking builds, and failing to
    // decode that cache just to show provider diagnostics would discard useful
    // real weather. New provider fetches always set this so Control Center can
    // distinguish Apple WeatherKit from the Open-Meteo fallback.
    var dataSource: WeatherDataSource? = nil
}

enum DockWidgetKind: String, Identifiable {
    case calendar
    case weather

    var id: String { rawValue }
}
