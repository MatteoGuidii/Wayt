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

        let searchService = self.searchService
        let cacheManager = self.cacheManager
        let imageService = self.imageService
        let searchCenter = center

        searchTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
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
                            let venues = try await searchService.search(query: query, region: searchRegion)
                            return await MainActor.run {
                                venues.map { venue in
                                    (venue: venue, key: "\(venue.name)_\(venue.coordinate.latitude)_\(venue.coordinate.longitude)")
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

            let scoredVenues = await collector.getVenues()
            let userLocation = CLLocation(latitude: searchCenter.latitude, longitude: searchCenter.longitude)

            // Fetch nearby venues for proximity-based scoring
            let venuesWithProximity = await MainActor.run {
                scoredVenues.compactMap { item -> (venue: Venue, rank: Int, nearbyCount: Int)? in
                    let venueLocation = CLLocation(latitude: item.venue.coordinate.latitude, longitude: item.venue.coordinate.longitude)
                    let distance = venueLocation.distance(from: userLocation)

                    // Consider venues within 5km as "nearby" for scoring purposes
                    let isNearby = distance <= 5000

                    return (venue: item.venue, rank: item.rank, nearbyCount: isNearby ? 1 : 0)
                }
            }

            // Score each venue with proximity context
            // First pass: Get all venues with scores to determine density
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
            // This ensures we don't filter out legitimate businesses in any area
            let venueCount = allScoredVenues.count
            let adaptiveThreshold: Int
            if venueCount >= AppConfiguration.VenueScoring.highDensityThreshold {
                // High density area (e.g., downtown Toronto) - be more selective
                adaptiveThreshold = AppConfiguration.VenueScoring.minimumNightlifeScoreHighDensity
            } else if venueCount <= AppConfiguration.VenueScoring.lowDensityThreshold {
                // Low density area (e.g., suburbs) - be more inclusive
                adaptiveThreshold = AppConfiguration.VenueScoring.minimumNightlifeScoreLowDensity
            } else {
                // Medium density - use default threshold
                adaptiveThreshold = AppConfiguration.VenueScoring.minimumNightlifeScore
            }
            
            // Second pass: Filter by adaptive threshold
            let enrichedVenues = await MainActor.run {
                allScoredVenues.compactMap { item -> RankedVenue? in
                    // Filter out venues that don't meet the adaptive threshold
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

            let validVenues = enrichedVenues.filter { item in
                let venueLoc = CLLocation(latitude: item.latitude, longitude: item.longitude)
                let distanceOk = venueLoc.distance(from: userLocation) <= radius
                let typeOk = item.type.isNightlife
                return distanceOk && typeOk
            }

            let sortedItemTuples = validVenues.sorted { item1, item2 in
                let loc1 = CLLocation(latitude: item1.latitude, longitude: item1.longitude)
                let loc2 = CLLocation(latitude: item2.latitude, longitude: item2.longitude)

                let dist1 = loc1.distance(from: userLocation)
                let dist2 = loc2.distance(from: userLocation)

                let penalty1 = dist1 > 5000 ? 20 : 0
                let penalty2 = dist2 > 5000 ? 20 : 0

                let score1 = item1.rank + penalty1
                let score2 = item2.rank + penalty2

                if score1 == score2 {
                    return dist1 < dist2
                } else {
                    return score1 < score2
                }
            }

            let finalVenues = sortedItemTuples.map { $0.venue }
            let limitedVenues = Array(finalVenues.prefix(AppConfiguration.Search.maxResultCount))

            let shouldPersistResults = await MainActor.run { [weak self] () -> Bool in
                guard let self = self else { return false }
                defer { self.isSearching = false }

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
                    return false
                }

                self.shouldRetryAfterEmptyResult = false
                self.venues = limitedVenues
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
