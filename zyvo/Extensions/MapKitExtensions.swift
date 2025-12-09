import Foundation
import MapKit

extension MKCoordinateSpan {
    /// Calculates the radius in meters from the coordinate span
    /// - Returns: Radius in meters, clamped between 500m and 50km
    func toRadius() -> CLLocationDistance {
        // 1 degree of latitude is approximately 111km
        // We take half the span as radius
        let meters = latitudeDelta * 111_000 / 2
        return max(500, min(meters, 50_000)) // Clamp between 500m and 50km
    }
}
