import SwiftUI

struct WeatherDetailPanelView: View {
    @EnvironmentObject private var model: DockingAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(locationTitle)
                        .font(.title2.weight(.semibold))
                    Text(statusText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await model.weatherViewModel.refresh(settings: model.settings, force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .dockTooltip("Refresh weather")
                .accessibilityLabel("Refresh weather")
                .accessibilityHint("Reloads the weather forecast")
            }

            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dockingSurface(settings: model.settings, cornerRadius: 18)
        .task {
            await model.weatherViewModel.refreshIfNeeded(settings: model.settings)
        }
    }

    private var statusText: String {
        switch model.weatherViewModel.state {
        case .stale:
            return compactStatus(prefix: "Cached") ?? "Cached"
        case .manualLocationNotSet:
            return "Choose a city in Control Center."
        case .locationPermissionNeeded:
            return "Location permission or manual city needed."
        case .loading:
            return "Updating..."
        default:
            return compactStatus(prefix: "Updated") ?? "Not loaded"
        }
    }

    private var locationTitle: String {
        guard let snapshot = model.weatherViewModel.snapshot else {
            return "Weather"
        }

        // The weather panel is still a widget surface, not a location picker.
        // Showing the geocoder's full administrative label makes the header
        // compete with the forecast itself, so use the same concise label as
        // the dock tile and reserve the panel's space for weather information.
        return WeatherDockLocationDisplay.name(
            snapshotLocationName: snapshot.locationName,
            settings: model.settings
        )
    }

    private func compactStatus(prefix: String) -> String? {
        guard let fetchedAt = model.weatherViewModel.snapshot?.fetchedAt else {
            return prefix
        }

        return "\(prefix) · \(DockingFormatters.timeFormatter.string(from: fetchedAt))"
    }

    @ViewBuilder
    private var content: some View {
        switch model.weatherViewModel.state {
        case .idle, .loading:
            if let snapshot = model.weatherViewModel.snapshot {
                WeatherSnapshotContent(snapshot: snapshot, settings: model.settings)
            } else {
                ProgressView("Loading weather...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .manualLocationNotSet:
            PermissionStateView(
                systemImage: "location.slash",
                title: "Manual location not set",
                message: "Set a city in Control Center to load weather without Location Services."
            )
        case .locationPermissionNeeded:
            PermissionStateView(
                systemImage: "location",
                title: "Location access is needed",
                message: "Choose a city manually or enable Location Services for current-location weather."
            )
        case .locationDenied:
            PermissionStateView(
                systemImage: "lock.slash",
                title: "Location access is off",
                message: "Choose a city manually or enable Location Services."
            )
        case .loaded, .stale:
            if let snapshot = model.weatherViewModel.snapshot {
                WeatherSnapshotContent(snapshot: snapshot, settings: model.settings)
            } else {
                EmptyView()
            }
        case .error(let message):
            PermissionStateView(
                systemImage: "exclamationmark.triangle",
                title: "Weather could not load",
                message: message
            )
        }
    }
}

private struct WeatherSnapshotContent: View {
    let snapshot: WeatherSnapshot
    let settings: DockingSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 14) {
                Text(DockingFormatters.temperature(snapshot.current.temperature, unit: snapshot.unit))
                    .font(.system(size: 52, weight: .semibold, design: .rounded))
                VStack(alignment: .leading, spacing: 4) {
                    WeatherWidgetSymbolImage(snapshot.current.symbolName, accessibilityLabel: snapshot.current.conditionLabel)
                        .font(.system(size: 34, weight: .semibold))
                    Text(snapshot.current.conditionLabel)
                        .font(.headline)
                    if let feelsLike = snapshot.current.feelsLike {
                        Text("Feels like \(DockingFormatters.temperature(feelsLike, unit: snapshot.unit))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            HStack(spacing: 10) {
                ForEach(snapshot.hourly.prefix(6)) { hour in
                    VStack(spacing: 5) {
                        Text(DockingFormatters.timeFormatter.string(from: hour.date))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        WeatherWidgetSymbolImage(hour.symbolName)
                            .font(.system(size: 17, weight: .medium))
                        Text(DockingFormatters.temperature(hour.temperature, unit: snapshot.unit))
                            .font(.caption.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            VStack(spacing: 8) {
                if settings.weatherShowsHumidity, let humidity = snapshot.humidity {
                    WeatherMetricRow(title: "Humidity", value: "\(Int((humidity > 1 ? humidity : humidity * 100).rounded()))%")
                }
                if settings.weatherShowsAQI, let airQualityLabel = snapshot.airQualityLabel {
                    WeatherMetricRow(title: "Air Quality", value: airQualityLabel)
                }
            }

            HStack(spacing: 10) {
                ForEach(snapshot.daily.prefix(5)) { day in
                    VStack(spacing: 5) {
                        Text(DockingFormatters.weekdayFormatter.string(from: day.date))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        WeatherWidgetSymbolImage(day.symbolName)
                            .font(.system(size: 17, weight: .medium))
                        Text("\(Int(day.high.rounded()))/\(Int(day.low.rounded()))")
                            .font(.caption.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

private struct WeatherMetricRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
    }
}
