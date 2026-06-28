import Foundation

struct DockItem: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var bundleIdentifier: String?
    var appURL: URL?
    var iconCacheKey: String
    var isPinned: Bool
    var groupID: UUID?

    init(
        id: UUID = UUID(),
        title: String,
        bundleIdentifier: String?,
        appURL: URL?,
        iconCacheKey: String,
        isPinned: Bool = true,
        groupID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.bundleIdentifier = bundleIdentifier
        self.appURL = appURL
        self.iconCacheKey = iconCacheKey
        self.isPinned = isPinned
        self.groupID = groupID
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
            return "Display with pointer"
        case .specific:
            return "Specific display"
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
        item.bundleIdentifier ?? item.appURL?.path ?? item.iconCacheKey
    }
}

struct DockWidgetConfiguration: Codable, Equatable {
    var calendarEnabled: Bool
    var weatherEnabled: Bool
    var widgetSize: Double

    static let `default` = DockWidgetConfiguration(
        calendarEnabled: true,
        weatherEnabled: true,
        widgetSize: 58
    )
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
    var widgetSize: Double
    var spacing: Double
    var cornerRadius: Double
    var materialStrength: Double
    var opacity: Double
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
        widgetSize: 58,
        spacing: 8,
        cornerRadius: 22,
        materialStrength: 0.9,
        opacity: 0.96,
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
    static let autoHideDelay: ClosedRange<Double> = 0.2...2.0
    static let dockSize: ClosedRange<Double> = 58...104
    static let iconSize: ClosedRange<Double> = 32...72
    // 44pt allowed the Calendar icon and two compact text rows to compete for
    // the same vertical space. The app is pre-1.0, so we choose the readable
    // product constraint instead of preserving a size that produced broken UI.
    static let widgetSize: ClosedRange<Double> = widgetReadableMinimum...84
    static let spacing: ClosedRange<Double> = 4...18
    static let cornerRadius: ClosedRange<Double> = 12...34
    static let materialStrength: ClosedRange<Double> = 0.0...1.0
    static let opacity: ClosedRange<Double> = 0.65...1.0
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

struct WeatherSnapshot: Codable, Equatable {
    var locationName: String
    var fetchedAt: Date
    var unit: TemperatureUnit
    var current: CurrentWeatherSummary
    var hourly: [HourlyWeatherSummary]
    var daily: [DailyWeatherSummary]
    var humidity: Double?
    var airQualityLabel: String?
}

enum DockWidgetKind: String, Identifiable {
    case calendar
    case weather

    var id: String { rawValue }
}
