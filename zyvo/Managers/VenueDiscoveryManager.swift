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
            var allVenues: [Venue] = []
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
                    for venue in venues {
                        // Use Venue's Hashable implementation for proper deduplication
                        if !seenVenues.contains(venue) {
                            allVenues.append(venue)
                            seenVenues.insert(venue)
                        }
                    }
                }
            }
            
            if Task.isCancelled { return }
            
            // Filter and Sort
            let userLocation = CLLocation(latitude: center.latitude, longitude: center.longitude)
            
            let filteredVenues = allVenues.filter { venue in
                let venueLoc = CLLocation(latitude: venue.coordinate.latitude, longitude: venue.coordinate.longitude)
                let distanceOk = venueLoc.distance(from: userLocation) <= radius
                let typeOk = venue.type.isNightlife
                return distanceOk && typeOk
            }
            
            // Sort by distance
            let sortedVenues = filteredVenues.sorted { v1, v2 in
                let loc1 = CLLocation(latitude: v1.coordinate.latitude, longitude: v1.coordinate.longitude)
                let loc2 = CLLocation(latitude: v2.coordinate.latitude, longitude: v2.coordinate.longitude)
                return loc1.distance(from: userLocation) < loc2.distance(from: userLocation)
            }
            
            await MainActor.run {
                self.venues = sortedVenues
                self.isSearching = false
                
                // Save to cache
                let cachedVenues = sortedVenues.map { venue in
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
                        try await self.cacheManager.saveImages(for: sortedVenues)
                    } catch {
                        // Cache save failed, but continue - this is non-critical
                    }
                }
                
                // Start fetching images
                Task {
                    await self.imageService.fetchImages(for: sortedVenues) { [weak self] id, image in
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

