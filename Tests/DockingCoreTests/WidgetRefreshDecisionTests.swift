import Foundation
import XCTest
@testable import DockingCore

final class WidgetRefreshDecisionTests: XCTestCase {
    private let fetchedAt = Date(timeIntervalSince1970: 1_800_000_000)
    private let tokyo = WeatherRequestKey(usesCurrentLocation: false, manualLocation: "Tokyo", unit: .celsius)

    private func snapshot(requestKey: WeatherRequestKey?) -> WeatherSnapshot {
        WeatherSnapshot(
            locationName: "Tokyo",
            fetchedAt: fetchedAt,
            unit: .celsius,
            current: CurrentWeatherSummary(temperature: 20, feelsLike: nil, conditionCode: 0, conditionLabel: "Clear", symbolName: "sun.max"),
            hourly: [],
            daily: [],
            humidity: nil,
            airQualityLabel: nil,
            timeZoneIdentifier: nil,
            dataSource: .openMeteo,
            requestKey: requestKey
        )
    }

    private func decision(_ snapshot: WeatherSnapshot?, key: WeatherRequestKey? = nil,
                          interval: Int = 30, minutesLater: Double) -> WidgetRefreshDecision {
        WidgetRefreshDecision.weather(
            snapshot: snapshot,
            currentKey: key ?? tokyo,
            intervalMinutes: interval,
            now: fetchedAt.addingTimeInterval(minutesLater * 60)
        )
    }

    func testMissingCacheRefetches() {
        XCTAssertEqual(decision(nil, minutesLater: 0), .refetch)
    }

    func testDifferentRequestKeyRefetchesEvenWhenFresh() {
        let osaka = WeatherRequestKey(usesCurrentLocation: false, manualLocation: "Osaka", unit: .celsius)
        XCTAssertEqual(decision(snapshot(requestKey: tokyo), key: osaka, minutesLater: 1), .refetch)

        let fahrenheit = WeatherRequestKey(usesCurrentLocation: false, manualLocation: "Tokyo", unit: .fahrenheit)
        XCTAssertEqual(decision(snapshot(requestKey: tokyo), key: fahrenheit, minutesLater: 1), .refetch)
    }

    func testMatchingFreshSnapshotUsesCache() {
        XCTAssertEqual(decision(snapshot(requestKey: tokyo), minutesLater: 29), .useCache)
    }

    func testMatchingStaleSnapshotRefetches() {
        XCTAssertEqual(decision(snapshot(requestKey: tokyo), minutesLater: 30), .refetch)
    }

    func testLegacySnapshotWithoutRequestKeyRefetches() {
        XCTAssertEqual(decision(snapshot(requestKey: nil), minutesLater: 1), .refetch)
    }

    func testLegacyCacheFileDecodesWithoutRequestKey() throws {
        let encoder = JSONEncoder()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(snapshot(requestKey: tokyo))) as? [String: Any])
        object.removeValue(forKey: "requestKey")
        let legacy = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(WeatherSnapshot.self, from: legacy)
        XCTAssertNil(decoded.requestKey)
    }

    func testRefreshIntervalOnlyChangesFreshness() {
        var settings = DockingSettings.default
        settings.weatherManualLocation = "Tokyo"
        let before = settings.weatherRequestKey
        settings.weatherRefreshIntervalMinutes = 60
        XCTAssertEqual(settings.weatherRequestKey, before)

        let cached = snapshot(requestKey: tokyo)
        XCTAssertEqual(decision(cached, interval: 30, minutesLater: 45), .refetch)
        XCTAssertEqual(decision(cached, interval: 60, minutesLater: 45), .useCache)
    }

    func testManualLocationWhitespaceDoesNotChangeRequestKey() {
        var settings = DockingSettings.default
        settings.weatherManualLocation = "Tokyo"
        let trimmed = settings.weatherRequestKey
        settings.weatherManualLocation = "  Tokyo "
        XCTAssertEqual(settings.weatherRequestKey, trimmed)
    }
}
