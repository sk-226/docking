import SwiftUI

struct WeatherWidgetView: View {
    @EnvironmentObject private var model: DockingAppModel

    var body: some View {
        let presentation = WeatherDockPresentation(
            snapshot: model.weatherViewModel.snapshot,
            state: model.weatherViewModel.state,
            settings: model.settings
        )

        DockWidgetShell(
            title: "Weather",
            systemImage: presentation.symbolName,
            iconStyle: presentation.tone.iconStyle,
            iconScale: model.settings.weatherWidgetSizePreset == .detailed ? 1.7 : 1.45,
            width: model.settings.weatherWidgetWidth,
            height: model.settings.widgetTileHeight
        ) {
            model.toggleWidgetPanel(.weather)
        } content: {
            WeatherDockContent(
                presentation: presentation,
                isDetailed: model.settings.weatherWidgetSizePreset == .detailed
            )
        }
        .background(WidgetFrameReporter(kind: .weather))
    }
}

private struct WeatherDockContent: View {
    let presentation: WeatherDockPresentation
    let isDetailed: Bool

    var body: some View {
        if isDetailed {
            HStack(alignment: .center, spacing: 7) {
                primaryStack

                if !presentation.detailLines.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(presentation.detailLines.prefix(3).enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(size: index == 0 ? 10.5 : 9.5, weight: .medium))
                                .foregroundStyle(index == 0 ? .primary : .secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .allowsTightening(true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } else {
            primaryStack
        }
    }

    private var primaryStack: some View {
        VStack(alignment: .leading, spacing: isDetailed ? 2 : 1) {
            Text(presentation.primary)
                .font(.system(size: isDetailed ? 21 : 18, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .allowsTightening(true)

            Text(presentation.secondary)
                .font(.system(size: isDetailed ? 11.5 : 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .allowsTightening(true)
        }
    }
}

struct WeatherDockPresentation {
    let primary: String
    let secondary: String
    let detailLines: [String]
    let symbolName: String
    let tone: WeatherConditionTone

    var tertiary: String? {
        detailLines.isEmpty ? nil : detailLines.joined(separator: " - ")
    }

    init(snapshot: WeatherSnapshot?, state: WeatherWidgetState, settings: DockingSettings) {
        guard let snapshot else {
            switch state {
            case .manualLocationNotSet:
                self.init(primary: "--", secondary: "Set city", detailLines: [], symbolName: "location.slash", tone: .neutral)
            case .locationPermissionNeeded:
                self.init(primary: "--", secondary: "Location", detailLines: [], symbolName: "location", tone: .neutral)
            case .locationDenied:
                self.init(primary: "--", secondary: "Location off", detailLines: [], symbolName: "location.slash", tone: .neutral)
            case .loading:
                self.init(primary: "...", secondary: "Weather", detailLines: [], symbolName: "cloud", tone: .neutral)
            default:
                self.init(primary: "--", secondary: "Weather", detailLines: [], symbolName: "cloud", tone: .neutral)
            }
            return
        }

        let temperature = DockingFormatters.temperature(snapshot.current.temperature, unit: snapshot.unit)
        let location = WeatherDockLocationDisplay.name(snapshotLocationName: snapshot.locationName, settings: settings)
        let tone = WeatherConditionTone.resolve(
            conditionCode: snapshot.current.conditionCode,
            symbolName: snapshot.current.symbolName
        )

        var metrics: [String] = []
        if let today = snapshot.daily.first {
            metrics.append(
                "H \(DockingFormatters.temperature(today.high, unit: snapshot.unit)) / L \(DockingFormatters.temperature(today.low, unit: snapshot.unit))"
            )
        }
        if settings.weatherShowsHumidity, let humidity = snapshot.humidity {
            let percent = Int((humidity > 1 ? humidity : humidity * 100).rounded())
            metrics.append("Humidity \(percent)%")
        } else if let feelsLike = snapshot.current.feelsLike {
            metrics.append("Feels \(DockingFormatters.temperature(feelsLike, unit: snapshot.unit))")
        } else if settings.weatherShowsAQI, let airQualityLabel = snapshot.airQualityLabel?.nilIfBlank {
            metrics.append("AQI \(airQualityLabel)")
        }

        // Weather widgets need a different hierarchy from Calendar widgets:
        // the state of the sky should be readable before the user parses
        // labels. We keep location and metrics on the optional third line so a
        // wider tile buys information density without taking more vertical dock
        // space or making administrative place names the visual headline.
        self.init(
            primary: temperature,
            secondary: snapshot.current.conditionLabel,
            detailLines: [location] + metrics,
            symbolName: WeatherWidgetSymbol.name(for: snapshot.current.symbolName),
            tone: tone
        )
    }

    private init(primary: String, secondary: String, detailLines: [String], symbolName: String, tone: WeatherConditionTone) {
        self.primary = primary
        self.secondary = secondary
        self.detailLines = detailLines
        self.symbolName = symbolName
        self.tone = tone
    }
}

enum WeatherConditionTone: Equatable {
    case clear
    case partlyCloudy
    case cloudy
    case fog
    case rain
    case snow
    case storm
    case neutral

    static func resolve(conditionCode: Int?, symbolName: String) -> WeatherConditionTone {
        // Provider labels are localized prose and SF Symbols can vary between
        // WeatherKit and Open-Meteo mappings. Prefer the numeric weather code
        // when we have it because it is the stable semantic source; keep the
        // symbol fallback for WeatherKit snapshots that do not expose a WMO
        // code. This avoids hard-coding English condition strings into the UI.
        if let conditionCode {
            switch conditionCode {
            case 0:
                return .clear
            case 1...2:
                return .partlyCloudy
            case 3:
                return .cloudy
            case 45, 48:
                return .fog
            case 51...67, 80...82:
                return .rain
            case 71...77:
                return .snow
            case 95...99:
                return .storm
            default:
                break
            }
        }

        if symbolName.contains("bolt") {
            return .storm
        }
        if symbolName.contains("rain") || symbolName.contains("drizzle") {
            return .rain
        }
        if symbolName.contains("snow") {
            return .snow
        }
        if symbolName.contains("fog") {
            return .fog
        }
        if symbolName.contains("sun") && symbolName.contains("cloud") {
            return .partlyCloudy
        }
        if symbolName.contains("sun") {
            return .clear
        }
        if symbolName.contains("cloud") {
            return .cloudy
        }
        return .neutral
    }

    var iconStyle: DockWidgetIconStyle {
        switch self {
        case .neutral:
            return .neutral
        default:
            // Do not copy or bundle Apple's Weather.app icon. Docking is its
            // own app, and using another app's icon for a widget would be
            // misleading if this ever leaves a personal build. Multicolor SF
            // Symbols are the native system-provided alternative: they keep
            // the weather glyphs close to Apple's visual language without
            // treating Apple app artwork as our asset.
            return .systemMulticolor
        }
    }
}

struct WeatherWidgetSymbolImage: View {
    let symbolName: String
    let accessibilityLabel: String?

    init(_ symbolName: String, accessibilityLabel: String? = nil) {
        self.symbolName = symbolName
        self.accessibilityLabel = accessibilityLabel
    }

    @ViewBuilder
    var body: some View {
        let image = Image(systemName: WeatherWidgetSymbol.name(for: symbolName))
            .symbolRenderingMode(.multicolor)

        if let accessibilityLabel {
            image.accessibilityLabel(accessibilityLabel)
        } else {
            image.accessibilityHidden(true)
        }
    }
}

enum WeatherWidgetSymbol {
    static func name(for providerSymbolName: String) -> String {
        // The provider-facing symbols are often outline variants because they
        // also work in text-heavy panels. Docking's weather widget should feel
        // closer to macOS Weather across both the compact dock tile and the
        // expanded panel, so filled multicolor SF Symbols are the common
        // presentation. Keep this as an explicit map rather than blindly
        // appending ".fill"; not every SF Symbol has a fill variant, and a
        // missing system symbol would render as an empty widget icon.
        switch providerSymbolName {
        case "sun.max":
            return "sun.max.fill"
        case "cloud.sun":
            return "cloud.sun.fill"
        case "cloud":
            return "cloud.fill"
        case "cloud.fog":
            return "cloud.fog.fill"
        case "cloud.rain":
            return "cloud.rain.fill"
        case "cloud.snow":
            return "cloud.snow.fill"
        case "cloud.bolt.rain":
            return "cloud.bolt.rain.fill"
        default:
            return providerSymbolName
        }
    }
}

enum WeatherDockLocationDisplay {
    static func name(snapshotLocationName: String, settings: DockingSettings) -> String {
        if let manualLocation = settings.weatherManualLocation.nilIfBlank,
           shouldPreferManualLocation(manualLocation, snapshotLocationName: snapshotLocationName, settings: settings) {
            return compactName(manualLocation)
        }

        return compactName(snapshotLocationName)
    }

    private static func shouldPreferManualLocation(
        _ manualLocation: String,
        snapshotLocationName: String,
        settings: DockingSettings
    ) -> Bool {
        // The dock tile is glanceable UI. When the user typed "Setagaya", the
        // expanded geocoder result is not more useful in the dock; it is mostly
        // a confirmation of information the user already supplied. Current-
        // location weather is different, because a manual city may only be a
        // fallback. In that case we use the manual label only when the loaded
        // snapshot clearly appears to be that fallback location.
        if !settings.weatherUsesCurrentLocation {
            return true
        }

        let loadedLocation = compactName(snapshotLocationName)
        let requestedLocation = compactName(manualLocation)
        return loadedLocation.range(of: requestedLocation, options: [.caseInsensitive, .diacriticInsensitive]) != nil ||
            requestedLocation.range(of: loadedLocation, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    private static func compactName(_ rawName: String) -> String {
        // Geocoders return provider-friendly labels such as
        // "Setagaya City, Tokyo, Japan", but the dock tile is not a place
        // picker and does not have enough horizontal space for administrative
        // hierarchy. We intentionally keep only the first meaningful locality
        // and strip common English/Japanese ward suffixes. The detail panel can
        // still show the full provider label; this helper is only for the dock's
        // glanceable surface.
        let firstComponent = rawName
            .split(whereSeparator: { $0 == "," || $0 == "、" })
            .first
            .map(String.init) ?? rawName
        var name = firstComponent.trimmingCharacters(in: .whitespacesAndNewlines)

        for suffix in [" City", " city", " Ward", " ward", "-ku", " Ku", " ku"] {
            if name.hasSuffix(suffix) {
                name.removeLast(suffix.count)
                return name.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return name
    }
}
