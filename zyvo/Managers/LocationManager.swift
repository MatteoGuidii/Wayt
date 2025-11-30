import Combine
import CoreLocation
import Foundation
import MapKit

final class LocationManager: NSObject, ObservableObject {
    private static let defaultSpan = MKCoordinateSpan(latitudeDelta: 0.01,
                                                      longitudeDelta: 0.01)

    @Published var region: MKCoordinateRegion
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var accuracyAuthorization: CLAccuracyAuthorization = .reducedAccuracy
    @Published var statusMessage: String?
    @Published var heading: CLLocationDirection = 0 // User's compass heading in degrees

    var userLocation: CLLocation? {
        manager.location
    }

    private let manager: CLLocationManager

    override init() {
        manager = CLLocationManager()
        // Start with a default region that will be immediately updated when location is available
        region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            span: Self.defaultSpan
        )

        super.init()

        configureManager()
    }

    func start() {
        // Only look at the manager's current authorization status.
        // No more CLLocationManager.locationServicesEnabled() on main thread.
        let status = manager.authorizationStatus

        switch status {
        case .notDetermined:
            // Trigger the system prompt once; future changes come via the delegate
            manager.requestWhenInUseAuthorization()

        default:
            // For all other states, let the central handler decide what to do
            handleAuthorizationStatus(status)
        }
    }

    func recenterOnUser() {
        if let coordinate = manager.location?.coordinate {
            updateRegion(center: coordinate)
        } else {
            manager.requestLocation()
        }
    }

    @discardableResult
    func adjustZoom(by factor: Double) -> MKCoordinateRegion {
        let center = region.center
        let span = MKCoordinateSpan(
            latitudeDelta: clamp(region.span.latitudeDelta * factor),
            longitudeDelta: clamp(region.span.longitudeDelta * factor)
        )
        let newRegion = MKCoordinateRegion(center: center, span: span)

        DispatchQueue.main.async {
            self.region = newRegion
        }

        return newRegion
    }

    func syncRegionWithCamera(_ region: MKCoordinateRegion) {
        DispatchQueue.main.async {
            self.region = region
        }
    }

    private func configureManager() {
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = 3
        manager.activityType = .otherNavigation
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true
        manager.headingFilter = 5 // Update heading when it changes by 5 degrees
        manager.delegate = self

        // Seed published properties from current manager state
        authorizationStatus = manager.authorizationStatus
        accuracyAuthorization = manager.accuracyAuthorization
    }

    private func handleAuthorizationStatus(_ status: CLAuthorizationStatus) {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
            manager.startUpdatingHeading() // Start tracking heading
            manager.requestLocation()

        case .notDetermined:
            // Do nothing here; `start()` is responsible for requesting auth
            break

        case .restricted, .denied:
            DispatchQueue.main.async {
                self.statusMessage = "Location access is required to show precise maps around you."
            }

        @unknown default:
            break
        }
    }

    private func updateRegion(with location: CLLocation) {
        updateRegion(center: location.coordinate)
    }

    private func updateRegion(center: CLLocationCoordinate2D) {
        let newRegion = MKCoordinateRegion(center: center, span: Self.defaultSpan)
        DispatchQueue.main.async {
            self.region = newRegion
            self.statusMessage = nil
        }
    }

    private func clamp(_ value: CLLocationDegrees) -> CLLocationDegrees {
        let minValue: CLLocationDegrees = 0.001
        let maxValue: CLLocationDegrees = 0.5
        return min(max(value, minValue), maxValue)
    }
}

extension LocationManager: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        let accuracy = manager.accuracyAuthorization

        DispatchQueue.main.async {
            self.authorizationStatus = status
            self.accuracyAuthorization = accuracy
        }

        // React to new status via a single handler, as Apple recommends
        handleAuthorizationStatus(status)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        updateRegion(with: location)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // Use true heading if available (requires location), otherwise use magnetic heading
        let headingValue = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading

        DispatchQueue.main.async {
            self.heading = headingValue
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.statusMessage = error.localizedDescription
        }
    }
}
