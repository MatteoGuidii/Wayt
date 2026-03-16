import Foundation
import MapKit

/// Lightweight wrapper around MKLocalSearch with result caching and rate-limit protection.
@MainActor
final class VenueSearchService {

    // MARK: - Cache

    private struct CachedSearch {
        let region: MKCoordinateRegion
        let results: [Venue]
        let timestamp: Date
    }

    /// Per-query cache for recent search results (avoids redundant MapKit calls).
    private var queryCache: [String: CachedSearch] = [:]
    private static let cacheTTL: TimeInterval = 300 // 5 minutes
    private static let maxCacheEntries = 50

    // MARK: - Rate Limiting (shared across all instances)

    /// Timestamps of recent MapKit requests (sliding window). Static so all instances share the budget.
    private static var requestTimestamps: [Date] = []
    /// Apple enforces 50 requests / 60 seconds. Stay well under that.
    private static let maxRequestsPerWindow = 40
    private static let windowDuration: TimeInterval = 60

    /// Returns true if we can safely make another request. Prunes stale timestamps.
    private func canMakeRequest() -> Bool {
        let cutoff = Date().addingTimeInterval(-Self.windowDuration)
        Self.requestTimestamps.removeAll { $0 < cutoff }
        return Self.requestTimestamps.count < Self.maxRequestsPerWindow
    }

    private func recordRequest() {
        Self.requestTimestamps.append(Date())
    }

    // MARK: - Query Normalization & Cache

    private func normalizedQuery(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func pruneCacheIfNeeded() {
        let now = Date()
        queryCache = queryCache.filter { _, value in
            now.timeIntervalSince(value.timestamp) < Self.cacheTTL
        }
        if queryCache.count > Self.maxCacheEntries {
            let sortedKeys = queryCache.keys.sorted { lhs, rhs in
                (queryCache[lhs]?.timestamp ?? .distantPast) < (queryCache[rhs]?.timestamp ?? .distantPast)
            }
            for key in sortedKeys.prefix(queryCache.count - Self.maxCacheEntries) {
                queryCache.removeValue(forKey: key)
            }
        }
    }

    private func cachedResults(for query: String, region: MKCoordinateRegion) -> [Venue]? {
        pruneCacheIfNeeded()
        let cacheKey = normalizedQuery(query)
        guard let entry = queryCache[cacheKey],
              Date().timeIntervalSince(entry.timestamp) < Self.cacheTTL,
              entry.region.isClose(to: region) else {
            return nil
        }
        return entry.results
    }

    // MARK: - Excluded Categories

    private static let excludedCategories: Set<MKPointOfInterestCategory> = [
        .gasStation, .atm, .bank, .hospital, .pharmacy,
        .police, .fireStation, .parking, .carRental,
        .evCharger, .laundry, .postOffice, .store
    ]

    /// Known fast-food chains to filter out
    private static let excludedNames: Set<String> = [
        "mcdonald's", "burger king", "wendy's", "taco bell",
        "kfc", "subway", "chick-fil-a", "popeyes",
        "dunkin'", "domino's", "pizza hut", "papa john's"
    ]

    // MARK: - Search

    /// Search venues by natural language query within a map region.
    func search(
        query: String,
        region: MKCoordinateRegion
    ) async throws -> [Venue] {
        // Return cached results if the region hasn't changed much
        if let cached = cachedResults(for: query, region: region) {
            return cached
        }

        // Rate-limit guard — wait for budget to free up instead of dropping the query
        if !canMakeRequest() {
            print("[VenueSearchService] Rate limit guard: waiting before '\(query)'")
            try await Task.sleep(for: .seconds(5))
            // Re-check after wait; if still exhausted, skip
            guard canMakeRequest() else {
                print("[VenueSearchService] Rate limit guard: skipping '\(query)'")
                return []
            }
        }

        recordRequest()

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = region
        request.resultTypes = .pointOfInterest

        let search = MKLocalSearch(request: request)
        let response = try await search.start()

        let venues = response.mapItems.compactMap { item -> Venue? in
            guard let name = item.name?.lowercased() else { return nil }

            // Filter excluded names
            if Self.excludedNames.contains(where: { name.contains($0) }) {
                return nil
            }

            // Filter excluded categories
            if let category = item.pointOfInterestCategory,
               Self.excludedCategories.contains(category) {
                return nil
            }

            // Filter to venues within the search region (MKLocalSearch returns results beyond it)
            let coord = item.placemark.coordinate
            if !region.contains(coord) {
                return nil
            }

            return Venue(mapItem: item)
        }

        pruneCacheIfNeeded()
        queryCache[normalizedQuery(query)] = CachedSearch(region: region, results: venues, timestamp: Date())
        return venues
    }

    /// Search multiple venue types concurrently and deduplicate results.
    ///
    /// Fires all 6 queries in parallel to minimize wall-clock time while staying
    /// well under Apple's 50-req/60s limit.
    func searchAllTypes(region: MKCoordinateRegion) async -> [Venue] {
        let queries = ["restaurant", "bar", "cafe", "nightclub", "pub", "bakery"]

        let allResults = await withTaskGroup(of: [Venue].self) { group in
            for query in queries {
                group.addTask {
                    do {
                        return try await self.search(query: query, region: region)
                    } catch {
                        print("[VenueSearchService] '\(query)' failed: \(error.localizedDescription)")
                        return []
                    }
                }
            }

            var collected: [Venue] = []
            for await venues in group {
                collected.append(contentsOf: venues)
            }
            return collected
        }

        // Deduplicate
        var seen = Set<String>()
        var results: [Venue] = []
        for venue in allResults where !seen.contains(venue.id) {
            seen.insert(venue.id)
            results.append(venue)
            if results.count >= AppConstants.maxVisibleVenues { break }
        }

        return results
    }

}

// MARK: - Region Proximity Check

extension MKCoordinateRegion {
    /// Returns true if the coordinate falls within this region.
    func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        let halfLat = span.latitudeDelta / 2.0
        let halfLng = span.longitudeDelta / 2.0
        return coordinate.latitude >= center.latitude - halfLat
            && coordinate.latitude <= center.latitude + halfLat
            && coordinate.longitude >= center.longitude - halfLng
            && coordinate.longitude <= center.longitude + halfLng
    }

    /// Returns true if two regions overlap substantially and are at a similar zoom level.
    func isClose(to other: MKCoordinateRegion) -> Bool {
        // Center proximity (use the smaller span so a zoomed-in view doesn't match a zoomed-out one)
        let latTolerance = min(span.latitudeDelta, other.span.latitudeDelta) * 0.5
        let lngTolerance = min(span.longitudeDelta, other.span.longitudeDelta) * 0.5
        let latDiff = abs(center.latitude - other.center.latitude)
        let lngDiff = abs(center.longitude - other.center.longitude)
        guard latDiff < latTolerance, lngDiff < lngTolerance else { return false }

        // Span similarity — reject if zoom levels differ by more than 50%
        let latSpanMin = min(span.latitudeDelta, other.span.latitudeDelta)
        let lngSpanMin = min(span.longitudeDelta, other.span.longitudeDelta)
        guard latSpanMin > 0, lngSpanMin > 0 else { return false }

        let maxRatio = 1.5
        let latRatio = max(span.latitudeDelta, other.span.latitudeDelta) / latSpanMin
        let lngRatio = max(span.longitudeDelta, other.span.longitudeDelta) / lngSpanMin
        return latRatio <= maxRatio && lngRatio <= maxRatio
    }
}
