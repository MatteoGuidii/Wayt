import Foundation
import MapKit
import Combine
import UIKit

@MainActor
class VenueDiscoveryManager: ObservableObject {
    @Published var venues: [Venue] = []
    @Published var isSearching = false
    @Published var searchError: String?
    @Published var didHitResultLimit = false
    @Published var searchedRegion: MKCoordinateRegion?

    private var lastSearchLocation: CLLocation?
    private var lastSearchRadius: CLLocationDistance = AppConfiguration.Search.defaultSearchRadius
    private var lastSuccessfulLocation: CLLocation?
    private var shouldRetryAfterEmptyResult = false

    /// Stores previous venues to merge with new results for persistence
    private var persistedVenues: [String: Venue] = [:]

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
                // Populate persisted venues from cache
                for venue in cached {
                    let key = venueKey(for: venue)
                    persistedVenues[key] = venue
                }
            }
        }
    }

    // MARK: - Public API

    /// Triggers a search around the user's location if they have moved significantly
    func updateUserLocation(_ location: CLLocation, radius: CLLocationDistance? = nil) {
        // Don't interrupt an ongoing user-initiated search (text search or region search)
        guard !isSearching else { return }

        let searchRadius = radius ?? AppConfiguration.Search.defaultSearchRadius

        if shouldRetryAfterEmptyResult {
            shouldRetryAfterEmptyResult = false
            performSearch(near: location.coordinate, radius: searchRadius, mode: .discovery)
            lastSearchLocation = location
            lastSearchRadius = searchRadius
            return
        }

        // Only search if we haven't searched yet, or if we've moved significantly
        // OR if the radius has changed significantly
        guard let lastLocation = lastSearchLocation else {
            performSearch(near: location.coordinate, radius: searchRadius, mode: .discovery)
            lastSearchLocation = location
            lastSearchRadius = searchRadius
            return
        }

        let distance = location.distance(from: lastLocation)
        let radiusRatio = abs(searchRadius - lastSearchRadius) / lastSearchRadius

        if distance > AppConfiguration.Search.minimumDistanceForNewSearch ||
           radiusRatio > AppConfiguration.Search.minimumRadiusChangeRatio {
            performSearch(near: location.coordinate, radius: searchRadius, mode: .discovery)
            lastSearchLocation = location
            lastSearchRadius = searchRadius
        }
    }

    /// Performs a search with a specific query (e.g. from search bar)
    /// Uses extended radius to find venues further away
    func search(text: String) {
        guard let location = lastSearchLocation else { return }
        // Use extended radius for text searches to find specific venues
        let searchRadius = AppConfiguration.Search.textSearchRadius
        performSearch(near: location.coordinate, searchText: text, radius: searchRadius, mode: .textSearch)
    }

    /// Search a specific region (for "Search This Area" functionality)
    func searchRegion(_ region: MKCoordinateRegion) {
        let radius = region.span.toRadius()
        performSearch(near: region.center, radius: radius, mode: .regionSearch)
        lastSearchLocation = CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)
        lastSearchRadius = radius
    }

    /// Clears text search and returns to discovery mode
    func clearSearch() {
        guard let location = lastSearchLocation else { return }
        performSearch(near: location.coordinate, radius: lastSearchRadius, mode: .discovery)
    }

    // MARK: - Private

    private enum SearchMode {
        case discovery      // Normal location-based discovery
        case textSearch     // Searching for specific venue by name
        case regionSearch   // User-initiated "search this area"
    }

    private func venueKey(for venue: Venue) -> String {
        "\(venue.name)_\(String(format: "%.5f", venue.coordinate.latitude))_\(String(format: "%.5f", venue.coordinate.longitude))"
    }

    /// Calculates soft distance penalty using decay curve
    private func calculateDistancePenalty(distance: CLLocationDistance, maxRadius: CLLocationDistance) -> Int {
        let decayStart = AppConfiguration.VenueScoring.distanceDecayStart
        let maxPenalty = AppConfiguration.VenueScoring.maxDistancePenalty

        guard distance > decayStart else { return 0 }

        // Linear decay from decayStart to maxRadius
        let decayRange = maxRadius - decayStart
        guard decayRange > 0 else { return 0 }

        let decayProgress = min((distance - decayStart) / decayRange, 1.0)
        return Int(Double(maxPenalty) * decayProgress)
    }
    
    private func performSearch(
        near center: CLLocationCoordinate2D,
        searchText: String = "",
        radius: CLLocationDistance,
        mode: SearchMode
    ) {
        searchTask?.cancel()
        isSearching = true

        let searchService = self.searchService
        let cacheManager = self.cacheManager
        let imageService = self.imageService
        let searchCenter = center
        let currentPersistedVenues = self.persistedVenues

        searchTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            // Debounce only for discovery mode (not for explicit searches)
            if mode == .discovery {
                try? await Task.sleep(nanoseconds: AppConfiguration.Search.debounceDelayNanoseconds)
            }

            if Task.isCancelled { return }

            // Dynamic radius: start with requested, may expand if results are sparse
            var currentRadius = radius
            var allFoundVenues: [(venue: Venue, rank: Int)] = []
            var searchAttempt = 0
            let maxAttempts = mode == .discovery ? 2 : 1 // Only expand radius in discovery mode

            while searchAttempt < maxAttempts {
                searchAttempt += 1

                let searchRegion = MKCoordinateRegion(
                    center: searchCenter,
                    latitudinalMeters: currentRadius * 2,
                    longitudinalMeters: currentRadius * 2
                )

                // Update searchedRegion for UI feedback
                await MainActor.run {
                    self.searchedRegion = searchRegion
                }

                let queries = await searchService.getQueries(for: searchText)

                // Use an actor to safely collect venues from concurrent tasks
                actor VenueCollector {
                    private var scoredVenues: [(venue: Venue, rank: Int)] = []
                    private var seenVenueKeys: Set<String> = []

                    func add(_ venues: [(venue: Venue, key: String)]) {
                        for (index, item) in venues.enumerated() {
                            if !seenVenueKeys.contains(item.key) {
                                scoredVenues.append((item.venue, index))
                                seenVenueKeys.insert(item.key)
                            }
                        }
                    }

                    func getVenues() -> [(venue: Venue, rank: Int)] {
                        return scoredVenues
                    }
                }

                let collector = VenueCollector()

                await withTaskGroup(of: [(venue: Venue, key: String)].self) { group in
                    for query in queries {
                        group.addTask {
                            do {
                                let venues = try await searchService.searchWithGrid(query: query, region: searchRegion)
                                return await MainActor.run {
                                    venues.map { venue in
                                        let key = "\(venue.name)_\(String(format: "%.5f", venue.coordinate.latitude))_\(String(format: "%.5f", venue.coordinate.longitude))"
                                        return (venue: venue, key: key)
                                    }
                                }
                            } catch {
                                return []
                            }
                        }
                    }

                    for await venues in group {
                        await collector.add(venues)
                    }
                }

                if Task.isCancelled { return }

                allFoundVenues = await collector.getVenues()

                // Check if we need to expand radius (only in discovery mode)
                if mode == .discovery &&
                   allFoundVenues.count < AppConfiguration.Search.minVenuesBeforeExpansion &&
                   currentRadius < AppConfiguration.Search.maxSearchRadius {
                    // Expand radius and retry
                    currentRadius = min(
                        currentRadius * AppConfiguration.Search.radiusExpansionMultiplier,
                        AppConfiguration.Search.maxSearchRadius
                    )
                } else {
                    break // Enough results or max radius reached
                }
            }

            if Task.isCancelled { return }

            let userLocation = CLLocation(latitude: searchCenter.latitude, longitude: searchCenter.longitude)
            let effectiveRadius = currentRadius

            // For text search, also filter by name matching
            var filteredByText: [(venue: Venue, rank: Int)]
            if !searchText.isEmpty {
                let searchLower = searchText.lowercased()
                filteredByText = allFoundVenues.filter { item in
                    item.venue.name.lowercased().contains(searchLower)
                }
                // If no exact matches, fall back to all results (API already filtered by query)
                if filteredByText.isEmpty {
                    filteredByText = allFoundVenues
                }
            } else {
                filteredByText = allFoundVenues
            }

            // Calculate proximity counts for scoring
            let venuesWithProximity = await MainActor.run {
                filteredByText.compactMap { item -> (venue: Venue, rank: Int, nearbyCount: Int)? in
                    let venueLocation = CLLocation(latitude: item.venue.coordinate.latitude, longitude: item.venue.coordinate.longitude)
                    let distance = venueLocation.distance(from: userLocation)
                    let isNearby = distance <= 5000
                    return (venue: item.venue, rank: item.rank, nearbyCount: isNearby ? 1 : 0)
                }
            }

            // Score each venue
            let allScoredVenues = await MainActor.run {
                venuesWithProximity.compactMap { item -> (venue: Venue, rank: Int, classification: VenueClassification)? in
                    let classification = VenueClassifier.classifyWithConfidence(
                        mapItem: item.venue.mapItem,
                        nearbyNightlifeCount: item.nearbyCount
                    )

                    var scoredVenue = item.venue
                    scoredVenue.confidenceScore = classification.confidenceScore

                    return (venue: scoredVenue, rank: item.rank, classification: classification)
                }
            }

            // Determine adaptive threshold based on venue density
            let venueCount = allScoredVenues.count
            let adaptiveThreshold: Int

            // Text search mode is more permissive - user is looking for something specific
            if mode == .textSearch {
                adaptiveThreshold = 0 // No filtering for text search
            } else if venueCount >= AppConfiguration.VenueScoring.highDensityThreshold {
                adaptiveThreshold = AppConfiguration.VenueScoring.minimumNightlifeScoreHighDensity
            } else if venueCount <= AppConfiguration.VenueScoring.lowDensityThreshold {
                adaptiveThreshold = AppConfiguration.VenueScoring.minimumNightlifeScoreLowDensity
            } else {
                adaptiveThreshold = AppConfiguration.VenueScoring.minimumNightlifeScore
            }

            // Filter by threshold and create ranked venues
            let enrichedVenues = await MainActor.run {
                allScoredVenues.compactMap { item -> RankedVenue? in
                    guard item.classification.confidenceScore >= adaptiveThreshold else {
                        return nil
                    }

                    return RankedVenue(
                        venue: item.venue,
                        rank: item.rank,
                        latitude: item.venue.coordinate.latitude,
                        longitude: item.venue.coordinate.longitude,
                        type: item.classification.type,
                        confidenceScore: Double(item.classification.confidenceScore)
                    )
                }
            }

            // Filter by distance
            let validVenues = enrichedVenues.filter { item in
                let venueLoc = CLLocation(latitude: item.latitude, longitude: item.longitude)
                return venueLoc.distance(from: userLocation) <= effectiveRadius
            }

            // Sort using soft distance penalty
            let sortedItemTuples = await MainActor.run { [self] in
                validVenues.sorted { item1, item2 in
                    let loc1 = CLLocation(latitude: item1.latitude, longitude: item1.longitude)
                    let loc2 = CLLocation(latitude: item2.latitude, longitude: item2.longitude)

                    let dist1 = loc1.distance(from: userLocation)
                    let dist2 = loc2.distance(from: userLocation)

                    // Use soft distance penalty instead of hard cutoff
                    let penalty1 = self.calculateDistancePenalty(distance: dist1, maxRadius: effectiveRadius)
                    let penalty2 = self.calculateDistancePenalty(distance: dist2, maxRadius: effectiveRadius)

                    let score1 = item1.rank + penalty1
                    let score2 = item2.rank + penalty2

                    if score1 == score2 {
                        return dist1 < dist2
                    } else {
                        return score1 < score2
                    }
                }
            }

            let finalVenues = sortedItemTuples.map { $0.venue }
            var limitedVenues = Array(finalVenues.prefix(AppConfiguration.Search.maxResultCount))

            // Result persistence: merge with persisted venues that are still in range
            if mode == .discovery && !currentPersistedVenues.isEmpty {
                let existingKeys = Set(limitedVenues.map { venue in
                    "\(venue.name)_\(String(format: "%.5f", venue.coordinate.latitude))_\(String(format: "%.5f", venue.coordinate.longitude))"
                })

                // Add persisted venues that are within expanded range and not already in results
                for (key, venue) in currentPersistedVenues {
                    if !existingKeys.contains(key) {
                        let venueLoc = CLLocation(latitude: venue.coordinate.latitude, longitude: venue.coordinate.longitude)
                        let distance = venueLoc.distance(from: userLocation)
                        // Keep persisted venues within 1.5x the search radius
                        if distance <= effectiveRadius * 1.5 {
                            limitedVenues.append(venue)
                        }
                    }
                }

                // Re-limit after merging
                limitedVenues = Array(limitedVenues.prefix(AppConfiguration.Search.maxResultCount))
            }

            let shouldPersistResults = await MainActor.run { [weak self] () -> Bool in
                guard let self = self else { return false }
                defer { self.isSearching = false }

                let searchLocation = userLocation
                self.didHitResultLimit = limitedVenues.count >= AppConfiguration.Search.maxResultCount

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
                        // Don't clear venues - keep showing what we had
                        self.lastSuccessfulLocation = nil
                    }
                    return false
                }

                self.shouldRetryAfterEmptyResult = false
                self.venues = limitedVenues

                // Update persisted venues
                for venue in limitedVenues {
                    let key = self.venueKey(for: venue)
                    self.persistedVenues[key] = venue
                }

                // Limit persisted venue cache size
                if self.persistedVenues.count > 500 {
                    // Remove oldest entries (arbitrary, could be improved with timestamps)
                    let keysToRemove = Array(self.persistedVenues.keys.prefix(self.persistedVenues.count - 500))
                    for key in keysToRemove {
                        self.persistedVenues.removeValue(forKey: key)
                    }
                }

                self.lastSuccessfulLocation = searchLocation
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
                Task { @MainActor in
                    guard let self = self else { return }
                    if let index = self.venues.firstIndex(where: { $0.id == id }) {
                        self.venues[index].image = image
                    }
                    // Also update persisted venues with images
                    for (key, var venue) in self.persistedVenues {
                        if venue.id == id {
                            venue.image = image
                            self.persistedVenues[key] = venue
                            break
                        }
                    }
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
    let confidenceScore: Double
}

// MARK: - Helpers

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
