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

    private func cacheKey(for query: String, region: MKCoordinateRegion) -> String {
        // Coarse region bucket so different zoom levels get separate entries
        let latBucket = Int(region.center.latitude * 100)
        let lngBucket = Int(region.center.longitude * 100)
        let zoomBucket = Int(log2(max(region.span.latitudeDelta, 0.001) * 1000))
        return "\(normalizedQuery(query))_\(latBucket)_\(lngBucket)_\(zoomBucket)"
    }

    private func cachedResults(for query: String, region: MKCoordinateRegion) -> [Venue]? {
        pruneCacheIfNeeded()
        let key = cacheKey(for: query, region: region)
        guard let entry = queryCache[key],
              Date().timeIntervalSince(entry.timestamp) < Self.cacheTTL,
              entry.region.isClose(to: region) else {
            return nil
        }
        return entry.results
    }

    /// Return cached results even if the region doesn't match closely (stale fallback).
    /// Searches all cache entries matching the query prefix. Skips entries whose
    /// region is much smaller than the requested region (would show too few venues).
    private func staleCachedResults(for query: String, region: MKCoordinateRegion? = nil) -> [Venue]? {
        let prefix = normalizedQuery(query)
        let now = Date()

        // Find the best matching stale entry for this query
        var bestEntry: CachedSearch?
        var bestScore = Double.greatestFiniteMagnitude

        for (key, entry) in queryCache where key.hasPrefix(prefix) {
            guard now.timeIntervalSince(entry.timestamp) < Self.cacheTTL * 2 else { continue }

            // If we have a target region and the cached region is much smaller,
            // the stale results are misleading — skip them
            if let target = region {
                let cachedSpan = entry.region.span.latitudeDelta
                let targetSpan = target.span.latitudeDelta
                if cachedSpan > 0, targetSpan / cachedSpan > 2.0 {
                    continue
                }
            }

            // Prefer the most recent entry
            let age = now.timeIntervalSince(entry.timestamp)
            if age < bestScore {
                bestScore = age
                bestEntry = entry
            }
        }

        return bestEntry?.results
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

        // Rate-limit guard — return stale cache or skip instead of blocking
        if !canMakeRequest() {
            print("[VenueSearchService] Rate limit: returning stale cache for '\(query)'")
            return staleCachedResults(for: query, region: region) ?? []
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
        queryCache[cacheKey(for: query, region: region)] = CachedSearch(region: region, results: venues, timestamp: Date())
        return venues
    }

    // MARK: - Timeout-Protected Search

    private static let maxRetries = 2

    /// Execute a single search with timeout and retry. Falls back to stale cache on failure.
    private func searchWithTimeout(
        query: String,
        region: MKCoordinateRegion
    ) async -> [Venue] {
        for attempt in 0...Self.maxRetries {
            guard !Task.isCancelled else { return [] }

            if attempt > 0 {
                // Brief backoff before retry
                try? await Task.sleep(for: .milliseconds(500 * attempt))
                guard !Task.isCancelled else { return [] }
                print("[VenueSearchService] Retrying '\(query)' (attempt \(attempt + 1))")
            }

            do {
                let result: [Venue]? = try await withThrowingTaskGroup(of: [Venue]?.self) { group in
                    group.addTask { [self] () -> [Venue]? in
                        try await self.search(query: query, region: region)
                    }
                    group.addTask { () -> [Venue]? in
                        try await Task.sleep(for: .seconds(AppConstants.mapKitQueryTimeout))
                        return nil
                    }

                    for try await result in group {
                        if let venues = result {
                            group.cancelAll()
                            return venues
                        } else {
                            group.cancelAll()
                            return nil // timeout
                        }
                    }
                    return nil
                }

                if let venues = result {
                    return venues
                }
                // Timeout — retry
                print("[VenueSearchService] '\(query)' timed out (attempt \(attempt + 1))")
            } catch is CancellationError {
                return []
            } catch {
                print("[VenueSearchService] '\(query)' failed (attempt \(attempt + 1)): \(error.localizedDescription)")
            }
        }

        // All retries exhausted — return stale cache if available
        if let stale = staleCachedResults(for: query, region: region) {
            print("[VenueSearchService] '\(query)' returning stale cache after retries")
            return stale
        }
        return []
    }

    // MARK: - Multi-Type Search

    /// Search multiple venue types concurrently with progressive results.
    ///
    /// Fires all 6 queries in parallel. Each completed query calls `onBatch` with
    /// the deduplicated accumulated results so the UI can update progressively.
    func searchAllTypes(
        region: MKCoordinateRegion,
        onBatch: (([Venue]) -> Void)? = nil
    ) async -> [Venue] {
        let queries = ["restaurant", "bar", "cafe", "nightclub", "pub", "bakery"]

        var seen = Set<String>()
        var accumulated: [Venue] = []

        await withTaskGroup(of: [Venue].self) { group in
            for query in queries {
                group.addTask {
                    await self.searchWithTimeout(query: query, region: region)
                }
            }

            for await batch in group {
                for venue in batch where !seen.contains(venue.id) {
                    seen.insert(venue.id)
                    accumulated.append(venue)
                }
                if accumulated.count >= AppConstants.maxVisibleVenues {
                    group.cancelAll()
                    break
                }
                // Notify caller with current accumulated results
                onBatch?(accumulated)
            }
        }

        return accumulated
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
