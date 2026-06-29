import CoreLocation
import Foundation
import MapKit
import WeatherKit

final class WeatherKitProvider: WeatherProvider {
    private let weatherService: WeatherService
    private let locationProvider: LocationProviding

    init(
        weatherService: WeatherService = .shared,
        locationProvider: LocationProviding = CoreLocationProvider()
    ) {
        self.weatherService = weatherService
        self.locationProvider = locationProvider
    }

    func fetchWeather(configuration: WeatherRequestConfiguration) async throws -> WeatherSnapshot {
        let location = try await resolveLocation(configuration: configuration)
        let clLocation = CLLocation(latitude: location.latitude, longitude: location.longitude)

        do {
            let weather = try await weatherService.weather(for: clLocation)
            return makeSnapshot(weather: weather, locationName: location.displayName, unit: configuration.unit)
        } catch WeatherError.permissionDenied {
            // WeatherKit entitlement or account problems often surface here.
            // We keep this distinct from CoreLocation denial so the composite
            // provider can fall back to Open-Meteo instead of asking the user to
            // change Location Services unnecessarily.
            throw WeatherProviderError.providerUnavailable("WeatherKit permission was denied for this app bundle.")
        } catch {
            throw WeatherProviderError.providerUnavailable(error.localizedDescription)
        }
    }

    private func resolveLocation(configuration: WeatherRequestConfiguration) async throws -> WeatherLocation {
        if configuration.usesCurrentLocation {
            do {
                return try await locationProvider.currentLocation()
            } catch LocationProviderError.denied, LocationProviderError.restricted {
                throw WeatherProviderError.locationDenied
            } catch LocationProviderError.servicesDisabled {
                throw WeatherProviderError.locationPermissionNeeded
            } catch let error as LocationProviderError {
                throw WeatherProviderError.providerUnavailable(error.localizedDescription)
            } catch {
                throw WeatherProviderError.providerUnavailable(error.localizedDescription)
            }
        }

        guard let manualLocation = configuration.manualLocation?.nilIfBlank else {
            throw WeatherProviderError.manualLocationMissing
        }

        return try await geocode(manualLocation)
    }

    private func geocode(_ query: String) async throws -> WeatherLocation {
        guard let request = MKGeocodingRequest(addressString: query) else {
            throw WeatherProviderError.providerUnavailable("Weather location could not be encoded.")
        }
        request.preferredLocale = .autoupdatingCurrent

        do {
            guard let mapItem = try await request.mapItems.first else {
                throw WeatherProviderError.providerUnavailable("No matching city was found for \"\(query)\".")
            }

            let coordinate = mapItem.location.coordinate
            return WeatherLocation(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                displayName: displayName(for: mapItem, fallback: query)
            )
        } catch let error as WeatherProviderError {
            throw error
        } catch {
            throw WeatherProviderError.providerUnavailable(error.localizedDescription)
        }
    }

    private func displayName(for mapItem: MKMapItem, fallback: String) -> String {
        [
            mapItem.addressRepresentations?.cityWithContext(.full),
            mapItem.address?.shortAddress,
            mapItem.name,
            fallback
        ].compactMap { $0?.nilIfBlank }.first ?? fallback
    }

    private func makeSnapshot(weather: Weather, locationName: String, unit: TemperatureUnit) -> WeatherSnapshot {
        let current = weather.currentWeather
        let targetUnit = unit.foundationUnit

        return WeatherSnapshot(
            locationName: locationName,
            fetchedAt: Date(),
            unit: unit,
            current: CurrentWeatherSummary(
                temperature: current.temperature.converted(to: targetUnit).value,
                feelsLike: current.apparentTemperature.converted(to: targetUnit).value,
                conditionCode: nil,
                conditionLabel: current.condition.description.capitalized,
                symbolName: current.symbolName
            ),
            hourly: weather.hourlyForecast.forecast
                .filter { $0.date >= Date() }
                .prefix(6)
                .map { hour in
                    HourlyWeatherSummary(
                        date: hour.date,
                        temperature: hour.temperature.converted(to: targetUnit).value,
                        conditionCode: nil,
                        symbolName: hour.symbolName
                    )
                },
            daily: weather.dailyForecast.forecast
                .prefix(7)
                .map { day in
                    DailyWeatherSummary(
                        date: day.date,
                        high: day.highTemperature.converted(to: targetUnit).value,
                        low: day.lowTemperature.converted(to: targetUnit).value,
                        conditionCode: nil,
                        symbolName: day.symbolName
                    )
                },
            humidity: current.humidity,
            airQualityLabel: nil,
            dataSource: .weatherKit
        )
    }
}

private extension TemperatureUnit {
    var foundationUnit: UnitTemperature {
        switch self {
        case .celsius:
            return .celsius
        case .fahrenheit:
            return .fahrenheit
        }
    }
}
