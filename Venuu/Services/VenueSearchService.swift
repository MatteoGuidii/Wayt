import Foundation
import MapKit

/// Lightweight wrapper around MKLocalSearch.
/// One query at a time — no grid bombardment, no rate-limit gymnastics.
@MainActor
final class VenueSearchService {

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
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = region
        request.resultTypes = .pointOfInterest

        let search = MKLocalSearch(request: request)
        let response = try await search.start()

        return response.mapItems.compactMap { item -> Venue? in
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

            let venueType = Self.classify(item)
            return Venue(mapItem: item, type: venueType)
        }
    }

    /// Search multiple venue types and deduplicate results.
    func searchAllTypes(region: MKCoordinateRegion) async -> [Venue] {
        let queries = ["restaurant", "bar", "cafe", "nightclub", "lounge", "pub"]
        var seen = Set<String>()
        var results: [Venue] = []

        for query in queries {
            do {
                let venues = try await search(query: query, region: region)
                for venue in venues where !seen.contains(venue.id) {
                    seen.insert(venue.id)
                    results.append(venue)
                    if results.count >= AppConstants.maxVisibleVenues { return results }
                }
            } catch {
                // Partial failure is fine — continue with other queries
                print("[VenueSearchService] '\(query)' failed: \(error.localizedDescription)")
            }
        }

        return results
    }

    // MARK: - Classification

    private static func classify(_ item: MKMapItem) -> VenueType {
        let category = item.pointOfInterestCategory
        let name = (item.name ?? "").lowercased()

        // Category-based classification
        if category == .nightlife { return .club }
        if category == .cafe      { return .cafe }
        if category == .bakery    { return .bakery }
        if category == .brewery   { return .pub }

        // Name-based fallback
        if name.contains("club") || name.contains("disco") { return .club }
        if name.contains("lounge") || name.contains("rooftop") { return .lounge }
        if name.contains("pub") || name.contains("brew") { return .pub }
        if name.contains("bar") || name.contains("cocktail") || name.contains("wine") { return .bar }
        if name.contains("cafe") || name.contains("café") || name.contains("coffee") { return .cafe }
        if name.contains("bakery") || name.contains("pastry") { return .bakery }

        return .restaurant
    }
}
