import CoreLocation
import Foundation
import os

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

    // MARK: - Area Pre-fetch

    /// Pre-fetch cached fused estimates for an area (no venue list needed).
    /// Populates the local cache so that subsequent `cachedEstimate(for:)` calls hit instantly.
    /// Safe to call on every region change — skips if cache is already valid.
    func prefetchArea(lat: Double, lng: Double, radius: Double = 2_000) async {
        guard !isCacheValid(lat: lat, lng: lng) else {
            Log.fusion.debug("Prefetch skipped — cache valid (\(self.nearbyCache.count) venues)")
            return
        }
        do {
            let _ = try await fetchNearbyEstimates(lat: lat, lng: lng, radius: radius)
            Log.fusion.info("Area prefetch complete: \(self.nearbyCache.count) cached estimates")
        } catch {
            Log.fusion.notice("Area prefetch failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Nearby Fused Estimates

    /// Fetch fused busyness estimates for venues near the given coordinates.
    /// Sends all venues in a single POST request. When `venues` is empty,
    /// returns only cached estimates from the server (fast DynamoDB-only query).
    func fetchNearbyEstimates(
        lat: Double,
        lng: Double,
        radius: Double = 2_000,
        venues: [VenueInfo] = []
    ) async throws -> [String: FusedEstimateResponse] {
        if isCacheValid(lat: lat, lng: lng) {
            Log.fusion.debug("Nearby fusion cache hit (\(self.nearbyCache.count) venues)")
            return nearbyCache
        }

        Log.fusion.info("Fetching fused estimates (POST) for \(venues.count) venues")

        let request = NearbyVenuesRequest(
            lat: lat,
            lng: lng,
            radius: Int(radius),
            timezone: TimeZone.current.identifier,
            venues: venues
        )

        let response: NearbyVenuesFusedResponse = try await APIClient.shared.post(
            path: "/v1/venues/nearby",
            body: request
        )

        var indexed: [String: FusedEstimateResponse] = [:]
        for estimate in response.venues {
            if let venueId = estimate.venueId {
                indexed[venueId] = estimate
            }
        }

        Log.fusion.info("Fusion returned \(indexed.count) estimates")
        // Merge into existing cache rather than replacing — preserves pre-fetched data
        if !indexed.isEmpty {
            nearbyCache.merge(indexed) { _, new in new }
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
        Log.fusion.debug("Fetching single-venue busyness for \(venueId, privacy: .public)")
        let encoded = venueId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? venueId
        let queryItems = [
            URLQueryItem(name: "venueName", value: venueName),
            URLQueryItem(name: "lat", value: String(lat)),
            URLQueryItem(name: "lng", value: String(lng)),
            URLQueryItem(name: "timezone", value: TimeZone.current.identifier),
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
        if nearbyCache[venueId] != nil {
            Log.fusion.debug("Fusion cache hit for \(venueId, privacy: .public)")
        }
        return nearbyCache[venueId]
    }

    // MARK: - Cache Control

    func invalidateCache() {
        Log.fusion.debug("Fusion cache invalidated")
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

/// POST body for /v1/venues/nearby.
struct NearbyVenuesRequest: Encodable, Sendable {
    let lat: Double
    let lng: Double
    let radius: Int
    let timezone: String
    let venues: [VenueInfo]
}

/// Response from /v1/venues/nearby.
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
