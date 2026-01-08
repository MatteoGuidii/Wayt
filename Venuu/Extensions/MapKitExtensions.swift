import Foundation
import MapKit
import CoreLocation

extension MKCoordinateSpan {
    /// Calculates the radius in meters from the coordinate span
    /// - Returns: Radius in meters, clamped between configured minimum and maximum values
    func toRadius() -> CLLocationDistance {
        // 1 degree of latitude is approximately 111km
        // We take half the span as radius
        let meters = latitudeDelta * 111_000 / 2
        return max(AppConfiguration.Map.minimumRadius, min(meters, AppConfiguration.Map.maximumRadius))
    }
}

extension CLLocationCoordinate2D {
    /// Calculates the distance in meters from this coordinate to another
    /// - Parameter other: The target coordinate
    /// - Returns: Distance in meters
    func distance(to other: CLLocationCoordinate2D) -> CLLocationDistance {
        let from = CLLocation(latitude: latitude, longitude: longitude)
        let to = CLLocation(latitude: other.latitude, longitude: other.longitude)
        return from.distance(from: to)
    }
}
