import CoreLocation
import Foundation

enum LocationProviderError: LocalizedError {
    case servicesDisabled
    case denied
    case restricted
    case unableToDetermine(String)
    case requestAlreadyInProgress

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
        case .requestAlreadyInProgress:
            return "A location request is already in progress."
        }
    }
}

final class CoreLocationProvider: NSObject, LocationProviding, CLLocationManagerDelegate {
    private var manager: CLLocationManager?
    private var continuation: CheckedContinuation<WeatherLocation, Error>?

    func currentLocation() async throws -> WeatherLocation {
        try await requestLocationOnMainActor()
    }

    @MainActor
    private func requestLocationOnMainActor() async throws -> WeatherLocation {
        guard CLLocationManager.locationServicesEnabled() else {
            throw LocationProviderError.servicesDisabled
        }

        guard continuation == nil else {
            throw LocationProviderError.requestAlreadyInProgress
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

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
        let continuation = continuation
        self.continuation = nil
        manager?.delegate = nil
        manager = nil

        switch result {
        case .success(let location):
            continuation?.resume(returning: location)
        case .failure(let error):
            continuation?.resume(throwing: error)
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

        let location = WeatherLocation(
            latitude: latest.coordinate.latitude,
            longitude: latest.coordinate.longitude,
            displayName: "Current Location"
        )

        Task { @MainActor [weak self] in
            self?.complete(with: .success(location))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.complete(with: .failure(LocationProviderError.unableToDetermine(error.localizedDescription)))
        }
    }
}
