import MapKit
import SwiftUI

/// Broad venue category for display and filtering.
/// Internally, venues store the raw `MKPointOfInterestCategory` from MapKit
/// for accurate classification; this enum provides the user-facing groups.
enum VenueCategory: String, CaseIterable, Codable, Hashable, Sendable {
    case food
    case drinks
    case nightlife
    case coffee

    // MARK: - Display

    var displayName: String {
        switch self {
        case .food:      return "Food"
        case .drinks:    return "Drinks"
        case .nightlife: return "Nightlife"
        case .coffee:    return "Coffee & Tea"
        }
    }

    var icon: String {
        switch self {
        case .food:      return "fork.knife"
        case .drinks:    return "wineglass.fill"
        case .nightlife: return "figure.dance"
        case .coffee:    return "cup.and.saucer.fill"
        }
    }

    var color: Color {
        switch self {
        case .food:      return .orange
        case .drinks:    return .purple
        case .nightlife: return .red
        case .coffee:    return .brown
        }
    }

    // MARK: - MapKit Category Mapping

    /// Map a MapKit POI category to a broad VenueCategory.
    static func from(poiCategory: MKPointOfInterestCategory?) -> VenueCategory {
        guard let poi = poiCategory else { return .food }
        switch poi {
        case .nightlife:  return .nightlife
        case .cafe:       return .coffee
        case .bakery:     return .coffee
        case .brewery:    return .drinks
        case .winery:     return .drinks
        case .restaurant: return .food
        default:          return .food
        }
    }

    /// Fallback: classify from venue name when MapKit category is missing or too generic.
    static func from(name: String) -> VenueCategory {
        let lower = name.lowercased()

        // Nightlife
        if lower.contains("club") || lower.contains("disco") || lower.contains("lounge")
            || lower.contains("karaoke") || lower.contains("hookah") {
            return .nightlife
        }

        // Drinks
        if lower.contains("bar") || lower.contains("pub") || lower.contains("brew")
            || lower.contains("cocktail") || lower.contains("tapas")
            || lower.contains("wine bar") || lower.contains("beer garden") {
            return .drinks
        }

        // Coffee & Tea
        if lower.contains("cafe") || lower.contains("café") || lower.contains("coffee")
            || lower.contains("bakery") || lower.contains("tea")
            || lower.contains("dessert") || lower.contains("juice")
            || lower.contains("ice cream") || lower.contains("pastry") {
            return .coffee
        }

        return .food
    }
}
