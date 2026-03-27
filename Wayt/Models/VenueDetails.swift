import Foundation

// MARK: - Venue Details Summary (from /v1/venues/nearby list response)

/// Lightweight venue details included in nearby venue list responses.
struct VenueDetailsSummary: Codable, Sendable, Hashable {
    let primaryType: String?
    let primaryTypeDisplayName: String?
    let rating: Double?
    let userRatingCount: Int?
    let priceLevel: String?
}

// MARK: - Google Review

/// A single Google review cached from Place Details.
struct GoogleReview: Codable, Sendable, Hashable, Identifiable {
    var id: String { "\(authorName)_\(publishTime)" }

    let authorName: String
    let rating: Int
    let text: String
    let relativePublishTime: String
    let publishTime: String
}

// MARK: - Venue Details Full (from /v1/venues/{id}/busyness single-venue response)

/// Full venue details including reviews and editorial summary.
struct VenueDetailsFull: Codable, Sendable, Hashable {
    let primaryType: String?
    let primaryTypeDisplayName: String?
    let rating: Double?
    let userRatingCount: Int?
    let priceLevel: String?
    let types: [String]
    let reviews: [GoogleReview]
    let editorialSummary: String?
    let googleMapsUrl: String?

    /// Convert to lightweight summary for list contexts.
    func toSummary() -> VenueDetailsSummary {
        VenueDetailsSummary(
            primaryType: primaryType,
            primaryTypeDisplayName: primaryTypeDisplayName,
            rating: rating,
            userRatingCount: userRatingCount,
            priceLevel: priceLevel
        )
    }
}

// MARK: - Price Level Formatting

enum PriceLevel {
    /// Convert backend price level string to user-facing dollar signs.
    static func format(_ raw: String?) -> String? {
        switch raw {
        case "PRICE_LEVEL_FREE":           return "Free"
        case "PRICE_LEVEL_INEXPENSIVE":    return "$"
        case "PRICE_LEVEL_MODERATE":       return "$$"
        case "PRICE_LEVEL_EXPENSIVE":      return "$$$"
        case "PRICE_LEVEL_VERY_EXPENSIVE": return "$$$$"
        default:                           return nil
        }
    }
}
