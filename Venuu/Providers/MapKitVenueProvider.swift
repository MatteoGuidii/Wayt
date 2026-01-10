import Foundation
import MapKit

/// MapKit-based venue provider
/// Wraps VenueSearchService to conform to VenueProvider protocol
struct MapKitVenueProvider: VenueProvider {

    // MARK: - VenueProvider Conformance

    let providerId = "mapkit"
    let displayName = "Apple Maps"
    let priority = 100 // Primary provider

    // MARK: - Private

    private let searchService = VenueSearchService()

    // MARK: - Search

    func search(query: String, region: MKCoordinateRegion) async throws -> [ProviderVenue] {
        let venues = try await searchService.searchWithGrid(query: query, region: region)
        return venues.map { venue in
            ProviderVenue(
                id: venue.id.uuidString,
                providerId: providerId,
                name: venue.name,
                coordinate: venue.coordinate,
                category: venue.category?.rawValue,
                rating: nil, // MapKit doesn't provide ratings
                priceLevel: nil, // MapKit doesn't provide price levels
                photoURL: nil // Photos handled separately
            )
        }
    }

    func searchBatch(queries: [String], region: MKCoordinateRegion) async throws -> [ProviderVenue] {
        var allVenues: [ProviderVenue] = []
        var seenKeys = Set<String>()

        // Execute queries concurrently with the search service's grid search
        await withTaskGroup(of: [ProviderVenue].self) { group in
            for query in queries {
                group.addTask {
                    do {
                        return try await self.search(query: query, region: region)
                    } catch {
                        return []
                    }
                }
            }

            for await venues in group {
                for venue in venues {
                    let key = venue.deduplicationKey
                    if !seenKeys.contains(key) {
                        seenKeys.insert(key)
                        allVenues.append(venue)
                    }
                }
            }
        }

        return allVenues
    }
}

// MARK: - Conversion Helpers

extension MapKitVenueProvider {
    /// Convert a ProviderVenue back to internal Venue model
    /// Used when aggregating results from multiple providers
    static func convertToVenue(_ providerVenue: ProviderVenue) -> Venue? {
        let placemark = MKPlacemark(coordinate: providerVenue.coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = providerVenue.name

        return Venue(mapItem: mapItem)
    }

    /// Convert multiple ProviderVenues to Venues
    static func convertToVenues(_ providerVenues: [ProviderVenue]) -> [Venue] {
        providerVenues.compactMap { convertToVenue($0) }
    }
}
