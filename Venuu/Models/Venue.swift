import Foundation
import MapKit
import SwiftUI

struct Venue: Identifiable, Hashable {
    let id = UUID()
    let mapItem: MKMapItem
    
    var name: String {
        mapItem.name ?? "Unknown Venue"
    }

    // Image is intentionally mutable and not included in equality/hash checks
    // This allows lazy loading of images without affecting venue identity
    var image: UIImage?
    
    var coordinate: CLLocationCoordinate2D {
        if #available(iOS 17.0, *) {
            return mapItem.location.coordinate
        } else {
            return mapItem.placemark.coordinate
        }
    }
    
    var title: String {
        name
    }
    
    var subtitle: String {
        // Fallback to name or empty if address is not easily available without placemark
        // Future iOS versions may provide simplified address APIs on MKMapItem
        mapItem.name ?? ""
    }
    
    // Helper to check category if needed, though we filter by search query
    var category: MKPointOfInterestCategory? {
        mapItem.pointOfInterestCategory
    }
    
    func hash(into hasher: inout Hasher) {
        // Use coordinate and name for uniqueness
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
