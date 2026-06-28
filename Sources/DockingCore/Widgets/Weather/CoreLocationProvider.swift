import CoreLocation
import Foundation
import MapKit

enum LocationProviderError: LocalizedError {
    case servicesDisabled
    case denied
    case restricted
    case unableToDetermine(String)

    var errorDescription: String? {
        switch self {
        case .servicesDisabled:
            return "Location Services are off."
        case .denied:
            return "Location access was denied."
        case .restricted:
            return "Location access is restricted by system policy."
        case .unableToDetermine(let message):
            return "Location could not be determined. \(message)"
        }
    }
}

final class CoreLocationProvider: NSObject, LocationProviding, CLLocationManagerDelegate {
    private var manager: CLLocationManager?
    private var continuations: [CheckedContinuation<WeatherLocation, Error>] = []
    private var reverseGeocodingRequest: MKReverseGeocodingRequest?

    func currentLocation() async throws -> WeatherLocation {
        try await requestLocationOnMainActor()
    }

    @MainActor
    private func requestLocationOnMainActor() async throws -> WeatherLocation {
        guard CLLocationManager.locationServicesEnabled() else {
            throw LocationProviderError.servicesDisabled
        }

        return try await withCheckedThrowingContinuation { continuation in
            if manager != nil {
                // WeatherKit primary, Open-Meteo fallback, launch refresh, and
                // panel-open refresh can converge on current-location weather
                // at nearly the same time. Treating the second caller as an
                // error makes the widget fail even though the first location
                // request is valid. Coalescing callers behind one CoreLocation
                // request keeps permission prompts singular and avoids wasting
                // battery/network work.
                continuations.append(continuation)
                return
            }

            continuations = [continuation]

            let manager = CLLocationManager()
            manager.delegate = self
            // A weather widget does not need street-level precision. Asking for
            // coarse accuracy is enough for forecast data and avoids implying
            // that we need high-power continuous location tracking.
            manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
            manager.distanceFilter = 5_000
            self.manager = manager

            handleAuthorizationStatus(manager.authorizationStatus, manager: manager)
        }
    }

    @MainActor
    private func handleAuthorizationStatus(_ status: CLAuthorizationStatus, manager: CLLocationManager) {
        switch status {
        case .notDetermined:
            // We request permission only when the user enables current-location
            // weather and the widget refreshes. Prompting at app launch would be
            // surprising and would violate the "ask only when needed" boundary.
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied:
            complete(with: .failure(LocationProviderError.denied))
        case .restricted:
            complete(with: .failure(LocationProviderError.restricted))
        @unknown default:
            complete(with: .failure(LocationProviderError.unableToDetermine("Unknown authorization state.")))
        }
    }

    @MainActor
    private func complete(with result: Result<WeatherLocation, Error>) {
        let continuations = continuations
        self.continuations.removeAll()
        reverseGeocodingRequest?.cancel()
        reverseGeocodingRequest = nil
        manager?.delegate = nil
        manager = nil

        switch result {
        case .success(let location):
            continuations.forEach { $0.resume(returning: location) }
        case .failure(let error):
            continuations.forEach { $0.resume(throwing: error) }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self, weak manager] in
            guard let manager else {
                return
            }
            self?.handleAuthorizationStatus(manager.authorizationStatus, manager: manager)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else {
            Task { @MainActor [weak self] in
                self?.complete(with: .failure(LocationProviderError.unableToDetermine("No location was returned.")))
            }
            return
        }

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            let location = await self.weatherLocation(for: latest)
            self.complete(with: .success(location))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.complete(with: .failure(LocationProviderError.unableToDetermine(error.localizedDescription)))
        }
    }

    @MainActor
    private func weatherLocation(for location: CLLocation) async -> WeatherLocation {
        let fallback = WeatherLocation(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            displayName: "Current Location"
        )

        do {
            guard let request = MKReverseGeocodingRequest(location: location) else {
                return fallback
            }
            request.preferredLocale = .autoupdatingCurrent
            reverseGeocodingRequest = request
            defer {
                if reverseGeocodingRequest === request {
                    reverseGeocodingRequest = nil
                }
            }

            let mapItems = try await request.mapItems
            guard let displayName = mapItems.first.flatMap(Self.displayName)?.nilIfBlank else {
                return fallback
            }

            return WeatherLocation(
                latitude: fallback.latitude,
                longitude: fallback.longitude,
                displayName: displayName
            )
        } catch {
            // The forecast only needs coordinates, so a reverse-geocode outage
            // should not block weather updates. Falling back to a generic label
            // is less informative, but it preserves the primary behavior and
            // avoids turning an optional presentation lookup into a data-fetch
            // failure.
            return fallback
        }
    }

    private static func displayName(for mapItem: MKMapItem) -> String? {
        // Weather needs a place label, not a street address. MapKit's
        // city-level representation is the right granularity for a dock widget:
        // it tells the user which location is being used without exposing or
        // crowding the UI with precise address data. The broader fallbacks are
        // still useful when reverse geocoding returns a sparse map item.
        [
            mapItem.addressRepresentations?.cityName,
            mapItem.addressRepresentations?.cityWithContext(.short),
            mapItem.address?.shortAddress,
            mapItem.name
        ].compactMap { $0?.nilIfBlank }.first
    }
}
