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
        if settings.weatherShowsHumidity, let humidity = snapshot.humidity {
            let percent = Int((humidity > 1 ? humidity : humidity * 100).rounded())
            return (snapshot.locationName, secondary, "Humidity \(percent)%")
        }
        if let feelsLike = snapshot.current.feelsLike {
            return (snapshot.locationName, secondary, "Feels \(DockingFormatters.temperature(feelsLike, unit: snapshot.unit))")
        }
        // Location is the key extra context for a larger dock weather tile.
        // If optional metrics are unavailable, keep the third line off instead
        // of inventing placeholder data that would make the dock look stale.
        return (snapshot.locationName, secondary, nil)
    }
}
