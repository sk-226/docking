import Foundation

enum WeatherWidgetState: Equatable {
    case idle
    case loading
    case locationPermissionNeeded
    case locationDenied
    case manualLocationNotSet
    case loaded
    case stale(String)
    case error(String)
}

@MainActor
final class WeatherWidgetViewModel: ObservableObject {
    @Published private(set) var state: WeatherWidgetState = .idle
    @Published private(set) var snapshot: WeatherSnapshot?

    private let provider: WeatherProvider
    private let cache: WeatherCache
    private var refreshTask: Task<Void, Never>?
    private var refreshGeneration = 0

    init(provider: WeatherProvider, cache: WeatherCache = WeatherCache()) {
        self.provider = provider
        self.cache = cache
        self.snapshot = cache.load()
        if snapshot != nil {
            state = .stale("Showing cached weather until the next refresh succeeds.")
        }
    }

    var compactText: (primary: String, secondary: String, symbol: String) {
        guard let snapshot else {
            switch state {
            case .manualLocationNotSet:
                return ("--", "Set city", "location.slash")
            case .locationPermissionNeeded:
                return ("--", "Location", "location")
            case .loading:
                return ("...", "Weather", "cloud")
            default:
                return ("--", "Weather", "cloud")
            }
        }

        return (
            DockingFormatters.temperature(snapshot.current.temperature, unit: snapshot.unit),
            snapshot.current.conditionLabel,
            snapshot.current.symbolName
        )
    }

    var isRefreshing: Bool {
        refreshTask != nil
    }

    func refreshIfNeeded(settings: DockingSettings) async {
        guard settings.weatherEnabled else {
            cancelRefresh()
            return
        }

        if let snapshot, WeatherCache.isFresh(snapshot, intervalMinutes: settings.weatherRefreshIntervalMinutes) {
            state = .loaded
            return
        }

        await refresh(settings: settings, force: false)
    }

    func refresh(settings: DockingSettings, force: Bool) async {
        guard settings.weatherEnabled else {
            // Disabled widgets should be inert even if a caller reaches the
            // ViewModel directly. Canceling here prevents a previously-started
            // provider request from publishing a late weather update after the
            // user turned the widget off.
            cancelRefresh()
            return
        }

        if !force,
           let snapshot,
           WeatherCache.isFresh(snapshot, intervalMinutes: settings.weatherRefreshIntervalMinutes) {
            state = .loaded
            return
        }

        guard settings.weatherUsesCurrentLocation || settings.weatherManualLocation.nilIfBlank != nil else {
            // A blank manual city is a local configuration problem, not a
            // provider problem. Handling it here prevents unnecessary
            // WeatherKit/Open-Meteo work and keeps the privacy boundary obvious:
            // no location or network request is attempted until the user gives
            // either a city or current-location permission.
            refreshGeneration += 1
            refreshTask?.cancel()
            refreshTask = nil
            state = snapshot == nil ? .manualLocationNotSet : .stale("Choose a city to update weather.")
            return
        }

        refreshGeneration += 1
        let generation = refreshGeneration
        refreshTask?.cancel()
        let configuration = WeatherRequestConfiguration(
            manualLocation: settings.weatherManualLocation,
            usesCurrentLocation: settings.weatherUsesCurrentLocation,
            unit: settings.weatherUnit
        )

        let task = Task { [provider, cache] in
            do {
                let loaded = try await provider.fetchWeather(configuration: configuration)
                guard !Task.isCancelled else {
                    return
                }
                await MainActor.run {
                    self.snapshot = loaded
                    self.state = .loaded
                    cache.save(loaded)
                }
            } catch WeatherProviderError.manualLocationMissing {
                guard !Task.isCancelled else {
                    return
                }
                await MainActor.run { self.state = self.snapshot == nil ? .manualLocationNotSet : .stale("Choose a city to update weather.") }
            } catch WeatherProviderError.locationPermissionNeeded {
                guard !Task.isCancelled else {
                    return
                }
                await MainActor.run { self.state = self.snapshot == nil ? .locationPermissionNeeded : .stale("Location access is needed to update weather.") }
            } catch WeatherProviderError.locationDenied {
                guard !Task.isCancelled else {
                    return
                }
                await MainActor.run { self.state = self.snapshot == nil ? .locationDenied : .stale("Location access is denied. Showing cached weather.") }
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                await MainActor.run {
                    if self.snapshot != nil {
                        self.state = .stale(error.localizedDescription)
                    } else {
                        self.state = .error(error.localizedDescription)
                    }
                }
            }
        }

        refreshTask = task
        state = .loading
        _ = await task.result
        clearRefreshTask(generation: generation)
    }

    func cancelRefresh() {
        refreshGeneration += 1
        refreshTask?.cancel()
        refreshTask = nil
        if state == .loading {
            state = snapshot == nil ? .idle : .stale("Showing cached weather until the next refresh succeeds.")
        }
    }

    private func clearRefreshTask(generation: Int) {
        // Weather refreshes can be started from launch, panel open, settings
        // changes, and the manual refresh button. A generation guard keeps an
        // older completion from erasing a newer in-flight task reference after
        // it has been cancelled and replaced.
        guard refreshGeneration == generation else {
            return
        }
        refreshTask = nil
    }
}
