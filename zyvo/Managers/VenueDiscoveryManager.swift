import Foundation
import MapKit
import Combine
import UIKit

@MainActor
class VenueDiscoveryManager: ObservableObject {
    @Published var venues: [Venue] = []
    @Published var isSearching = false
    
    private var lastSearchLocation: CLLocation?
    private let searchRadius: CLLocationDistance = 5000 // 5km
    
    private let searchService = VenueSearchService()
    

    
    // MARK: - Public API
    
    /// Triggers a search around the user's location if they have moved significantly
    func updateUserLocation(_ location: CLLocation) {
        // Only search if we haven't searched yet, or if we've moved significantly (e.g. 500m)
        guard let lastLocation = lastSearchLocation else {
            performSearch(near: location.coordinate)
            lastSearchLocation = location
            return
        }
        
        if location.distance(from: lastLocation) > 500 {
            performSearch(near: location.coordinate)
            lastSearchLocation = location
        }
    }
    
    /// Performs a search with a specific query (e.g. from search bar)
    func search(text: String) {
        guard let location = lastSearchLocation else { return }
        performSearch(near: location.coordinate, searchText: text)
    }
    
    private func performSearch(near center: CLLocationCoordinate2D, searchText: String = "") {
        guard !isSearching else { return }
        isSearching = true
        
        let searchRegion = MKCoordinateRegion(
            center: center,
            latitudinalMeters: searchRadius * 2,
            longitudinalMeters: searchRadius * 2
        )
        
        Task {
            let queries = searchService.getQueries(for: searchText)
            var allVenues: [Venue] = []
            var seenKeys: Set<String> = []
            
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
                        // Create a unique key based on name and location to prevent duplicates
                        // distinct from the random UUID
                        let key = "\(venue.name)_\(venue.coordinate.latitude)_\(venue.coordinate.longitude)"
                        
                        if !seenKeys.contains(key) {
                            allVenues.append(venue)
                            seenKeys.insert(key)
                        }
                    }
                }
            }
            
            // Filter and Sort
            let userLocation = CLLocation(latitude: center.latitude, longitude: center.longitude)
            
            let filteredVenues = allVenues.filter { venue in
                let venueLoc = CLLocation(latitude: venue.coordinate.latitude, longitude: venue.coordinate.longitude)
                let distanceOk = venueLoc.distance(from: userLocation) <= self.searchRadius
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
                
                // Start fetching images
                Task {
                    await self.fetchImages(for: sortedVenues)
                }
            }
        }
    }
    
    // MARK: - Image Fetching (Look Around Snapshots)
    
    private var imageCache: [String: UIImage] = [:]
    private let maxImageFetchCount = 10 // Reduced from 20 to prevent throttling
    
    private func fetchImages(for venues: [Venue]) async {
        // 0. Check cache first and update immediately
        var venuesToFetch: [Venue] = []
        
        await MainActor.run {
            var currentVenues = self.venues
            var hasChanges = false
            
            for (index, venue) in currentVenues.enumerated() {
                let cacheKey = "\(venue.name)_\(venue.coordinate.latitude)_\(venue.coordinate.longitude)"
                if let cachedImage = imageCache[cacheKey] {
                    currentVenues[index].image = cachedImage
                    hasChanges = true
                } else {
                    // Only queue for fetching if within the limit
                    if index < maxImageFetchCount {
                        venuesToFetch.append(venue)
                    }
                }
            }
            
            if hasChanges {
                self.venues = currentVenues
            }
        }
        
        guard !venuesToFetch.isEmpty else { return }
        
        // 1. Prioritize the first 6 venues (Visible on screen)
        let priorityCount = 6
        let priorityVenues = Array(venuesToFetch.prefix(priorityCount))
        let remainingVenues = Array(venuesToFetch.dropFirst(priorityCount))
        
        // Fetch priority batch immediately
        if !priorityVenues.isEmpty {
            await fetchBatch(venues: priorityVenues)
        }
        
        // 2. Fetch the rest in smaller, slower batches to avoid throttling
        // Apple limits are tight (approx 50 requests per minute)
        let batchSize = 4
        
        for chunk in remainingVenues.chunked(into: batchSize) {
            // Significant delay to stay under rate limits
            // 2.0 seconds delay between batches
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2.0 seconds
            
            await fetchBatch(venues: chunk)
        }
    }
    
    private func fetchBatch(venues: [Venue]) async {
        await withTaskGroup(of: (UUID, UIImage?, String).self) { group in
            // Capture MainActor-isolated properties before hopping off the main actor
            let items: [(id: UUID, mapItem: MKMapItem, cacheKey: String)] = await MainActor.run {
                venues.map { venue in
                    (
                        id: venue.id,
                        mapItem: venue.mapItem,
                        cacheKey: "\(venue.name)_\(venue.coordinate.latitude)_\(venue.coordinate.longitude)"
                    )
                }
            }
            
            for item in items {
                group.addTask {
                    // Double check cache before request (in case another batch got it)
                    if let cached = await MainActor.run(body: { self.imageCache[item.cacheKey] }) {
                        return (item.id, cached, item.cacheKey)
                    }
                    
                    do {
                        let request = MKLookAroundSceneRequest(mapItem: item.mapItem)
                        if let scene = try await request.scene {
                            let options = MKLookAroundSnapshotter.Options()
                            options.size = CGSize(width: 300, height: 200)
                            
                            let snapshotter = MKLookAroundSnapshotter(scene: scene, options: options)
                            let snapshot = try await snapshotter.snapshot
                            return (item.id, snapshot.image, item.cacheKey)
                        }
                    } catch {
                        // Ignore errors
                    }
                    return (item.id, nil, item.cacheKey)
                }
            }
            
            // Collect results for this batch
            var updates: [(UUID, UIImage, String)] = []
            for await (id, image, key) in group {
                if let image = image {
                    updates.append((id, image, key))
                }
            }
            
            // Update the main array and cache
            if !updates.isEmpty {
                await MainActor.run {
                    var currentVenues = self.venues
                    var hasChanges = false
                    
                    for (id, image, key) in updates {
                        self.imageCache[key] = image
                        
                        if let index = currentVenues.firstIndex(where: { $0.id == id }) {
                            currentVenues[index].image = image
                            hasChanges = true
                        }
                    }
                    
                    if hasChanges {
                        self.venues = currentVenues
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
