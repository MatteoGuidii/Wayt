import Foundation
import MapKit
import Combine
import UIKit

@MainActor
class VenueDiscoveryManager: ObservableObject {
    @Published var venues: [Venue] = []
    @Published var isSearching = false

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
        // Cancel previous search task
        searchTask?.cancel()
        
        isSearching = true
        
        searchTask = Task {
            // Debounce for map interactions to prevent excessive searches during rapid zooming
            if searchText.isEmpty {
                try? await Task.sleep(nanoseconds: AppConfiguration.Search.debounceDelayNanoseconds)
            }
            
            if Task.isCancelled { return }
            
            let searchRegion = MKCoordinateRegion(
                center: center,
                latitudinalMeters: radius * 2,
                longitudinalMeters: radius * 2
            )
            
            let queries = searchService.getQueries(for: searchText)
            // Store venues with their search rank (index in the Apple Maps response)
            // (Venue, Rank)
            var scoredVenues: [(venue: Venue, rank: Int)] = []
            var seenVenues: Set<Venue> = []

            await withTaskGroup(of: [Venue].self) { group in
                for query in queries {
                    group.addTask {
                        do {
                            return try await self.searchService.search(query: query, region: searchRegion)
                        } catch {
                            return []
                        }
                    }
                }

                for await venues in group {
                    for (index, venue) in venues.enumerated() {
                        // Use Venue's Hashable implementation for proper deduplication
                        if !seenVenues.contains(venue) {
                            scoredVenues.append((venue, index))
                            seenVenues.insert(venue)
                        }
                    }
                }
            }
            
            if Task.isCancelled { return }
            
            // Filter and Sort
            let userLocation = CLLocation(latitude: center.latitude, longitude: center.longitude)
            
            // 1. Filter Check
            let validVenues = scoredVenues.filter { item in
                let venue = item.venue
                let venueLoc = CLLocation(latitude: venue.coordinate.latitude, longitude: venue.coordinate.longitude)
                let distanceOk = venueLoc.distance(from: userLocation) <= radius
                let typeOk = venue.type.isNightlife
                return distanceOk && typeOk
            }
            
            // 2. Hybrid Sort: "Trust Apple, but Verify Distance"
            // Primary Sort Key: Rank (Index from Apple response)
            // Secondary Sort Key: Distance (Break ties between categories)
            // Penalty: If distance is very far (> 5km), add a rank penalty so closer "mediocre" places might win
            
            let sortedItemTuples = validVenues.sorted { item1, item2 in
                let v1 = item1.venue
                let v2 = item2.venue
                
                let loc1 = CLLocation(latitude: v1.coordinate.latitude, longitude: v1.coordinate.longitude)
                let loc2 = CLLocation(latitude: v2.coordinate.latitude, longitude: v2.coordinate.longitude)
                
                let dist1 = loc1.distance(from: userLocation)
                let dist2 = loc2.distance(from: userLocation)
                
                // Penalty for being very far (> 5km)
                // We add 'penalty' to the Apple Rank.
                // 1 Rank point ~= "1 position worse in list"
                let penalty1 = dist1 > 5000 ? 20 : 0
                let penalty2 = dist2 > 5000 ? 20 : 0
                
                let score1 = item1.rank + penalty1
                let score2 = item2.rank + penalty2
                
                if score1 == score2 {
                    // If Ranks are equal (e.g. Best Bar vs Best Club), choose the closer one
                    return dist1 < dist2
                } else {
                    return score1 < score2
                }
            }
            
            let finalVenues = sortedItemTuples.map { $0.venue }
            
            await MainActor.run {
                defer { self.isSearching = false }
                
                let searchLocation = userLocation
                let hasExistingVenues = !self.venues.isEmpty
                let isSameAreaAsLastSuccess: Bool = {
                    guard let lastSuccessfulLocation else { return false }
                    return lastSuccessfulLocation.distance(from: searchLocation) < AppConfiguration.Search.minimumDistanceForNewSearch
                }()
                
                guard !finalVenues.isEmpty else {
                    if hasExistingVenues && isSameAreaAsLastSuccess {
                        // Treat empty results in the same area as a transient failure.
                        // Keep current pins on screen and retry on the next location update.
                        self.shouldRetryAfterEmptyResult = true
                        return
                    } else {
                        self.shouldRetryAfterEmptyResult = false
                        self.venues = []
                        self.lastSuccessfulLocation = nil
                        return
                    }
                }
                
                self.shouldRetryAfterEmptyResult = false
                self.venues = finalVenues
                self.lastSuccessfulLocation = searchLocation
                
                // Save to cache
                let cachedVenues = finalVenues.map { venue in
                    VenueCacheManager.CachedVenue(
                        id: venue.id,
                        name: venue.name,
                        latitude: venue.coordinate.latitude,
                        longitude: venue.coordinate.longitude,
                        categoryRawValue: venue.category?.rawValue,
                        imageData: nil
                    )
                }
                
                Task {
                    do {
                        try await self.cacheManager.saveVenues(cachedVenues)
                        try await self.cacheManager.saveImages(for: finalVenues)
                    } catch {
                        // Cache save failed, but continue - this is non-critical
                    }
                }
                
                // Start fetching images
                Task {
                    await self.imageService.fetchImages(for: finalVenues) { [weak self] id, image in
                        guard let self = self else { return }
                        if let index = self.venues.firstIndex(where: { $0.id == id }) {
                            self.venues[index].image = image
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Helpers

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
