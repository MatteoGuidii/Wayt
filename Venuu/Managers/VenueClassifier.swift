import Foundation
import MapKit

/// Result of venue classification including type and confidence score
struct VenueClassification {
    let type: VenueType
    let confidenceScore: Int // 0-100

    /// Whether this venue meets the minimum threshold for nightlife relevance
    var isNightlifeRelevant: Bool {
        confidenceScore >= AppConfiguration.VenueScoring.minimumNightlifeScore
    }
}

struct VenueClassifier {

    // MARK: - Public API

    /// Classify a venue with confidence scoring
    /// - Parameters:
    ///   - mapItem: The MapKit item to classify
    ///   - nearbyNightlifeCount: Optional count of nearby nightlife venues for context
    /// - Returns: Classification with type and confidence score
    public static func classifyWithConfidence(
        mapItem: MKMapItem,
        nearbyNightlifeCount: Int = 0
    ) -> VenueClassification {
        let type = determineType(mapItem: mapItem)
        let score = VenueRelevanceScorer.calculateScore(
            for: mapItem,
            nearbyNightlifeCount: nearbyNightlifeCount
        )

        return VenueClassification(type: type, confidenceScore: score)
    }

    /// Legacy classification method (backward compatibility)
    /// - Parameter mapItem: The MapKit item to classify
    /// - Returns: Venue type without scoring
    public static func classify(mapItem: MKMapItem) -> VenueType {
        return determineType(mapItem: mapItem)
    }

    // MARK: - Type Determination

    private static func determineType(mapItem: MKMapItem) -> VenueType {
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
