import CoreLocation
import Foundation
import MapKit
import os

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
    /// Apple enforces 50 requests / 60 seconds across ALL MapKit server calls,
    /// including internal batch-spatial-lookup requests triggered by map annotation rendering.
    /// Reserve ~15 slots for those internal requests.
    private static let maxRequestsPerWindow = 35
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

    /// Reset the rate limiter. Call when the user performs an explicit action
    /// (e.g. "Search This Area") so MapKit queries are never silently skipped.
    func resetRateLimit() {
        Self.requestTimestamps.removeAll()
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
        // Region bucket: ~100m precision for center, log-scale for zoom
        let latBucket = Int((region.center.latitude * 1000).rounded(.down))
        let lngBucket = Int((region.center.longitude * 1000).rounded(.down))
        let zoomBucket = Int(log2(max(region.span.latitudeDelta, 0.001) * 1000))
        return "\(normalizedQuery(query))|\(latBucket)|\(lngBucket)|\(zoomBucket)"
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
        let prefix = normalizedQuery(query) + "|"
        let now = Date()

        // Find the best matching stale entry for this query
        var bestEntry: CachedSearch?
        var bestScore = Double.greatestFiniteMagnitude

        for (key, entry) in queryCache where key.hasPrefix(prefix) {
            guard now.timeIntervalSince(entry.timestamp) < Self.cacheTTL * 2 else { continue }

            if let target = region {
                // Skip if cached region is much smaller than requested
                let cachedSpan = entry.region.span.latitudeDelta
                let targetSpan = target.span.latitudeDelta
                if cachedSpan > 0, targetSpan / cachedSpan > 2.0 {
                    continue
                }

                // Skip if cached center is far from requested center
                let latDiff = abs(entry.region.center.latitude - target.center.latitude)
                let lngDiff = abs(entry.region.center.longitude - target.center.longitude)
                let maxDrift = max(targetSpan, cachedSpan)
                if latDiff > maxDrift || lngDiff > maxDrift {
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
        .evCharger, .laundry, .postOffice, .store,
        .foodMarket
    ]

    /// Known fast-food chains to filter out
    private static let excludedNames: Set<String> = [
        "mcdonald's", "burger king", "wendy's", "taco bell",
        "kfc", "subway", "chick-fil-a", "popeyes",
        "dunkin'", "domino's", "pizza hut", "papa john's"
    ]

    /// Returns true if the lowercased venue name matches an excluded chain.
    /// Uses prefix matching so "Subway" and "McDonald's King St" are excluded,
    /// but "Subway Sushi Bar" passes through.
    private static func isExcludedChain(_ name: String) -> Bool {
        if excludedNames.contains(name) { return true }
        for chain in excludedNames {
            if name.hasPrefix(chain) {
                let remainder = name.dropFirst(chain.count)
                if remainder.isEmpty || remainder.first?.isLetter == false {
                    return true
                }
            }
        }
        return false
    }

    // MARK: - Non-Venue Filtering

    /// Keywords in a lowercased name that indicate a non-venue (home business, event, service).
    private static let nonVenueKeywords: [String] = [
        "beauty bar", "nail bar", "lash bar", "brow bar", "hair bar",
        "salon", "spa ", "nails", "lashes", "esthetics", "aesthetics",
        "tattoo", "piercing", "tanning",
        "monthly social", "weekly social", "dance social",
        "dance class", "fitness class", "yoga class",
        "with live band", "with dj",
        "meetup", "meet up", "networking event",
        "photo studio", "photography", "videography",
        "tutoring", "daycare", "dog grooming", "pet grooming",
        "cleaning service", "moving company", "plumbing", "roofing",
        "accounting", "consulting", "insurance",
        "catering", "caterer",
        "mobile bar", "traveling", "travelling",
        "bartender", "bartending",
        "event planner", "event planning", "event rental",
        "food truck",
    ]

    /// Name patterns that suggest an event listing rather than a permanent venue.
    /// Long names with dashes/pipes often indicate event descriptions, not venue names.
    private static func isNonVenue(_ name: String) -> Bool {
        // Check non-venue keywords
        for keyword in nonVenueKeywords {
            if name.contains(keyword) { return true }
        }

        // Very long names (>60 chars) with separators are typically event listings
        // e.g. "Vamos a Bailar - Latin Dance - Monthly Social with LIVE Band..."
        if name.count > 60, name.contains(" - ") || name.contains(" | ") {
            return true
        }

        return false
    }

    // MARK: - Search

    /// Search venues by natural language query within a map region.
    func search(
        query: String,
        region: MKCoordinateRegion
    ) async throws -> [Venue] {
        // Return cached results if the region hasn't changed much
        if let cached = cachedResults(for: query, region: region) {
            Log.search.debug("Cache hit for '\(query, privacy: .public)'")
            return cached
        }

        // Rate-limit guard — return stale cache or skip instead of blocking
        if !canMakeRequest() {
            Log.search.notice("Rate limited: returning stale cache for '\(query, privacy: .public)'")
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

            // Filter excluded fast-food chains (prefix match, not substring)
            if Self.isExcludedChain(name) { return nil }

            // Filter home businesses, events, and non-venue services
            if Self.isNonVenue(name) { return nil }

            // Filter excluded categories
            if let category = item.pointOfInterestCategory,
               Self.excludedCategories.contains(category) {
                return nil
            }

            // Filter to venues within the search region + 10% buffer (MKLocalSearch returns results beyond it)
            let coord = item.placemark.coordinate
            if !region.containsWithBuffer(coord) {
                return nil
            }

            return Venue(mapItem: item)
        }

        Log.search.info("'\(query, privacy: .public)' returned \(venues.count) venues (from \(response.mapItems.count) items)")
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
                Log.search.info("Retrying '\(query, privacy: .public)' (attempt \(attempt + 1))")
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
                Log.search.notice("'\(query, privacy: .public)' timed out (attempt \(attempt + 1))")
            } catch is CancellationError {
                return []
            } catch {
                Log.search.error("'\(query, privacy: .public)' failed (attempt \(attempt + 1)): \(error.localizedDescription)")
            }
        }

        // All retries exhausted — return stale cache if available
        if let stale = staleCachedResults(for: query, region: region) {
            Log.search.notice("'\(query, privacy: .public)' returning stale cache after retries")
            return stale
        }
        return []
    }

    // MARK: - Category-Based Search

    /// Search venues by MapKit POI category within a map region.
    /// Complements keyword search by matching on MapKit's internal classification.
    func searchByCategory(
        _ category: MKPointOfInterestCategory,
        region: MKCoordinateRegion
    ) async throws -> [Venue] {
        let cacheLabel = "cat:\(category.rawValue)"

        if let cached = cachedResults(for: cacheLabel, region: region) {
            Log.search.debug("Cache hit for category '\(category.rawValue, privacy: .public)'")
            return cached
        }

        if !canMakeRequest() {
            Log.search.notice("Rate limited: returning stale cache for category '\(category.rawValue, privacy: .public)'")
            return staleCachedResults(for: cacheLabel, region: region) ?? []
        }

        recordRequest()

        let request = MKLocalPointsOfInterestRequest(coordinateRegion: region)
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [category])

        let search = MKLocalSearch(request: request)
        let response = try await search.start()

        let venues = response.mapItems.compactMap { item -> Venue? in
            guard let name = item.name?.lowercased() else { return nil }

            if Self.isExcludedChain(name) { return nil }

            // Filter home businesses, events, and non-venue services
            if Self.isNonVenue(name) { return nil }

            if let poi = item.pointOfInterestCategory,
               Self.excludedCategories.contains(poi) {
                return nil
            }

            let coord = item.placemark.coordinate
            if !region.containsWithBuffer(coord) { return nil }

            return Venue(mapItem: item)
        }

        Log.search.info("Category '\(category.rawValue, privacy: .public)' returned \(venues.count) venues (from \(response.mapItems.count) items)")
        pruneCacheIfNeeded()
        queryCache[cacheKey(for: cacheLabel, region: region)] = CachedSearch(region: region, results: venues, timestamp: Date())
        return venues
    }

    // MARK: - Category Timeout-Protected Search

    /// Execute a single category search with timeout and retry.
    private func searchCategoryWithTimeout(
        category: MKPointOfInterestCategory,
        region: MKCoordinateRegion
    ) async -> [Venue] {
        let label = category.rawValue
        for attempt in 0...Self.maxRetries {
            guard !Task.isCancelled else { return [] }

            if attempt > 0 {
                try? await Task.sleep(for: .milliseconds(500 * attempt))
                guard !Task.isCancelled else { return [] }
                Log.search.info("Retrying category '\(label, privacy: .public)' (attempt \(attempt + 1))")
            }

            do {
                let result: [Venue]? = try await withThrowingTaskGroup(of: [Venue]?.self) { group in
                    group.addTask { [self] () -> [Venue]? in
                        try await self.searchByCategory(category, region: region)
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
                            return nil
                        }
                    }
                    return nil
                }

                if let venues = result { return venues }
                Log.search.notice("Category '\(label, privacy: .public)' timed out (attempt \(attempt + 1))")
            } catch is CancellationError {
                return []
            } catch {
                Log.search.error("Category '\(label, privacy: .public)' failed (attempt \(attempt + 1)): \(error.localizedDescription)")
            }
        }

        if let stale = staleCachedResults(for: "cat:\(label)", region: region) {
            Log.search.notice("Category '\(label, privacy: .public)' returning stale cache after retries")
            return stale
        }
        return []
    }

    // MARK: - Multi-Type Search

    /// Search multiple venue types concurrently with progressive results.
    ///
    /// Two-tier approach for maximum coverage, all queries run in parallel:
    /// - Category-based searches (broad coverage by MapKit classification)
    /// - Keyword searches (catch niche venues MapKit doesn't categorize well)
    ///
    /// Each completed query calls `onBatch` with deduplicated accumulated results
    /// so the UI can update progressively.
    func searchAllTypes(
        region: MKCoordinateRegion,
        onBatch: (([Venue]) -> Void)? = nil
    ) async -> [Venue] {
        let center = CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)

        var seen = Set<String>()
        var accumulated: [Venue] = []

        // Stagger queries in small batches to avoid exceeding Apple's shared
        // 50 req/60s budget (which includes internal map annotation lookups).
        let categories: [MKPointOfInterestCategory] = [
            .restaurant, .cafe, .nightlife, .bakery, .brewery, .winery
        ]
        let keywords = ["restaurant", "bar", "lounge", "brunch", "pub", "diner"]
        Log.search.debug("Starting \(categories.count) category + \(keywords.count) keyword searches in staggered batches")

        // Batch 1: category searches (6 concurrent)
        await withTaskGroup(of: [Venue].self) { group in
            for category in categories {
                group.addTask {
                    await self.searchCategoryWithTimeout(category: category, region: region)
                }
            }

            for await batch in group {
                for venue in batch where !seen.contains(venue.id) {
                    seen.insert(venue.id)
                    accumulated.append(venue)
                }
                onBatch?(accumulated)
            }
        }

        // Batch 2: keyword searches (6 concurrent)
        await withTaskGroup(of: [Venue].self) { group in
            for keyword in keywords {
                group.addTask {
                    await self.searchWithTimeout(query: keyword, region: region)
                }
            }

            for await batch in group {
                for venue in batch where !seen.contains(venue.id) {
                    seen.insert(venue.id)
                    accumulated.append(venue)
                }
                onBatch?(accumulated)
            }
        }

        Log.search.info("All searches complete: \(accumulated.count) total unique venues")

        // Precompute distances, sort, and cap at limit — closest venues first
        let distances = accumulated.map { venue in
            center.distance(from: CLLocation(latitude: venue.coordinate.latitude, longitude: venue.coordinate.longitude))
        }
        let sortedIndices = distances.enumerated()
            .sorted { $0.element < $1.element }
            .prefix(AppConstants.maxVisibleVenues)
            .map(\.offset)
        accumulated = sortedIndices.map { accumulated[$0] }

        Log.search.info("Multi-type search complete: \(accumulated.count) venues after distance cap")
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

    /// Returns true if the coordinate falls within this region plus a buffer (~10% by default).
    func containsWithBuffer(_ coordinate: CLLocationCoordinate2D, bufferFraction: Double = 0.1) -> Bool {
        let halfLat = span.latitudeDelta / 2.0 * (1.0 + bufferFraction)
        let halfLng = span.longitudeDelta / 2.0 * (1.0 + bufferFraction)
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
