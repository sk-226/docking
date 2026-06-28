import Foundation

final class OpenMeteoWeatherProvider: WeatherProvider {
    private let session: URLSession
    private let locationProvider: LocationProviding

    init(session: URLSession = .shared, locationProvider: LocationProviding = CoreLocationProvider()) {
        self.session = session
        self.locationProvider = locationProvider
    }

    func fetchWeather(configuration: WeatherRequestConfiguration) async throws -> WeatherSnapshot {
        if configuration.usesCurrentLocation {
            do {
                let location = try await locationProvider.currentLocation()
                return try await forecast(
                    latitude: location.latitude,
                    longitude: location.longitude,
                    locationName: location.displayName,
                    unit: configuration.unit
                )
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

        guard let location = configuration.manualLocation?.nilIfBlank else {
            throw WeatherProviderError.manualLocationMissing
        }

        let place = try await geocode(location)
        return try await forecast(
            latitude: place.latitude,
            longitude: place.longitude,
            locationName: place.displayName,
            unit: configuration.unit
        )
    }

    private func geocode(_ query: String) async throws -> GeocodingPlace {
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")
        components?.queryItems = [
            URLQueryItem(name: "name", value: query),
            URLQueryItem(name: "count", value: "1"),
            URLQueryItem(name: "language", value: Locale.autoupdatingCurrent.language.languageCode?.identifier ?? "en"),
            URLQueryItem(name: "format", value: "json")
        ]

        guard let url = components?.url else {
            throw WeatherProviderError.providerUnavailable("Weather location could not be encoded.")
        }

        do {
            let (data, _) = try await session.data(from: url)
            let response = try JSONDecoder().decode(GeocodingResponse.self, from: data)
            guard let place = response.results?.first else {
                throw WeatherProviderError.providerUnavailable("No matching city was found for \"\(query)\".")
            }
            return place
        } catch let error as WeatherProviderError {
            throw error
        } catch {
            throw WeatherProviderError.network(error.localizedDescription)
        }
    }

    private func forecast(latitude: Double, longitude: Double, locationName: String, unit: TemperatureUnit) async throws -> WeatherSnapshot {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: "\(latitude)"),
            URLQueryItem(name: "longitude", value: "\(longitude)"),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,relative_humidity_2m,weather_code"),
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "forecast_days", value: "7"),
            URLQueryItem(name: "temperature_unit", value: unit == .fahrenheit ? "fahrenheit" : "celsius"),
            URLQueryItem(name: "timezone", value: "auto")
        ]

        guard let url = components?.url else {
            throw WeatherProviderError.providerUnavailable("Weather request could not be encoded.")
        }

        do {
            let (data, _) = try await session.data(from: url)
            let response = try JSONDecoder().decode(ForecastResponse.self, from: data)
            return response.snapshot(locationName: locationName, unit: unit)
        } catch let error as WeatherProviderError {
            throw error
        } catch {
            throw WeatherProviderError.network(error.localizedDescription)
        }
    }
}

private struct GeocodingResponse: Decodable {
    var results: [GeocodingPlace]?
}

private struct GeocodingPlace: Decodable {
    var name: String
    var latitude: Double
    var longitude: Double
    var country: String?
    var admin1: String?

    var displayName: String {
        [name, admin1, country]
            .compactMap { $0?.nilIfBlank }
            .joined(separator: ", ")
    }
}

private struct ForecastResponse: Decodable {
    var current: CurrentBlock
    var hourly: HourlyBlock
    var daily: DailyBlock

    func snapshot(locationName: String, unit: TemperatureUnit) -> WeatherSnapshot {
        let code = current.weatherCode
        return WeatherSnapshot(
            locationName: locationName,
            fetchedAt: Date(),
            unit: unit,
            current: CurrentWeatherSummary(
                temperature: current.temperature,
                feelsLike: current.apparentTemperature,
                conditionCode: code,
                conditionLabel: WeatherCodeMapping.label(for: code),
                symbolName: WeatherCodeMapping.symbolName(for: code)
            ),
            hourly: hourly.items().prefix(6).map { $0 },
            daily: daily.items().prefix(7).map { $0 },
            humidity: current.relativeHumidity,
            airQualityLabel: nil
        )
    }
}

private struct CurrentBlock: Decodable {
    var temperature: Double
    var apparentTemperature: Double?
    var relativeHumidity: Double?
    var weatherCode: Int?

    enum CodingKeys: String, CodingKey {
        case temperature = "temperature_2m"
        case apparentTemperature = "apparent_temperature"
        case relativeHumidity = "relative_humidity_2m"
        case weatherCode = "weather_code"
    }
}

private struct HourlyBlock: Decodable {
    var time: [String]
    var temperature: [Double]
    var weatherCode: [Int?]

    enum CodingKeys: String, CodingKey {
        case time
        case temperature = "temperature_2m"
        case weatherCode = "weather_code"
    }

    func items() -> [HourlyWeatherSummary] {
        zip3(time, temperature, weatherCode).compactMap { rawTime, temperature, code in
            guard let date = OpenMeteoDateParsers.hourly.date(from: rawTime), date >= Date() else {
                return nil
            }
            return HourlyWeatherSummary(
                date: date,
                temperature: temperature,
                conditionCode: code,
                symbolName: WeatherCodeMapping.symbolName(for: code)
            )
        }
    }
}

private struct DailyBlock: Decodable {
    var time: [String]
    var weatherCode: [Int?]
    var high: [Double]
    var low: [Double]

    enum CodingKeys: String, CodingKey {
        case time
        case weatherCode = "weather_code"
        case high = "temperature_2m_max"
        case low = "temperature_2m_min"
    }

    func items() -> [DailyWeatherSummary] {
        zip4(time, weatherCode, high, low).compactMap { rawDate, code, high, low in
            guard let date = OpenMeteoDateParsers.daily.date(from: rawDate) else {
                return nil
            }
            return DailyWeatherSummary(
                date: date,
                high: high,
                low: low,
                conditionCode: code,
                symbolName: WeatherCodeMapping.symbolName(for: code)
            )
        }
    }
}

private enum OpenMeteoDateParsers {
    static let hourly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return formatter
    }()

    static let daily: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private func zip3<A, B, C>(_ a: [A], _ b: [B], _ c: [C]) -> [(A, B, C)] {
    let count = min(a.count, b.count, c.count)
    return (0..<count).map { (a[$0], b[$0], c[$0]) }
}

private func zip4<A, B, C, D>(_ a: [A], _ b: [B], _ c: [C], _ d: [D]) -> [(A, B, C, D)] {
    let count = min(a.count, b.count, c.count, d.count)
    return (0..<count).map { (a[$0], b[$0], c[$0], d[$0]) }
}
