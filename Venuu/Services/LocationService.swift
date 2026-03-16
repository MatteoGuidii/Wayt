import Combine
import Foundation
import CoreLocation
import MapKit

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
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = AppConstants.locationDistanceFilter

        // Start updating immediately if already authorized (avoids waiting for scenePhase)
        let status = manager.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }

    // MARK: - Public

    func requestPermission() {
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
        Task { @MainActor in
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
        print("[LocationService] Error: \(error.localizedDescription)")
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
