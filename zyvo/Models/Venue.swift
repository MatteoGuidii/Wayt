import Foundation
import MapKit

struct Venue: Identifiable, Hashable {
    let id = UUID()
    let mapItem: MKMapItem
    
    var name: String {
        mapItem.name ?? "Unknown Venue"
    }
    
    var image: UIImage?
    
    var coordinate: CLLocationCoordinate2D {
        if #available(iOS 26.0, *) {
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
        // In iOS 26, we might use mapItem.address if available, but for now let's keep it simple
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
    
    var systemImage: String {
        guard let category = category else { return "mappin" }
        switch category {
        case .restaurant: return "fork.knife"
        case .cafe: return "cup.and.saucer.fill"
        case .nightlife: return "music.note"
        case .winery, .brewery, .distillery: return "wineglass.fill"
        default: return "mappin"
        }
    }
}
