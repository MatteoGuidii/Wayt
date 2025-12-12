import Foundation
import MapKit

struct VenueClassifier {

    public static func classify(mapItem: MKMapItem) -> VenueType {
        let category = mapItem.pointOfInterestCategory
        let name = mapItem.name?.lowercased() ?? ""
        
        // 1. Check specific categories first
        if category == .nightlife {
            if name.contains("club") || name.contains("disco") {
                return .club
            }
            if name.contains("pub") || name.contains("tavern") || name.contains("inn") {
                return .pub
            }
            if name.contains("lounge") {
                return .lounge
            }
            return .bar // Default for nightlife
        }
        
        if category == .brewery || category == .distillery || category == .winery {
            return .pub
        }
        
        // 2. Check name keywords if category is generic or missing
        if name.contains("nightclub") || name.contains("night club") {
            return .club
        }
        if name.contains("live music") || name.contains("jazz") || name.contains("concert") {
            return .liveMusic
        }
        if name.contains("pub") || name.contains("brewery") || name.contains("taproom") || name.contains("alehouse") || name.contains("gastropub") {
            return .pub
        }
        if name.contains("bar") || name.contains("speakeasy") || name.contains("cocktail") || name.contains("wine") || name.contains("tapas") {
            return .bar
        }
        if name.contains("lounge") {
            return .lounge
        }
        
        // 3. Fallback categories
        if category == .restaurant {
            // Some restaurants are actually bars/lounges at night
            if name.contains("bar") || name.contains("pub") || name.contains("lounge") || name.contains("taproom") || name.contains("gastropub") || name.contains("tapas") || name.contains("wine") || name.contains("alehouse") {
                return .bar
            }
            return .restaurant
        }
        
        if category == .theater || category == .musicVenue {
            return .liveMusic
        }
        
        return .other
    }
}
