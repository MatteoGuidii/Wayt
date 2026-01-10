import Foundation
import CoreLocation

/// Calculates relevance scores for venues using multiple weighted signals
/// Primary signal is distance, with secondary signals for tie-breaking
struct VenueRelevanceScorer: Sendable {

    // MARK: - Scoring Weights

    struct Weights: Sendable {
        var distance: Double = 0.60    // Primary signal
        var category: Double = 0.20    // Category preference match
        var keyword: Double = 0.15     // Search term match
        var freshness: Double = 0.05   // Placeholder for future signals

        /// Validate weights sum to 1.0
        var isValid: Bool {
            abs((distance + category + keyword + freshness) - 1.0) < 0.001
        }
    }

    // MARK: - User Preferences

    struct UserPreferences: Sendable {
        var preferredCategories: Set<VenueType> = []
        var avoidChains: Bool = true

        static let `default` = UserPreferences()
    }

    // MARK: - Properties

    let weights: Weights
    let preferences: UserPreferences

    // MARK: - Initialization

    init(weights: Weights = Weights(), preferences: UserPreferences = .default) {
        self.weights = weights
        self.preferences = preferences
    }

    // MARK: - Public API

    /// Calculate composite relevance score for a venue
    /// - Parameters:
    ///   - venue: The venue to score
    ///   - userLocation: User's current location
    ///   - searchQuery: Optional search query for keyword matching
    ///   - maxDistance: Maximum search distance (for normalization)
    /// - Returns: Score between 0.0 and 1.0 (higher is more relevant)
    func score(
        venue: Venue,
        userLocation: CLLocation,
        searchQuery: String? = nil,
        maxDistance: CLLocationDistance
    ) -> Double {
        var totalScore = 0.0

        // 1. Distance score (60%) - closer is better
        let distanceScore = calculateDistanceScore(
            venue: venue,
            userLocation: userLocation,
            maxDistance: maxDistance
        )
        totalScore += distanceScore * weights.distance

        // 2. Category score (20%) - preference matching
        let categoryScore = calculateCategoryScore(venue: venue)
        totalScore += categoryScore * weights.category

        // 3. Keyword score (15%) - search term matching
        let keywordScore = calculateKeywordScore(venue: venue, query: searchQuery)
        totalScore += keywordScore * weights.keyword

        // 4. Freshness score (5%) - placeholder for future
        let freshnessScore = 0.5 // Neutral baseline
        totalScore += freshnessScore * weights.freshness

        return min(1.0, max(0.0, totalScore))
    }

    /// Score and sort venues by relevance
    /// - Parameters:
    ///   - venues: Venues to sort
    ///   - userLocation: User's current location
    ///   - searchQuery: Optional search query
    ///   - maxDistance: Maximum search distance
    /// - Returns: Venues sorted by relevance (highest first)
    func sortByRelevance(
        venues: [Venue],
        userLocation: CLLocation,
        searchQuery: String? = nil,
        maxDistance: CLLocationDistance
    ) -> [Venue] {
        let scored = venues.map { venue -> (venue: Venue, score: Double) in
            let score = self.score(
                venue: venue,
                userLocation: userLocation,
                searchQuery: searchQuery,
                maxDistance: maxDistance
            )
            return (venue, score)
        }

        return scored
            .sorted { $0.score > $1.score }
            .map { $0.venue }
    }

    /// Sort venues with distance as primary, relevance as secondary
    /// This is the hybrid approach: distance-first, then relevance for tie-breaking
    func sortByDistanceThenRelevance(
        venues: [Venue],
        userLocation: CLLocation,
        searchQuery: String? = nil,
        maxDistance: CLLocationDistance,
        distanceBucketSize: CLLocationDistance = 500 // 500m buckets
    ) -> [Venue] {
        let scored = venues.map { venue -> (venue: Venue, distance: CLLocationDistance, score: Double) in
            let venueLocation = CLLocation(
                latitude: venue.coordinate.latitude,
                longitude: venue.coordinate.longitude
            )
            let distance = venueLocation.distance(from: userLocation)
            let score = self.score(
                venue: venue,
                userLocation: userLocation,
                searchQuery: searchQuery,
                maxDistance: maxDistance
            )
            return (venue, distance, score)
        }

        return scored
            .sorted { item1, item2 in
                // Group into distance buckets
                let bucket1 = Int(item1.distance / distanceBucketSize)
                let bucket2 = Int(item2.distance / distanceBucketSize)

                if bucket1 != bucket2 {
                    // Different buckets: sort by distance
                    return bucket1 < bucket2
                } else {
                    // Same bucket: sort by relevance score
                    return item1.score > item2.score
                }
            }
            .map { $0.venue }
    }

    // MARK: - Score Components

    private func calculateDistanceScore(
        venue: Venue,
        userLocation: CLLocation,
        maxDistance: CLLocationDistance
    ) -> Double {
        let venueLocation = CLLocation(
            latitude: venue.coordinate.latitude,
            longitude: venue.coordinate.longitude
        )
        let distance = venueLocation.distance(from: userLocation)

        // Guard against division by zero
        guard maxDistance > 0 else { return 1.0 }

        // Exponential decay: venues at 0 distance = 1.0, at maxDistance ≈ 0.1
        // Using square root for gentler decay curve
        let normalized = min(1.0, distance / maxDistance)
        return max(0.0, 1.0 - pow(normalized, 0.5))
    }

    private func calculateCategoryScore(venue: Venue) -> Double {
        // No preferences set = neutral score
        if preferences.preferredCategories.isEmpty {
            return 0.5
        }

        // Check if venue type matches preferred categories
        if preferences.preferredCategories.contains(venue.type) {
            return 1.0
        }

        // Slight penalty for non-preferred, but not zero
        return 0.3
    }

    private func calculateKeywordScore(venue: Venue, query: String?) -> Double {
        // No query = discovery mode = neutral score
        guard let query = query, !query.isEmpty else {
            return 0.5
        }

        let queryLower = query.lowercased()
        let nameLower = venue.name.lowercased()

        // Exact name match
        if nameLower == queryLower {
            return 1.0
        }

        // Name contains query
        if nameLower.contains(queryLower) {
            return 0.9
        }

        // Query words appear in name
        let queryWords = queryLower.split(separator: " ").map(String.init)
        let matchingWords = queryWords.filter { nameLower.contains($0) }
        if !matchingWords.isEmpty {
            let ratio = Double(matchingWords.count) / Double(queryWords.count)
            return 0.5 + (ratio * 0.3) // 0.5 to 0.8
        }

        // Venue type matches query
        let typeString = venue.type.rawValue.lowercased()
        if typeString.contains(queryLower) || queryLower.contains(typeString) {
            return 0.6
        }

        // No match
        return 0.0
    }
}

// MARK: - Convenience Extension

extension VenueRelevanceScorer {
    /// Create a scorer with default weights optimized for discovery
    static let discovery = VenueRelevanceScorer(
        weights: Weights(distance: 0.60, category: 0.20, keyword: 0.15, freshness: 0.05),
        preferences: .default
    )

    /// Create a scorer with weights optimized for text search
    static let textSearch = VenueRelevanceScorer(
        weights: Weights(distance: 0.40, category: 0.15, keyword: 0.40, freshness: 0.05),
        preferences: .default
    )
}
