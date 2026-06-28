import Foundation

final class CompositeWeatherProvider: WeatherProvider {
    private let primary: WeatherProvider
    private let fallback: WeatherProvider

    init(primary: WeatherProvider, fallback: WeatherProvider) {
        self.primary = primary
        self.fallback = fallback
    }

    func fetchWeather(configuration: WeatherRequestConfiguration) async throws -> WeatherSnapshot {
        do {
            return try await primary.fetchWeather(configuration: configuration)
        } catch let providerError as WeatherProviderError {
            switch providerError {
            case .locationDenied, .locationPermissionNeeded, .manualLocationMissing:
                // These errors are user-actionable permission/configuration
                // states. Falling back would either ask for the same missing
                // permission again or hide that the user has not configured a
                // city.
                throw providerError
            case .providerUnavailable, .network:
                DockingLog.weather.notice("Primary weather provider failed; trying fallback: \(providerError.localizedDescription)")
                return try await fallback.fetchWeather(configuration: configuration)
            }
        } catch {
            DockingLog.weather.notice("Primary weather provider failed; trying fallback: \(error.localizedDescription)")
            return try await fallback.fetchWeather(configuration: configuration)
        }
    }
}
