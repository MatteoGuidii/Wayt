import Foundation
import MapKit

/// Centralized configuration for venue discovery queries
/// Defines query terms, POI categories, and execution parameters
enum VenueQueryConfiguration {

    // MARK: - Query Terms

    /// Primary queries - always executed first for fastest results
    /// These cover the most common venue types
    static let primaryQueries = [
        "restaurant",
        "bar",
        "cafe"
    ]

    /// Secondary queries - executed if primary yields < secondaryThreshold results
    /// Targets nightlife and specialty venues often missed by primary queries
    static let secondaryQueries = [
        "nightlife",
        "lounge",
        "pub",
        "wine bar",
        "cocktail bar",
        "gastropub",
        "speakeasy",
        "rooftop bar"
    ]

    /// Cuisine-specific queries - used for comprehensive coverage in dense areas
    /// Helps find restaurants that don't appear in generic "restaurant" searches
    static let cuisineQueries = [
        "italian restaurant",
        "japanese restaurant",
        "mexican restaurant",
        "thai restaurant",
        "indian restaurant",
        "chinese restaurant",
        "french restaurant",
        "mediterranean restaurant",
        "korean restaurant",
        "vietnamese restaurant",
        "sushi",
        "pizza",
        "tapas",
        "ramen"
    ]

    /// Activity-based queries - for specialized searches
    static let activityQueries = [
        "brunch",
        "happy hour",
        "late night food",
        "breakfast"
    ]

    // MARK: - POI Categories

    /// All venue-related MapKit categories to include in searches
    /// Note: MapKit does not have a dedicated .bar category; bars are found via .nightlife or queries
    /// Excludes .bakery and .foodMarket to reduce clutter from unwanted venues (bakeries, supermarkets, stores)
    static let venueCategories: [MKPointOfInterestCategory] = [
        .restaurant,
        .cafe,
        .brewery,
        .distillery,
        .winery,
        .nightlife
    ]

    // MARK: - Execution Parameters

    /// Maximum concurrent MKLocalSearch requests
    /// Apple rate limits aggressive querying; 4 is a safe balance
    static let maxConcurrentQueries = 4

    /// Minimum venues from primary queries before triggering secondary
    static let secondaryThreshold = 15

    /// Minimum venues before triggering cuisine-specific queries
    static let cuisineThreshold = 30

    /// Delay between query batches to avoid rate limiting (nanoseconds)
    static let batchDelayNanoseconds: UInt64 = 100_000_000 // 100ms

    // MARK: - Query Selection

    /// Get all discovery queries for a region based on current result count
    /// - Parameters:
    ///   - currentCount: Number of venues already found
    ///   - searchText: User's search text (empty for discovery mode)
    /// - Returns: Array of queries to execute
    static func getQueries(currentCount: Int, searchText: String) -> [String] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        // User typed something specific - use that query only
        if !trimmed.isEmpty {
            return [trimmed]
        }

        // Discovery mode - tier queries based on current coverage
        if currentCount == 0 {
            return primaryQueries
        } else if currentCount < secondaryThreshold {
            return secondaryQueries
        } else if currentCount < cuisineThreshold {
            return cuisineQueries
        }

        // Already have good coverage
        return []
    }

    /// Get initial discovery queries
    static func getInitialQueries() -> [String] {
        return primaryQueries
    }

    /// Get secondary queries for expanded search
    static func getSecondaryQueries() -> [String] {
        return secondaryQueries
    }

    /// Get cuisine queries for comprehensive coverage
    static func getCuisineQueries() -> [String] {
        return cuisineQueries
    }
}
