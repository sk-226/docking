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
    private var refreshTask: Task<Bool, Never>?
    private var refreshGeneration = 0
    private var scheduledRefreshTask: Task<Void, Never>?
    private var currentSettings: DockingSettings = .default
    private let now: () -> Date
    private let sleep: WidgetRefreshSleep
    private static let missingManualLocationWithCacheMessage = "Showing cached weather. Choose a city in Control Center to update."

    init(
        provider: WeatherProvider,
        cache: WeatherCache = WeatherCache(),
        now: @escaping () -> Date = Date.init,
        sleep: @escaping WidgetRefreshSleep = WidgetRefreshSchedule.sleep(until:)
    ) {
        self.provider = provider
        self.cache = cache
        self.now = now
        self.sleep = sleep
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
        currentSettings = settings
        guard settings.weatherEnabled else {
            cancelRefresh()
            return
        }

        if cacheDecision(settings: settings) == .useCache {
            state = .loaded
            scheduleNextRefresh()
            return
        }

        await refresh(settings: settings, force: false)
    }

    func refresh(settings: DockingSettings, force: Bool) async {
        currentSettings = settings
        guard settings.weatherEnabled else {
            // Disabled widgets should be inert even if a caller reaches the
            // ViewModel directly. Canceling here prevents a previously-started
            // provider request from publishing a late weather update after the
            // user turned the widget off.
            cancelRefresh()
            return
        }

        if !force, cacheDecision(settings: settings) == .useCache {
            state = .loaded
            scheduleNextRefresh()
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
            cancelScheduledRefresh()
            // A cached forecast is still useful, but the user also needs to
            // know why it cannot refresh. The stale message therefore names
            // both facts instead of showing a bare "choose a city" prompt next
            // to real weather data, which looked like a contradictory state.
            state = snapshot == nil ? .manualLocationNotSet : .stale(Self.missingManualLocationWithCacheMessage)
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
        let manualFallbackConfiguration = Self.manualFallbackConfiguration(from: settings)
        let requestKey = settings.weatherRequestKey

        let task = Task { [provider, cache, manualFallbackConfiguration] in
            func publish(_ fetched: WeatherSnapshot) async {
                var keyed = fetched
                keyed.requestKey = requestKey
                let loaded = keyed
                await MainActor.run {
                    self.snapshot = loaded
                    self.state = .loaded
                    cache.save(loaded)
                }
            }

            // The Bool says whether retrying later on a timer can succeed.
            // Missing city and location-permission outcomes need the user to
            // act, and those actions already trigger a refresh through the
            // settings or permission flow.
            func publishManualFallbackOrLocationState(
                emptyState: WeatherWidgetState,
                staleMessage: String
            ) async -> Bool {
                guard let manualFallbackConfiguration else {
                    await MainActor.run { self.state = self.snapshot == nil ? emptyState : .stale(staleMessage) }
                    return false
                }

                do {
                    let loaded = try await provider.fetchWeather(configuration: manualFallbackConfiguration)
                    guard !Task.isCancelled else {
                        return false
                    }
                    await publish(loaded)
                } catch {
                    guard !Task.isCancelled else {
                        return false
                    }
                    await MainActor.run {
                        let message = "Current location could not be used, and manual city fallback also failed. \(error.localizedDescription)"
                        self.state = self.snapshot == nil ? .error(message) : .stale(message)
                    }
                }
                return true
            }

            do {
                let loaded = try await provider.fetchWeather(configuration: configuration)
                guard !Task.isCancelled else {
                    return false
                }
                await publish(loaded)
                return true
            } catch WeatherProviderError.manualLocationMissing {
                guard !Task.isCancelled else {
                    return false
                }
                await MainActor.run {
                    self.state = self.snapshot == nil ? .manualLocationNotSet : .stale(Self.missingManualLocationWithCacheMessage)
                }
                return false
            } catch WeatherProviderError.locationPermissionNeeded {
                guard !Task.isCancelled else {
                    return false
                }
                return await publishManualFallbackOrLocationState(
                    emptyState: .locationPermissionNeeded,
                    staleMessage: "Location access is needed to update weather."
                )
            } catch WeatherProviderError.locationDenied {
                guard !Task.isCancelled else {
                    return false
                }
                return await publishManualFallbackOrLocationState(
                    emptyState: .locationDenied,
                    staleMessage: "Location access is denied. Showing cached weather."
                )
            } catch {
                guard !Task.isCancelled else {
                    return false
                }
                await MainActor.run {
                    if self.snapshot != nil {
                        self.state = .stale(error.localizedDescription)
                    } else {
                        self.state = .error(error.localizedDescription)
                    }
                }
                return true
            }
        }

        refreshTask = task
        state = .loading
        let canRetryLater = await task.value
        if refreshGeneration == generation {
            if canRetryLater {
                scheduleNextRefresh()
            } else {
                cancelScheduledRefresh()
            }
        }
        clearRefreshTask(generation: generation)
    }

    func cancelRefresh() {
        refreshGeneration += 1
        refreshTask?.cancel()
        refreshTask = nil
        cancelScheduledRefresh()
        if state == .loading {
            state = snapshot == nil ? .idle : .stale("Showing cached weather until the next refresh succeeds.")
        }
    }

    private func cacheDecision(settings: DockingSettings) -> WidgetRefreshDecision {
        WidgetRefreshDecision.weather(
            snapshot: snapshot,
            currentKey: settings.weatherRequestKey,
            intervalMinutes: settings.weatherRefreshIntervalMinutes,
            now: now()
        )
    }

    private func scheduleNextRefresh() {
        cancelScheduledRefresh()
        guard currentSettings.weatherEnabled else {
            return
        }

        let deadline = WidgetRefreshSchedule.nextWeatherRefresh(
            fetchedAt: snapshot?.fetchedAt,
            intervalMinutes: currentSettings.weatherRefreshIntervalMinutes,
            now: now()
        )
        let sleep = self.sleep
        scheduledRefreshTask = Task { [weak self] in
            do {
                try await sleep(deadline)
            } catch {
                return
            }
            guard !Task.isCancelled, let self else {
                return
            }
            self.scheduledRefreshTask = nil
            await self.refreshIfNeeded(settings: self.currentSettings)
        }
    }

    private func cancelScheduledRefresh() {
        scheduledRefreshTask?.cancel()
        scheduledRefreshTask = nil
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

    private static func manualFallbackConfiguration(from settings: DockingSettings) -> WeatherRequestConfiguration? {
        guard settings.weatherUsesCurrentLocation,
              settings.weatherManualLocation.nilIfBlank != nil else {
            return nil
        }

        // The Weather settings intentionally let users keep a manual city even
        // while "Use current location" is enabled. That city is not redundant:
        // it is the privacy-preserving fallback when CoreLocation is denied,
        // disabled, or unavailable. We build a second provider request instead
        // of special-casing Open-Meteo here so WeatherKit, Open-Meteo, and any
        // future provider keep one shared request contract.
        return WeatherRequestConfiguration(
            manualLocation: settings.weatherManualLocation,
            usesCurrentLocation: false,
            unit: settings.weatherUnit
        )
    }
}
