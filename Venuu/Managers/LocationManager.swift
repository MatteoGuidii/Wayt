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
    @Published var currentCity: String = "Locating..."

    var userLocation: CLLocation? {
        manager.location
    }

    private let manager: CLLocationManager
    private var currentSearch: MKLocalSearch?
    private var lastCityLookupLocation: CLLocation?
    private var lastCityLookupDate: Date?
    private var lastCityLookupFailureDate: Date?
    private var headingUpdatesEnabled = false
    private var highAccuracyTrackingEnabled = false

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

    @MainActor
    @discardableResult
    func adjustZoom(by factor: Double) -> MKCoordinateRegion {
        let center = region.center
        let span = MKCoordinateSpan(
            latitudeDelta: clamp(region.span.latitudeDelta * factor),
            longitudeDelta: clamp(region.span.longitudeDelta * factor)
        )
        let newRegion = MKCoordinateRegion(center: center, span: span)
        self.region = newRegion
        return newRegion
    }

    @MainActor
    func syncRegionWithCamera(_ region: MKCoordinateRegion) {
        self.region = region
    }

    private func configureManager() {
        manager.desiredAccuracy = AppConfiguration.Location.desiredAccuracy
        manager.distanceFilter = AppConfiguration.Location.distanceFilter
        manager.activityType = .otherNavigation
        manager.pausesLocationUpdatesAutomatically = true
        manager.showsBackgroundLocationIndicator = false
        manager.headingFilter = AppConfiguration.Location.headingFilterDegrees
        manager.delegate = self

        // Seed published properties from current manager state
        authorizationStatus = manager.authorizationStatus
        accuracyAuthorization = manager.accuracyAuthorization
    }

    private func handleAuthorizationStatus(_ status: CLAuthorizationStatus) {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
            if headingUpdatesEnabled {
                manager.startUpdatingHeading()
            } else {
                manager.stopUpdatingHeading()
            }
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
        handleCityLookup(for: location)
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

// MARK: - Heading Controls

extension LocationManager {
    func setHeadingUpdatesEnabled(_ enabled: Bool) {
        guard enabled != headingUpdatesEnabled else { return }
        headingUpdatesEnabled = enabled

        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            if enabled {
                manager.startUpdatingHeading()
            } else {
                manager.stopUpdatingHeading()
            }
        default:
            if !enabled {
                manager.stopUpdatingHeading()
            }
        }
    }

    func setHighAccuracyTrackingEnabled(_ enabled: Bool) {
        guard enabled != highAccuracyTrackingEnabled else { return }
        highAccuracyTrackingEnabled = enabled

        let accuracy = enabled ? kCLLocationAccuracyBest : AppConfiguration.Location.desiredAccuracy
        let filter = enabled ? AppConfiguration.Location.highAccuracyDistanceFilter : AppConfiguration.Location.distanceFilter

        manager.desiredAccuracy = accuracy
        manager.distanceFilter = filter
        manager.pausesLocationUpdatesAutomatically = !enabled

        if enabled {
            manager.startUpdatingLocation()
        }
    }

    private func handleCityLookup(for location: CLLocation) {
        guard shouldPerformCityLookup(for: location) else { return }

        currentSearch?.cancel()
        let lookupLocation = location

        let searchRequest = MKLocalSearch.Request()
        searchRequest.region = MKCoordinateRegion(
            center: location.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
        searchRequest.naturalLanguageQuery = "city"
        searchRequest.resultTypes = [.address]

        let search = MKLocalSearch(request: searchRequest)
        currentSearch = search

        search.start { [weak self] response, error in
            guard let self = self else { return }

            if self.currentSearch === search {
                self.currentSearch = nil
            }

            guard error == nil, let mapItem = response?.mapItems.first else {
                DispatchQueue.main.async {
                    if self.currentCity == "Locating..." {
                        self.currentCity = "Unknown Location"
                    }
                    self.lastCityLookupFailureDate = Date()
                }
                return
            }

            DispatchQueue.main.async {
                self.lastCityLookupFailureDate = nil
                self.lastCityLookupLocation = lookupLocation
                self.lastCityLookupDate = Date()

                // Use placemark to get city information (iOS 18 compatible)
                let placemark = mapItem.placemark
                if let locality = placemark.locality {
                    // If we have administrative area (state), include it for context
                    if let administrativeArea = placemark.administrativeArea {
                        self.currentCity = "\(locality), \(administrativeArea)"
                    } else {
                        self.currentCity = locality
                    }
                } else {
                    self.currentCity = mapItem.name ?? "Unknown Location"
                }
            }
        }
    }

    private func shouldPerformCityLookup(for location: CLLocation) -> Bool {
        if let lastFailureDate = lastCityLookupFailureDate {
            let attemptInterval = Date().timeIntervalSince(lastFailureDate)
            if attemptInterval < AppConfiguration.Location.cityRefreshRetryInterval {
                return false
            }
        }

        guard let lastLocation = lastCityLookupLocation,
              let lastDate = lastCityLookupDate else {
            return true
        }

        let distance = location.distance(from: lastLocation)
        let timeInterval = Date().timeIntervalSince(lastDate)

        return distance >= AppConfiguration.Location.cityRefreshDistance ||
               timeInterval >= AppConfiguration.Location.cityRefreshInterval
    }
}
