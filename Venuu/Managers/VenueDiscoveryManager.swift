import Foundation
import MapKit
import Combine
import UIKit

@MainActor
class VenueDiscoveryManager: ObservableObject {
    @Published var venues: [Venue] = []
    @Published var isSearching = false
    @Published var didHitResultLimit = false
    @Published var searchError: String?

    private var lastSearchLocation: CLLocation?
    private var lastSearchRadius: CLLocationDistance = AppConfiguration.Search.defaultSearchRadius
    private var lastSuccessfulLocation: CLLocation?
    private var shouldRetryAfterEmptyResult = false
    
    private let searchService = VenueSearchService()
    private let cacheManager = VenueCacheManager.shared
    private let imageService = VenueImageService.shared
    
    private var searchTask: Task<Void, Never>?
    
    init() {
        // Load cached venues on startup
        Task {
            let cached = await cacheManager.loadVenues()
            if !cached.isEmpty {
                self.venues = cached
            }
        }
    }
    
    // MARK: - Public API
    
    /// Triggers a search around the user's location if they have moved significantly
    func updateUserLocation(_ location: CLLocation, radius: CLLocationDistance? = nil) {
        let searchRadius = radius ?? AppConfiguration.Search.defaultSearchRadius
        
        if shouldRetryAfterEmptyResult {
            shouldRetryAfterEmptyResult = false
            performSearch(near: location.coordinate, radius: searchRadius)
            lastSearchLocation = location
            lastSearchRadius = searchRadius
            return
        }

        // Only search if we haven't searched yet, or if we've moved significantly
        // OR if the radius has changed significantly
        guard let lastLocation = lastSearchLocation else {
            performSearch(near: location.coordinate, radius: searchRadius)
            lastSearchLocation = location
            lastSearchRadius = searchRadius
            return
        }

        let distance = location.distance(from: lastLocation)
        let radiusRatio = abs(searchRadius - lastSearchRadius) / lastSearchRadius

        if distance > AppConfiguration.Search.minimumDistanceForNewSearch ||
           radiusRatio > AppConfiguration.Search.minimumRadiusChangeRatio {
            performSearch(near: location.coordinate, radius: searchRadius)
            lastSearchLocation = location
            lastSearchRadius = searchRadius
        }
    }
    
    /// Performs a search with a specific query (e.g. from search bar)
    func search(text: String, radius: CLLocationDistance? = nil) {
        guard let location = lastSearchLocation else { return }
        let searchRadius = radius ?? lastSearchRadius
        performSearch(near: location.coordinate, searchText: text, radius: searchRadius)
    }
    
    private func performSearch(near center: CLLocationCoordinate2D, searchText: String = "", radius: CLLocationDistance) {
        searchTask?.cancel()
        isSearching = true
        searchError = nil  // Clear any previous errors

        let searchService = self.searchService
        let cacheManager = self.cacheManager
        let imageService = self.imageService
        let searchCenter = center

        searchTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            // Ensure isSearching is always cleared when task exits (including cancellation)
            defer {
                Task { @MainActor in
                    self.isSearching = false
                }
            }
            // Debounce for map interactions to prevent excessive searches during rapid zooming
            if searchText.isEmpty {
                try? await Task.sleep(nanoseconds: AppConfiguration.Search.debounceDelayNanoseconds)
            }

            if Task.isCancelled { return }

            let searchRegion = MKCoordinateRegion(
                center: searchCenter,
                latitudinalMeters: radius * 2,
                longitudinalMeters: radius * 2
            )

            let queries = searchService.getQueries(for: searchText)
            
            // Use an actor to safely collect venues from concurrent tasks
            actor VenueCollector {
                private var scoredVenues: [(venue: Venue, rank: Int)] = []
                private var seenVenueKeys: Set<String> = []
                private var successCount = 0
                private var failureCount = 0

                func add(_ venues: [(venue: Venue, key: String)]) {
                    successCount += 1
                    for (index, item) in venues.enumerated() {
                        if !seenVenueKeys.contains(item.key) {
                            scoredVenues.append((item.venue, index))
                            seenVenueKeys.insert(item.key)
                        }
                    }
                }

                func recordFailure() {
                    failureCount += 1
                }

                func getVenues() -> [(venue: Venue, rank: Int)] {
                    return scoredVenues
                }

                func getStats() -> (successCount: Int, failureCount: Int) {
                    return (successCount, failureCount)
                }
            }

            let collector = VenueCollector()

            await withTaskGroup(of: (success: Bool, venues: [(venue: Venue, key: String)]).self) { group in
                for query in queries {
                    group.addTask {
                        do {
                            let venues = try await searchService.search(query: query, region: searchRegion)
                            let mapped = await MainActor.run {
                                venues.map { venue in
                                    (venue: venue, key: "\(venue.name)_\(venue.coordinate.latitude)_\(venue.coordinate.longitude)")
                                }
                            }
                            return (success: true, venues: mapped)
                        } catch {
                            return (success: false, venues: [])
                        }
                    }
                }

                for await result in group {
                    if result.success {
                        await collector.add(result.venues)
                    } else {
                        await collector.recordFailure()
                    }
                }
            }

            if Task.isCancelled { return }

            let stats = await collector.getStats()
            let scoredVenues = await collector.getVenues()
            let userLocation = CLLocation(latitude: searchCenter.latitude, longitude: searchCenter.longitude)

            // Check if all searches failed
            if stats.failureCount > 0 && stats.successCount == 0 {
                await MainActor.run {
                    self.searchError = "Unable to search for venues. Please check your connection."
                }
                return
            }

            // Calculate proximity context for each venue to improve scoring accuracy
            let venuesWithProximity = await MainActor.run {
                scoredVenues.map { item -> (venue: Venue, rank: Int, nearbyCount: Int) in
                    let venueLocation = CLLocation(
                        latitude: item.venue.coordinate.latitude,
                        longitude: item.venue.coordinate.longitude
                    )

                    // Count how many confirmed nightlife venues are nearby
                    let nearbyCount = scoredVenues.filter { other in
                        guard other.venue.id != item.venue.id else { return false }

                        let otherLocation = CLLocation(
                            latitude: other.venue.coordinate.latitude,
                            longitude: other.venue.coordinate.longitude
                        )
                        let distance = venueLocation.distance(from: otherLocation)

                        // Only count venues that are clearly nightlife (not generic restaurants)
                        let otherType = other.venue.type
                        let isConfirmedNightlife = otherType == .bar || otherType == .club ||
                                                   otherType == .pub || otherType == .lounge ||
                                                   otherType == .liveMusic

                        return distance <= AppConfiguration.VenueScoring.proximitySearchRadius && isConfirmedNightlife
                    }.count

                    return (venue: item.venue, rank: item.rank, nearbyCount: nearbyCount)
                }
            }

            // Score each venue with proximity context and filter by confidence
            let enrichedVenues = await MainActor.run {
                venuesWithProximity.compactMap { item -> RankedVenue? in
                    let classification = VenueClassifier.classifyWithConfidence(
                        mapItem: item.venue.mapItem,
                        nearbyNightlifeCount: item.nearbyCount
                    )

                    // Filter out venues that don't meet the minimum nightlife score
                    guard classification.isNightlifeRelevant else {
                        return nil
                    }

                    var scoredVenue = item.venue
                    scoredVenue.confidenceScore = classification.confidenceScore

                    return RankedVenue(
                        venue: scoredVenue,
                        rank: item.rank,
                        latitude: item.venue.coordinate.latitude,
                        longitude: item.venue.coordinate.longitude,
                        type: classification.type,
                        confidenceScore: classification.confidenceScore
                    )
                }
            }

            // Distance filter (already filtered by confidence above)
            let validVenues = enrichedVenues.filter { item in
                let venueLoc = CLLocation(latitude: item.latitude, longitude: item.longitude)
                return venueLoc.distance(from: userLocation) <= radius
            }

            let sortedItemTuples = validVenues.sorted { item1, item2 in
                let loc1 = CLLocation(latitude: item1.latitude, longitude: item1.longitude)
                let loc2 = CLLocation(latitude: item2.latitude, longitude: item2.longitude)

                let dist1 = loc1.distance(from: userLocation)
                let dist2 = loc2.distance(from: userLocation)

                let penalty1 = dist1 > 5000 ? 20 : 0
                let penalty2 = dist2 > 5000 ? 20 : 0

                // Adjust rank with penalties
                let score1 = item1.rank + penalty1
                let score2 = item2.rank + penalty2

                // Primary sort: by rank + penalties (lower is better)
                if score1 != score2 {
                    return score1 < score2
                }

                // Secondary sort: by confidence score (higher is better for same rank)
                if item1.confidenceScore != item2.confidenceScore {
                    return item1.confidenceScore > item2.confidenceScore
                }

                // Tertiary sort: by distance (closer is better)
                return dist1 < dist2
            }

            let finalVenues = sortedItemTuples.map { $0.venue }
            let limitedVenues = Array(finalVenues.prefix(AppConfiguration.Search.maxResultCount))
            let trimmedResults = finalVenues.count > limitedVenues.count

            let shouldPersistResults = await MainActor.run { [weak self] () -> Bool in
                guard let self = self else { return false }

                let searchLocation = userLocation
                let hasExistingVenues = !self.venues.isEmpty
                let isSameAreaAsLastSuccess: Bool = {
                    guard let lastSuccessfulLocation = self.lastSuccessfulLocation else { return false }
                    return lastSuccessfulLocation.distance(from: searchLocation) < AppConfiguration.Search.minimumDistanceForNewSearch
                }()

                guard !limitedVenues.isEmpty else {
                    if hasExistingVenues && isSameAreaAsLastSuccess {
                        self.shouldRetryAfterEmptyResult = true
                    } else {
                        self.shouldRetryAfterEmptyResult = false
                        self.venues = []
                        self.lastSuccessfulLocation = nil
                    }
                    self.didHitResultLimit = false
                    return false
                }

                self.shouldRetryAfterEmptyResult = false
                self.venues = limitedVenues
                self.lastSuccessfulLocation = searchLocation
                self.didHitResultLimit = trimmedResults
                return true
            }

            guard shouldPersistResults else { return }
            if Task.isCancelled { return }

            let cachedVenues = await MainActor.run {
                limitedVenues.map { venue in
                    VenueCacheManager.CachedVenue(
                        id: venue.id,
                        name: venue.name,
                        latitude: venue.coordinate.latitude,
                        longitude: venue.coordinate.longitude,
                        categoryRawValue: venue.category?.rawValue,
                        imageData: nil
                    )
                }
            }

            do {
                try await cacheManager.saveVenues(cachedVenues)
                try await cacheManager.saveImages(for: limitedVenues)
            } catch {
                // Cache save failures are non-critical
            }

            if Task.isCancelled { return }

            await imageService.fetchImages(for: limitedVenues) { [weak self] id, image in
                guard let self = self else { return }
                if let index = self.venues.firstIndex(where: { $0.id == id }) {
                    self.venues[index].image = image
                }
            }
        }
    }
}

private struct RankedVenue: Sendable {
    let venue: Venue
    let rank: Int
    let latitude: Double
    let longitude: Double
    let type: VenueType
    let confidenceScore: Int
}

// MARK: - Helpers

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
