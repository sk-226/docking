import SwiftUI

struct WeatherWidgetView: View {
    @EnvironmentObject private var model: DockingAppModel

    var body: some View {
        DockWidgetShell(
            title: "Weather",
            systemImage: compact.symbol,
            width: model.settings.weatherWidgetWidth,
            height: model.settings.widgetTileHeight
        ) {
            model.toggleWidgetPanel(.weather)
        } content: {
            if model.settings.weatherWidgetSizePreset == .detailed {
                WeatherDetailedDockContent(
                    snapshot: model.weatherViewModel.snapshot,
                    state: model.weatherViewModel.state,
                    settings: model.settings
                )
            } else {
                DockWidgetLine(compact.primary, font: .system(size: 16, weight: .semibold, design: .rounded))
                DockWidgetLine(compact.secondary, font: .caption2, isSecondary: true)
            }
        }
        .background(WidgetFrameReporter(kind: .weather))
    }

    private var compact: (primary: String, secondary: String, symbol: String) {
        model.weatherViewModel.compactText
    }
}

private struct WeatherDetailedDockContent: View {
    let snapshot: WeatherSnapshot?
    let state: WeatherWidgetState
    let settings: DockingSettings

    var body: some View {
        let content = detailedText

        VStack(spacing: 1) {
            DockWidgetLine(content.primary, font: .caption.weight(.semibold))
            DockWidgetLine(content.secondary, font: .caption2, isSecondary: true)
            if let tertiary = content.tertiary {
                DockWidgetLine(tertiary, font: .system(size: 9), isSecondary: true)
            }
        }
    }

    private var detailedText: (primary: String, secondary: String, tertiary: String?) {
        guard let snapshot else {
            switch state {
            case .manualLocationNotSet:
                return ("Set city", "Weather", nil)
            case .locationPermissionNeeded:
                return ("Location", "Needed", nil)
            case .locationDenied:
                return ("Location", "Off", nil)
            case .loading:
                return ("Loading", "Weather", nil)
            default:
                return ("Weather", "Not loaded", nil)
            }
        }

        let temperature = DockingFormatters.temperature(snapshot.current.temperature, unit: snapshot.unit)
        let secondary = "\(temperature) \(snapshot.current.conditionLabel)"
        let location = WeatherDockLocationDisplay.name(snapshotLocationName: snapshot.locationName, settings: settings)
        if settings.weatherShowsHumidity, let humidity = snapshot.humidity {
            let percent = Int((humidity > 1 ? humidity : humidity * 100).rounded())
            return (location, secondary, "Humidity \(percent)%")
        }
        if let feelsLike = snapshot.current.feelsLike {
            return (location, secondary, "Feels \(DockingFormatters.temperature(feelsLike, unit: snapshot.unit))")
        }
        // Location is the key extra context for a larger dock weather tile.
        // If optional metrics are unavailable, keep the third line off instead
        // of inventing placeholder data that would make the dock look stale.
        return (location, secondary, nil)
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
