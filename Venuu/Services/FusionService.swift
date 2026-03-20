import CoreLocation
import Foundation

/// Fetches fused busyness estimates from the v1 Signal Fusion Engine endpoints.
/// Falls back gracefully — callers should catch errors and use ReportService instead.
@MainActor
final class FusionService {

    static let shared = FusionService()

    // MARK: - Cache

    private var nearbyCache: [String: FusedEstimateResponse] = [:]
    private var cacheTimestamp: Date = .distantPast
    private var cachedLat: Double = 0
    private var cachedLng: Double = 0

    private func isCacheValid(lat: Double, lng: Double) -> Bool {
        guard Date().timeIntervalSince(cacheTimestamp) < AppConstants.reportCacheTTL else {
            return false
        }
        // Invalidate if the user moved significantly (> ~500m)
        let latDelta = abs(lat - cachedLat)
        let lngDelta = abs(lng - cachedLng)
        return latDelta < 0.005 && lngDelta < 0.005
    }

    // MARK: - Nearby Fused Estimates

    /// Fetch fused busyness estimates for venues near the given coordinates.
    /// Sends venue metadata in batches of 20 (URL length limit) and merges results.
    func fetchNearbyEstimates(
        lat: Double,
        lng: Double,
        radius: Double = 2_000,
        venues: [VenueInfo] = []
    ) async throws -> [String: FusedEstimateResponse] {
        if isCacheValid(lat: lat, lng: lng) { return nearbyCache }

        if venues.isEmpty { return [:] }

        let batchSize = 20
        let batches = stride(from: 0, to: venues.count, by: batchSize).map {
            Array(venues[($0)..<min($0 + batchSize, venues.count)])
        }

        var indexed: [String: FusedEstimateResponse] = [:]

        // Fetch all batches concurrently
        try await withThrowingTaskGroup(of: [FusedEstimateResponse].self) { group in
            for batch in batches {
                group.addTask {
                    var queryItems = [
                        URLQueryItem(name: "lat", value: String(lat)),
                        URLQueryItem(name: "lng", value: String(lng)),
                        URLQueryItem(name: "radius", value: String(Int(radius))),
                    ]

                    if !batch.isEmpty {
                        let encoder = JSONEncoder()
                        if let data = try? encoder.encode(batch),
                           let json = String(data: data, encoding: .utf8) {
                            queryItems.append(URLQueryItem(name: "venues", value: json))
                        }
                    }

                    let response: NearbyVenuesFusedResponse = try await APIClient.shared.get(
                        path: "/v1/venues/nearby",
                        queryItems: queryItems
                    )
                    return response.venues
                }
            }

            for try await venues in group {
                for estimate in venues {
                    if let venueId = estimate.venueId {
                        indexed[venueId] = estimate
                    }
                }
            }
        }

        // Only cache non-empty results — avoids blocking retries for 60s on transient failures
        if !indexed.isEmpty {
            nearbyCache = indexed
            cacheTimestamp = Date()
            cachedLat = lat
            cachedLng = lng
        }
        return indexed
    }

    // MARK: - Single Venue Busyness

    /// Fetch detailed fused busyness for a single venue.
    func fetchVenueBusyness(
        venueId: String,
        venueName: String,
        lat: Double,
        lng: Double
    ) async throws -> DetailedFusedResponse {
        let encoded = venueId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? venueId
        let queryItems = [
            URLQueryItem(name: "venueName", value: venueName),
            URLQueryItem(name: "lat", value: String(lat)),
            URLQueryItem(name: "lng", value: String(lng)),
        ]
        return try await APIClient.shared.get(
            path: "/v1/venues/\(encoded)/busyness",
            queryItems: queryItems
        )
    }

    // MARK: - Cache Lookup

    /// Return a cached fused estimate for a venue if available (avoids a redundant API call).
    func cachedEstimate(for venueId: String) -> FusedEstimateResponse? {
        guard Date().timeIntervalSince(cacheTimestamp) < AppConstants.reportCacheTTL else {
            return nil
        }
        return nearbyCache[venueId]
    }

    // MARK: - Cache Control

    func invalidateCache() {
        nearbyCache = [:]
        cacheTimestamp = .distantPast
    }
}

// MARK: - Request / Response Types

/// Minimal venue info sent to the backend for on-demand computation.
struct VenueInfo: Codable, Sendable {
    let venueId: String
    let venueName: String
    let lat: Double
    let lng: Double

    init(venue: Venue) {
        self.venueId = venue.id
        self.venueName = venue.name
        self.lat = venue.coordinate.latitude
        self.lng = venue.coordinate.longitude
    }
}

/// Response from GET /v1/venues/nearby.
struct NearbyVenuesFusedResponse: Codable, Sendable {
    let venues: [FusedEstimateResponse]
}

/// Detailed response from GET /v1/venues/{id}/busyness.
struct DetailedFusedResponse: Codable, Sendable {
    let venueId: String
    let busynessScore: Double
    let confidence: String
    let reportCount: Int
    let waitMinutes: Int?
    let sourceCount: Int
    let sources: [String]
    let conflictDetected: Bool
    let computedAt: String
    let signals: [SignalDetail]?

    /// Convert to a FusedEstimateResponse for the BusynessEngine.
    func toFusedEstimate() -> FusedEstimateResponse {
        FusedEstimateResponse(
            busynessScore: busynessScore,
            confidence: confidence,
            reportCount: reportCount,
            waitMinutes: waitMinutes,
            venueId: venueId,
            sourceCount: sourceCount,
            sources: sources,
            conflictDetected: conflictDetected,
            computedAt: computedAt
        )
    }
}

/// Individual signal breakdown in the detailed response.
struct SignalDetail: Codable, Sendable {
    let source: String
    let score: Double
    let confidence: Double
    let ageMinutes: Int
}
