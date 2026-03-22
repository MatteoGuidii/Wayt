import Combine
import CoreLocation
import Foundation
import MapKit
import os

@MainActor
final class LocationService: NSObject, ObservableObject {

    // MARK: - Published State

    @Published var userLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var region: MKCoordinateRegion = .defaultRegion

    // MARK: - Private

    private let manager = CLLocationManager()

    // MARK: - Init

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = AppConstants.locationDistanceFilter
        manager.activityType = .fitness          // walking / general movement

        // Start updating immediately if already authorized (avoids waiting for scenePhase)
        let status = manager.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }

    // MARK: - Public

    func requestPermission() {
        Log.location.info("Requesting location permission")
        manager.requestWhenInUseAuthorization()
    }

    func startUpdating() {
        manager.startUpdatingLocation()
    }

    func stopUpdating() {
        manager.stopUpdatingLocation()
    }

}

// MARK: - CLLocationManagerDelegate

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last else { return }

        // Reject stale or wildly inaccurate readings
        let age = -location.timestamp.timeIntervalSinceNow
        guard age < 15,
              location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= 200 else {
            Task { @MainActor in
                Log.location.debug("Rejected location: age=\(String(format: "%.1f", age))s accuracy=\(String(format: "%.0f", location.horizontalAccuracy))m")
            }
            return
        }

        Task { @MainActor in
            // Only accept if more accurate than current, or current is stale (>30s)
            if let current = self.userLocation,
               -current.timestamp.timeIntervalSinceNow < 30,
               location.horizontalAccuracy > current.horizontalAccuracy {
                return
            }
            Log.location.debug("Location updated: (\(location.coordinate.latitude), \(location.coordinate.longitude)) accuracy=\(String(format: "%.0f", location.horizontalAccuracy))m")
            self.userLocation = location
            self.region = MKCoordinateRegion(
                center: location.coordinate,
                latitudinalMeters: AppConstants.defaultSearchRadius * 2,
                longitudinalMeters: AppConstants.defaultSearchRadius * 2
            )
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            Log.location.info("Authorization changed to \(String(describing: status))")
            self.authorizationStatus = status
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                self.startUpdating()
            }
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        Task { @MainActor in
            Log.location.error("Location update failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Default Region

extension MKCoordinateRegion {
    static let defaultRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194), // SF
        latitudinalMeters: 4_000,
        longitudinalMeters: 4_000
    )
}
