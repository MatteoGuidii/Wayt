import Foundation
import CoreLocation

/// Lightweight venue data stored in the backend when a user bookmarks a venue.
/// Does not require an MKMapItem — can be rendered in Profile without MapKit.
struct SavedVenue: Codable, Identifiable, Sendable {
    let venueId: String
    let venueName: String
    let categoryRaw: String
    let lat: Double
    let lng: Double
    let address: String?
    let savedAt: String

    var id: String { venueId }

    var category: VenueCategory {
        VenueCategory(rawValue: categoryRaw) ?? .food
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}
