import Foundation
import MapKit

/// Lightweight wrapper around MKLocalSearch with result caching.
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
    private static let cacheTTL: TimeInterval = 120 // 2 minutes

    private func cachedResults(for query: String, region: MKCoordinateRegion) -> [Venue]? {
        guard let entry = queryCache[query],
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

            return Venue(mapItem: item)
        }

        queryCache[query] = CachedSearch(region: region, results: venues, timestamp: Date())
        return venues
    }

    /// Search multiple venue types concurrently and deduplicate results.
    func searchAllTypes(region: MKCoordinateRegion) async -> [Venue] {
        let queries = [
            "restaurant", "bar", "cafe", "nightclub", "lounge", "pub",
            "brewery", "wine bar", "bakery", "brunch", "food truck", "juice bar"
        ]

        // Fire all 6 searches in parallel
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

            var collected: [[Venue]] = []
            for await batch in group {
                collected.append(batch)
            }
            return collected
        }

        // Deduplicate and cap
        var seen = Set<String>()
        var results: [Venue] = []
        for batch in allResults {
            for venue in batch where !seen.contains(venue.id) {
                seen.insert(venue.id)
                results.append(venue)
                if results.count >= AppConstants.maxVisibleVenues { return results }
            }
        }

        return results
    }

}

// MARK: - Region Proximity Check

extension MKCoordinateRegion {
    /// Returns true if two regions overlap substantially (center within half-span).
    func isClose(to other: MKCoordinateRegion) -> Bool {
        let latDiff = abs(center.latitude - other.center.latitude)
        let lngDiff = abs(center.longitude - other.center.longitude)
        return latDiff < span.latitudeDelta * 0.5
            && lngDiff < span.longitudeDelta * 0.5
    }
}
