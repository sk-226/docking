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

enum DockRunningTileScope: String, Codable, Equatable {
    // This enum is intentionally about the visible Dock tile, not the process
    // list. A regular app process can still exist behind either case; the
    // difference is whether one user-facing Dock affordance maps to one pid or
    // to the app's shared Dock identity.
    case process
    case singleAppTile
}

struct DockItem: Identifiable, Codable, Equatable {
    var id: UUID
    var kind: DockItemKind
    var title: String
    var bundleIdentifier: String?
    var url: URL?
    var iconCacheKey: String
    var runningProcessIdentifier: pid_t?
    var runningTileScope: DockRunningTileScope?
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
        runningProcessIdentifier: pid_t? = nil,
        runningTileScope: DockRunningTileScope? = nil,
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
        self.runningProcessIdentifier = runningProcessIdentifier
        self.runningTileScope = runningTileScope
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

    var runningInstanceKey: String? {
        guard let runningProcessIdentifier, isApplication else {
            return nil
        }

        // A bundle identifier alone is the durable identity for pinned apps,
        // but it is too coarse for live Dock items that the system Dock exposes
        // as separate tiles. Calculator and TextEdit launched twice with
        // `open -n` were observed as two standard Dock icons, so combining the
        // app identity with the pid lets Docking keep those per-tile runtime
        // boundaries. Apps that the system Dock collapses to one tile, such as
        // Ghostty with its Dock tile plug-in, do not receive a pid-bound live
        // item from RunningAppObserver in the first place.
        //
        // The pid is intentionally not part of `identityKey`: persisted items
        // must keep matching the app across launches, while this key is only
        // valid inside the current NSWorkspace snapshot and the short
        // quit-reconciliation window.
        return "\(identityKey)#pid:\(runningProcessIdentifier)"
    }

    var representsSingleAppRunningTile: Bool {
        // A nil pid is ambiguous without this explicit runtime scope: persisted
        // pinned apps also have no pid, while Ghostty-style live items drop the
        // pid because the standard Dock exposes several regular processes as
        // one icon. Keeping that distinction on the item prevents launch/quit
        // code from guessing based on nil alone.
        runningTileScope == .singleAppTile
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
    static func assignedPinnedItems(pinnedItems: [DockItem], runningItems: [DockItem]) -> [DockItem] {
        let assignments = runningAssignments(pinnedItems: pinnedItems, runningItems: runningItems)
        return pinnedItems.map { pinnedItem in
            var item = pinnedItem
            if let runningItem = assignments[pinnedItem.id] {
                // Pinned icons are durable user choices, but while an app is
                // running the visible pinned tile still represents one concrete
                // standard-Dock slot. Copying the runtime pid/scope onto a
                // display-only value keeps Quit, active state, and pending
                // reconciliation pointed at the same process or grouped tile
                // that this pinned icon consumed from the running snapshot.
                //
                // We deliberately do not write these fields back into
                // AppListStore. Persisting a pid would create stale behavior
                // across launches, while the assignment is only valid for the
                // current NSWorkspace snapshot.
                item.runningProcessIdentifier = runningItem.runningProcessIdentifier
                item.runningTileScope = runningItem.runningTileScope
            } else {
                item.runningProcessIdentifier = nil
                item.runningTileScope = nil
            }
            return item
        }
    }

    static func unpinnedRunningItems(
        pinnedItems: [DockItem],
        runningItems: [DockItem],
        visibility: UnpinnedRunningAppVisibility
    ) -> [DockItem] {
        guard visibility == .separated else {
            return []
        }

        return unresolvedRunningItems(pinnedItems: pinnedItems, runningItems: runningItems)
    }

    private static func runningAssignments(pinnedItems: [DockItem], runningItems: [DockItem]) -> [UUID: DockItem] {
        var remainingRunningItems = runningItems
        var assignments: [UUID: DockItem] = [:]

        for pinnedItem in pinnedItems {
            guard let index = remainingRunningItems.firstIndex(where: { runningItem in
                stableKey(for: runningItem) == stableKey(for: pinnedItem)
            }) else {
                continue
            }
            assignments[pinnedItem.id] = remainingRunningItems.remove(at: index)
        }

        return assignments
    }

    private static func unresolvedRunningItems(pinnedItems: [DockItem], runningItems: [DockItem]) -> [DockItem] {
        var remainingRunningItems = runningItems
        for pinnedItem in pinnedItems {
            guard let index = remainingRunningItems.firstIndex(where: { runningItem in
                stableKey(for: runningItem) == stableKey(for: pinnedItem)
            }) else {
                continue
            }
            // Pinned Dock items consume one running instance of the same app
            // identity, but they do not consume every sibling Dock tile. This
            // mirrors the system Dock behavior observed with Calculator and
            // TextEdit: two `open -n` regular processes produce two standard
            // Dock icons, so a pinned icon accounts for one tile while a sibling
            // remains separately addressable. Apps such as Ghostty that the
            // standard Dock collapses to one tile are already grouped by
            // RunningAppObserver before they reach this resolver.
            remainingRunningItems.remove(at: index)
        }

        return remainingRunningItems
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

    var contentWidth: Double {
        switch self {
        case .compact: return 76
        case .standard: return 124
        case .detailed: return 184
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
}

enum DockAutoHideResponsePreset: String, CaseIterable, Identifiable, Codable {
    case standard
    case fast
    case instant

    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard:
            return "Default"
        case .fast:
            return "Fast"
        case .instant:
            return "Instant"
        }
    }

    var revealDelay: TimeInterval {
        switch self {
        case .standard:
            return 0.5
        case .fast:
            return 0.15
        case .instant:
            return 0.0
        }
    }
}

struct DockingSettings: Codable, Equatable {
    var launchAtLogin: Bool
    var showMenuBarIcon: Bool
    var dockVisibility: DockVisibilityMode
    var unpinnedRunningAppVisibility: UnpinnedRunningAppVisibility
    var keepAboveOtherWindows: Bool
    var dockAutoHideResponsePreset: DockAutoHideResponsePreset
    var autoHideDelay: Double
    var showOnAllSpaces: Bool
    var showOnFullScreenSpaces: Bool
    var displayMode: DockDisplayMode
    var dockDisplayID: UInt32?
    var dockPosition: DockPosition
    var iconSize: Double
    var widgetScale: Double
    var magnificationEnabled: Bool
    var magnificationSize: Double
    var calendarWidgetSizePreset: WidgetSizePreset
    var weatherWidgetSizePreset: WidgetSizePreset
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
        dockAutoHideResponsePreset: .standard,
        autoHideDelay: 0.7,
        showOnAllSpaces: true,
        showOnFullScreenSpaces: true,
        displayMode: .main,
        dockDisplayID: nil,
        dockPosition: .bottomCenter,
        iconSize: 36,
        widgetScale: 1,
        magnificationEnabled: true,
        magnificationSize: 72,
        calendarWidgetSizePreset: .standard,
        weatherWidgetSizePreset: .standard,
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
        _ = AppleDockPreferences.mirrorOriginalDock(into: &settings, savedValues: nil, dockDefaults: dockDefaults)
        return settings
    }
}

extension DockingSettings {
    enum CodingKeys: String, CodingKey {
        case launchAtLogin
        case showMenuBarIcon
        case dockVisibility
        case unpinnedRunningAppVisibility
        case keepAboveOtherWindows
        case dockAutoHideResponsePreset
        case autoHideDelay
        case showOnAllSpaces
        case showOnFullScreenSpaces
        case displayMode
        case dockDisplayID
        case dockPosition
        case iconSize
        case widgetScale
        case magnificationEnabled
        case magnificationSize
        case calendarWidgetSizePreset
        case weatherWidgetSizePreset
        case liquidGlassSurfaceStyle
        case theme
        case accentColorName
        case calendarEnabled
        case calendarLookaheadDays
        case calendarMaxEventCount
        case calendarShowsLocation
        case calendarSelectedCalendarIDs
        case weatherEnabled
        case weatherUsesCurrentLocation
        case weatherManualLocation
        case weatherUnit
        case weatherRefreshIntervalMinutes
        case weatherShowsHumidity
        case weatherShowsAQI
        case dockReplacementModeEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self.default

        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? defaults.launchAtLogin
        showMenuBarIcon = try container.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? defaults.showMenuBarIcon
        dockVisibility = try container.decodeIfPresent(DockVisibilityMode.self, forKey: .dockVisibility) ?? defaults.dockVisibility
        unpinnedRunningAppVisibility = try container.decodeIfPresent(UnpinnedRunningAppVisibility.self, forKey: .unpinnedRunningAppVisibility) ?? defaults.unpinnedRunningAppVisibility
        keepAboveOtherWindows = try container.decodeIfPresent(Bool.self, forKey: .keepAboveOtherWindows) ?? defaults.keepAboveOtherWindows
        dockAutoHideResponsePreset = try container.decodeIfPresent(DockAutoHideResponsePreset.self, forKey: .dockAutoHideResponsePreset) ?? defaults.dockAutoHideResponsePreset
        autoHideDelay = try container.decodeIfPresent(Double.self, forKey: .autoHideDelay) ?? defaults.autoHideDelay
        showOnAllSpaces = try container.decodeIfPresent(Bool.self, forKey: .showOnAllSpaces) ?? defaults.showOnAllSpaces
        showOnFullScreenSpaces = try container.decodeIfPresent(Bool.self, forKey: .showOnFullScreenSpaces) ?? defaults.showOnFullScreenSpaces
        displayMode = try container.decodeIfPresent(DockDisplayMode.self, forKey: .displayMode) ?? defaults.displayMode
        dockDisplayID = try container.decodeIfPresent(UInt32.self, forKey: .dockDisplayID) ?? defaults.dockDisplayID
        dockPosition = try container.decodeIfPresent(DockPosition.self, forKey: .dockPosition) ?? defaults.dockPosition
        iconSize = min(max(try container.decodeIfPresent(Double.self, forKey: .iconSize) ?? defaults.iconSize, DockingSettingLimits.iconSize.lowerBound), DockingSettingLimits.iconSize.upperBound)
        widgetScale = min(max(try container.decodeIfPresent(Double.self, forKey: .widgetScale) ?? defaults.widgetScale, DockingSettingLimits.widgetScale.lowerBound), DockingSettingLimits.widgetScale.upperBound)
        magnificationEnabled = try container.decodeIfPresent(Bool.self, forKey: .magnificationEnabled) ?? defaults.magnificationEnabled
        magnificationSize = min(max(try container.decodeIfPresent(Double.self, forKey: .magnificationSize) ?? defaults.magnificationSize, DockingSettingLimits.magnificationSize.lowerBound), DockingSettingLimits.magnificationSize.upperBound)
        calendarWidgetSizePreset = try container.decodeIfPresent(WidgetSizePreset.self, forKey: .calendarWidgetSizePreset) ?? defaults.calendarWidgetSizePreset
        weatherWidgetSizePreset = try container.decodeIfPresent(WidgetSizePreset.self, forKey: .weatherWidgetSizePreset) ?? defaults.weatherWidgetSizePreset
        liquidGlassSurfaceStyle = try container.decodeIfPresent(LiquidGlassSurfaceStyle.self, forKey: .liquidGlassSurfaceStyle) ?? defaults.liquidGlassSurfaceStyle
        theme = try container.decodeIfPresent(ThemeMode.self, forKey: .theme) ?? defaults.theme
        accentColorName = try container.decodeIfPresent(String.self, forKey: .accentColorName) ?? defaults.accentColorName
        calendarEnabled = try container.decodeIfPresent(Bool.self, forKey: .calendarEnabled) ?? defaults.calendarEnabled
        calendarLookaheadDays = try container.decodeIfPresent(Int.self, forKey: .calendarLookaheadDays) ?? defaults.calendarLookaheadDays
        calendarMaxEventCount = try container.decodeIfPresent(Int.self, forKey: .calendarMaxEventCount) ?? defaults.calendarMaxEventCount
        calendarShowsLocation = try container.decodeIfPresent(Bool.self, forKey: .calendarShowsLocation) ?? defaults.calendarShowsLocation
        calendarSelectedCalendarIDs = try container.decodeIfPresent([String].self, forKey: .calendarSelectedCalendarIDs) ?? defaults.calendarSelectedCalendarIDs
        weatherEnabled = try container.decodeIfPresent(Bool.self, forKey: .weatherEnabled) ?? defaults.weatherEnabled
        weatherUsesCurrentLocation = try container.decodeIfPresent(Bool.self, forKey: .weatherUsesCurrentLocation) ?? defaults.weatherUsesCurrentLocation
        weatherManualLocation = try container.decodeIfPresent(String.self, forKey: .weatherManualLocation) ?? defaults.weatherManualLocation
        weatherUnit = try container.decodeIfPresent(TemperatureUnit.self, forKey: .weatherUnit) ?? defaults.weatherUnit
        weatherRefreshIntervalMinutes = try container.decodeIfPresent(Int.self, forKey: .weatherRefreshIntervalMinutes) ?? defaults.weatherRefreshIntervalMinutes
        weatherShowsHumidity = try container.decodeIfPresent(Bool.self, forKey: .weatherShowsHumidity) ?? defaults.weatherShowsHumidity
        weatherShowsAQI = try container.decodeIfPresent(Bool.self, forKey: .weatherShowsAQI) ?? defaults.weatherShowsAQI
        dockReplacementModeEnabled = try container.decodeIfPresent(Bool.self, forKey: .dockReplacementModeEnabled) ?? defaults.dockReplacementModeEnabled
    }
}

enum DockingSettingLimits {
    static let autoHideDelay: ClosedRange<Double> = 0.05...2.0
    static let autoHideDelayStep = 0.05
    static let iconSize: ClosedRange<Double> = 24...72
    static let widgetScale: ClosedRange<Double> = 0.75...1.5
    static let magnificationSize: ClosedRange<Double> = 24...128
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
    var effectiveDockThickness: Double { iconSize + 12 }

    var spacing: Double { max(3, iconSize * 0.12) }

    var maximumWidgetScale: Double {
        min(DockingSettingLimits.widgetScale.upperBound, (effectiveDockThickness - 8) / 36)
    }

    var effectiveWidgetScale: Double {
        min(widgetScale, maximumWidgetScale)
    }

    var widgetTileHeight: Double {
        dockPosition.isVertical ? iconSize : 36 * effectiveWidgetScale
    }

    var calendarWidgetWidth: Double {
        dockPosition.isVertical ? iconSize : calendarWidgetSizePreset.contentWidth * effectiveWidgetScale
    }

    var weatherWidgetWidth: Double {
        dockPosition.isVertical ? iconSize : (weatherWidgetSizePreset.contentWidth - 8) * effectiveWidgetScale
    }

    var cornerRadius: Double {
        min(liquidGlassSurfaceStyle.cornerRadius, effectiveDockThickness * 0.34)
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
            return "Open-Meteo"
        case .mock:
            return "Debug mock"
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
    // Weather forecasts are not necessarily for the Mac's current timezone:
    // manual locations can point anywhere in the world. Keep the provider's
    // timezone with the snapshot so the detail panel can format forecast hours
    // in the place the weather describes, not wherever the user happens to be.
    var timeZoneIdentifier: String?
    // Every persisted weather snapshot should identify its provider. Docking is
    // still pre-1.0, so a cache without this field is simply stale data to
    // discard, not a format we need to preserve.
    var dataSource: WeatherDataSource
}

enum DockWidgetKind: String, Identifiable {
    case calendar
    case weather

    var id: String { rawValue }
}
