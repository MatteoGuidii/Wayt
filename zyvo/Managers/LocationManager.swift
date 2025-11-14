import Combine
import CoreLocation
import Foundation
import MapKit

final class LocationManager: NSObject, ObservableObject {
    private static let fallbackCoordinate = CLLocationCoordinate2D(latitude: 37.3346, longitude: -122.0090)
    private static let defaultSpan = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    static let fallbackRegion = MKCoordinateRegion(center: fallbackCoordinate, span: defaultSpan)

    @Published var region: MKCoordinateRegion
    @Published var authorizationStatus: CLAuthorizationStatus
    @Published var accuracyAuthorization: CLAccuracyAuthorization
    @Published var statusMessage: String?

    private let manager: CLLocationManager

    override init() {
        manager = CLLocationManager()
        region = Self.fallbackRegion
        authorizationStatus = manager.authorizationStatus
        accuracyAuthorization = manager.accuracyAuthorization

        super.init()

        configureManager()
    }

    func start() {
        guard CLLocationManager.locationServicesEnabled() else {
            DispatchQueue.main.async {
                self.statusMessage = "Location services are disabled. Enable them in Settings to view the live map."
            }
            return
        }

        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            // Authorized: request a one-time location update; ongoing updates are started in the delegate when appropriate.
            manager.requestLocation()
        case .notDetermined:
            // Trigger the system prompt; subsequent actions happen in the delegate callback.
            manager.requestWhenInUseAuthorization()
        case .restricted, .denied:
            DispatchQueue.main.async {
                self.statusMessage = "Location access is required to show precise maps around you."
            }
        @unknown default:
            break
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
        manager.delegate = self
    }

    private func handleAuthorizationStatus(_ status: CLAuthorizationStatus) {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
            manager.requestLocation()
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
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
        DispatchQueue.main.async {
            self.authorizationStatus = manager.authorizationStatus
            self.accuracyAuthorization = manager.accuracyAuthorization
        }
        handleAuthorizationStatus(manager.authorizationStatus)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        updateRegion(with: location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.statusMessage = error.localizedDescription
        }
    }
}
