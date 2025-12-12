import Foundation
import MapKit

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
