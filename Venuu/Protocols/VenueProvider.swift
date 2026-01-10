import Foundation
import MapKit
import CoreLocation

/// Protocol for venue data providers
/// Abstracts the data source to enable future integration with Yelp, Google Places, Foursquare, etc.
protocol VenueProvider: Sendable {

    /// Unique identifier for this provider
    var providerId: String { get }

    /// Display name for the provider
    var displayName: String { get }

    /// Priority for result ordering (higher = more trusted)
    /// Used when merging results from multiple providers
    var priority: Int { get }

    /// Search for venues in a region
    /// - Parameters:
    ///   - query: Search query string
    ///   - region: Geographic region to search
    /// - Returns: Array of venues found
    func search(query: String, region: MKCoordinateRegion) async throws -> [ProviderVenue]

    /// Search with multiple queries (for batch efficiency)
    /// Default implementation calls search for each query
    func searchBatch(queries: [String], region: MKCoordinateRegion) async throws -> [ProviderVenue]
}

// MARK: - Default Implementation

extension VenueProvider {
    func searchBatch(queries: [String], region: MKCoordinateRegion) async throws -> [ProviderVenue] {
        var allVenues: [ProviderVenue] = []
        var seenKeys = Set<String>()

        for query in queries {
            let venues = try await search(query: query, region: region)
            for venue in venues {
                let key = venue.deduplicationKey
                if !seenKeys.contains(key) {
                    seenKeys.insert(key)
                    allVenues.append(venue)
                }
            }
        }

        return allVenues
    }
}

// MARK: - Provider Venue

/// Standardized venue representation from any provider
/// Converted to internal Venue model after aggregation
struct ProviderVenue: Sendable, Identifiable {
    let id: String
    let providerId: String
    let name: String
    let coordinate: CLLocationCoordinate2D
    let category: String?
    let rating: Double?
    let priceLevel: Int?
    let photoURL: URL?

    /// Unique key for deduplication across providers
    var deduplicationKey: String {
        let lat = String(format: "%.5f", coordinate.latitude)
        let lng = String(format: "%.5f", coordinate.longitude)
        let normalizedName = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(normalizedName)_\(lat)_\(lng)"
    }
}

// MARK: - Provider Errors

enum VenueProviderError: LocalizedError {
    case rateLimited(retryAfter: TimeInterval?)
    case networkError(underlying: Error)
    case invalidResponse
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .rateLimited(let retryAfter):
            if let seconds = retryAfter {
                return "Rate limited. Retry after \(Int(seconds)) seconds."
            }
            return "Rate limited. Please try again later."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from provider."
        case .notConfigured:
            return "Provider not configured."
        }
    }
}
