import Foundation

struct WeatherRequestConfiguration: Equatable {
    var manualLocation: String?
    var usesCurrentLocation: Bool
    var unit: TemperatureUnit
}

struct WeatherLocation: Equatable {
    var latitude: Double
    var longitude: Double
    var displayName: String
}

enum WeatherProviderError: LocalizedError, Equatable {
    case locationPermissionNeeded
    case locationDenied
    case manualLocationMissing
    case providerUnavailable(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .locationPermissionNeeded:
            return "Location access is off. Choose a city manually or enable Location Services."
        case .locationDenied:
            return "Location access was denied. Choose a city manually or enable Location Services."
        case .manualLocationMissing:
            return "Choose a city in Control Center to load weather without Location Services."
        case .providerUnavailable(let message):
            return message
        case .network(let message):
            return "Weather couldn't be updated. \(message)"
        }
    }
}

protocol WeatherProvider {
    func fetchWeather(configuration: WeatherRequestConfiguration) async throws -> WeatherSnapshot
}

protocol LocationProviding: AnyObject {
    func currentLocation() async throws -> WeatherLocation
}
