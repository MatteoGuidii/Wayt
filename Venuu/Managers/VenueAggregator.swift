import Foundation
import MapKit

/// Aggregates venue results from multiple providers
/// Handles deduplication, priority-based merging, and conflict resolution
actor VenueAggregator {

    // MARK: - State

    private var providers: [any VenueProvider] = []

    // MARK: - Initialization

    init() {
        // Register MapKit as the default provider
        register(provider: MapKitVenueProvider())
    }

    // MARK: - Provider Management

    /// Register a venue provider
    func register(provider: any VenueProvider) {
        providers.append(provider)
        // Sort by priority (highest first)
        providers.sort { $0.priority > $1.priority }
    }

    /// Remove a provider by ID
    func unregister(providerId: String) {
        providers.removeAll { $0.providerId == providerId }
    }

    /// Get all registered providers
    func getProviders() -> [any VenueProvider] {
        return providers
    }

    // MARK: - Search

    /// Search across all registered providers
    /// - Parameters:
    ///   - query: Search query
    ///   - region: Geographic region to search
    /// - Returns: Merged and deduplicated venues
    func search(query: String, region: MKCoordinateRegion) async -> [Venue] {
        let providerResults = await searchAllProviders(query: query, region: region)
        let merged = mergeResults(providerResults)
        return convertToVenues(merged)
    }

    /// Search with multiple queries across all providers
    func searchBatch(queries: [String], region: MKCoordinateRegion) async -> [Venue] {
        let providerResults = await searchAllProvidersBatch(queries: queries, region: region)
        let merged = mergeResults(providerResults)
        return convertToVenues(merged)
    }

    // MARK: - Private Methods

    private func searchAllProviders(
        query: String,
        region: MKCoordinateRegion
    ) async -> [(providerId: String, priority: Int, venues: [ProviderVenue])] {
        await withTaskGroup(of: (String, Int, [ProviderVenue]).self) { group in
            for provider in providers {
                group.addTask {
                    do {
                        let venues = try await provider.search(query: query, region: region)
                        return (provider.providerId, provider.priority, venues)
                    } catch {
                        return (provider.providerId, provider.priority, [])
                    }
                }
            }

            var results: [(String, Int, [ProviderVenue])] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
    }

    private func searchAllProvidersBatch(
        queries: [String],
        region: MKCoordinateRegion
    ) async -> [(providerId: String, priority: Int, venues: [ProviderVenue])] {
        await withTaskGroup(of: (String, Int, [ProviderVenue]).self) { group in
            for provider in providers {
                group.addTask {
                    do {
                        let venues = try await provider.searchBatch(queries: queries, region: region)
                        return (provider.providerId, provider.priority, venues)
                    } catch {
                        return (provider.providerId, provider.priority, [])
                    }
                }
            }

            var results: [(String, Int, [ProviderVenue])] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
    }

    /// Merge results from multiple providers with priority-based conflict resolution
    private func mergeResults(
        _ results: [(providerId: String, priority: Int, venues: [ProviderVenue])]
    ) -> [ProviderVenue] {
        // Dictionary to track best venue for each location
        var venuesByKey: [String: (venue: ProviderVenue, priority: Int)] = [:]

        // Sort results by priority (highest first)
        let sortedResults = results.sorted { $0.priority > $1.priority }

        for (_, priority, venues) in sortedResults {
            for venue in venues {
                let key = venue.deduplicationKey

                if let existing = venuesByKey[key] {
                    // Keep higher priority provider's data
                    if priority > existing.priority {
                        venuesByKey[key] = (venue, priority)
                    }
                    // If same priority, keep existing (first wins)
                } else {
                    venuesByKey[key] = (venue, priority)
                }
            }
        }

        return venuesByKey.values.map { $0.venue }
    }

    /// Convert ProviderVenues to internal Venue model
    private func convertToVenues(_ providerVenues: [ProviderVenue]) -> [Venue] {
        providerVenues.compactMap { providerVenue in
            let placemark = MKPlacemark(coordinate: providerVenue.coordinate)
            let mapItem = MKMapItem(placemark: placemark)
            mapItem.name = providerVenue.name
            return Venue(mapItem: mapItem)
        }
    }
}

// MARK: - Shared Instance

extension VenueAggregator {
    /// Shared aggregator instance
    static let shared = VenueAggregator()
}
