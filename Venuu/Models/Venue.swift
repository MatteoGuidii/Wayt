import Foundation
import MapKit
import SwiftUI

/// Value type backing each map annotation. `@unchecked Sendable` is required because
/// `MKMapItem`/`UIImage` are not marked as Sendable even though we access them carefully.
struct Venue: Identifiable, Hashable, @unchecked Sendable {
    let id = UUID()
    let mapItem: MKMapItem

    var name: String {
        mapItem.name ?? "Unknown Venue"
    }

    // Image is intentionally mutable and not included in equality/hash checks
    var image: UIImage?

    var coordinate: CLLocationCoordinate2D {
        mapItem.placemark.coordinate
    }

    /// Unique key for deduplication across searches
    /// Uses name + 5-decimal coordinate precision (~1.1m accuracy)
    var deduplicationKey: String {
        let lat = String(format: "%.5f", coordinate.latitude)
        let lng = String(format: "%.5f", coordinate.longitude)
        return "\(name)_\(lat)_\(lng)"
    }

    var title: String {
        name
    }

    var subtitle: String {
        mapItem.name ?? ""
    }

    var category: MKPointOfInterestCategory? {
        mapItem.pointOfInterestCategory
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(coordinate.latitude)
        hasher.combine(coordinate.longitude)
    }

    static func == (lhs: Venue, rhs: Venue) -> Bool {
        lhs.name == rhs.name &&
        lhs.coordinate.latitude == rhs.coordinate.latitude &&
        lhs.coordinate.longitude == rhs.coordinate.longitude
    }

    var type: VenueType {
        VenueClassifier.classify(mapItem: mapItem)
    }

    var systemImage: String {
        type.icon
    }

    var themeColor: Color {
        type.color
    }
}
