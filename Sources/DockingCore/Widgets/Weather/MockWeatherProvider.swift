import Foundation

#if DEBUG
// Mock weather is deliberately debug-only. A production dock showing plausible
// but fake weather is worse than a visible error, because users would have no
// reason to distrust the data. Previews and validation use separate local test
// providers, so this type should never become part of the release provider
// graph just to make entitlement or network failures look nicer.
final class MockWeatherProvider: WeatherProvider {
    func fetchWeather(configuration: WeatherRequestConfiguration) async throws -> WeatherSnapshot {
        WeatherSnapshot(
            locationName: configuration.manualLocation?.nilIfBlank ?? "Preview City",
            fetchedAt: Date(),
            unit: configuration.unit,
            current: CurrentWeatherSummary(
                temperature: 23,
                feelsLike: 27,
                conditionCode: 3,
                conditionLabel: "Cloudy",
                symbolName: "cloud.sun"
            ),
            hourly: (1...6).compactMap { offset in
                Calendar.current.date(byAdding: .hour, value: offset * 2, to: Date()).map {
                    HourlyWeatherSummary(date: $0, temperature: Double(22 + offset % 3), conditionCode: 3, symbolName: "cloud.sun")
                }
            },
            daily: (0...5).compactMap { offset in
                Calendar.current.date(byAdding: .day, value: offset, to: Date()).map {
                    DailyWeatherSummary(date: $0, high: Double(24 + offset), low: Double(18 + offset % 2), conditionCode: 3, symbolName: "cloud.sun")
                }
            },
            humidity: 0.72,
            airQualityLabel: nil
        )
    }
}
#endif
