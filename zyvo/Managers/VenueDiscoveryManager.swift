import Foundation
import MapKit
import Combine
import UIKit

@MainActor
class VenueDiscoveryManager: ObservableObject {
    @Published var venues: [Venue] = []
    @Published var isSearching = false
    
    private var lastSearchLocation: CLLocation?
    private var lastSearchRadius: CLLocationDistance = 5000 // Default 5km
    
    private let searchService = VenueSearchService()
    private let cacheManager = VenueCacheManager.shared
    
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
    func updateUserLocation(_ location: CLLocation, radius: CLLocationDistance = 5000) {
        // Only search if we haven't searched yet, or if we've moved significantly (e.g. 500m)
        // OR if the radius has changed significantly (e.g. by 20%)
        guard let lastLocation = lastSearchLocation else {
            performSearch(near: location.coordinate, radius: radius)
            lastSearchLocation = location
            lastSearchRadius = radius
            return
        }
        
        let distance = location.distance(from: lastLocation)
        let radiusRatio = abs(radius - lastSearchRadius) / lastSearchRadius
        
        if distance > 500 || radiusRatio > 0.2 {
            performSearch(near: location.coordinate, radius: radius)
            lastSearchLocation = location
            lastSearchRadius = radius
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
            // Debounce for map interactions (optional, but good for rapid zooming)
            if searchText.isEmpty {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s debounce for location updates
            }
            
            if Task.isCancelled { return }
            
            let searchRegion = MKCoordinateRegion(
                center: center,
                latitudinalMeters: radius * 2,
                longitudinalMeters: radius * 2
            )
            
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
                        let key = "\(venue.name)_\(venue.coordinate.latitude)_\(venue.coordinate.longitude)"
                        
                        if !seenKeys.contains(key) {
                            allVenues.append(venue)
                            seenKeys.insert(key)
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
                    await self.cacheManager.saveVenues(cachedVenues)
                    await self.cacheManager.saveImages(for: sortedVenues)
                }
                
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
        // 0. Check memory cache first and identify candidates
        var venuesToProcess: [Venue] = []
        
        await MainActor.run {
            var currentVenues = self.venues
            var hasChanges = false
            
            for (index, venue) in currentVenues.enumerated() {
                let cacheKey = "\(venue.name)_\(venue.coordinate.latitude)_\(venue.coordinate.longitude)"
                
                // Check memory cache
                if let cachedImage = imageCache[cacheKey] {
                    if currentVenues[index].image == nil {
                        currentVenues[index].image = cachedImage
                        hasChanges = true
                    }
                } else {
                    // Not in memory, so we need to process it (check disk, then network)
                    // Only queue if within limit
                    if index < maxImageFetchCount {
                        venuesToProcess.append(venue)
                    }
                }
            }
            
            if hasChanges {
                self.venues = currentVenues
            }
        }
        
        guard !venuesToProcess.isEmpty else { return }
        
        // 1. Check disk cache for these venues
        var venuesNeedingNetwork: [Venue] = []
        
        for venue in venuesToProcess {
            if Task.isCancelled { return }
            
            if let diskImage = await self.cacheManager.loadImage(for: venue.id) {
                // Found on disk, update UI and memory cache
                let cacheKey = "\(venue.name)_\(venue.coordinate.latitude)_\(venue.coordinate.longitude)"
                await MainActor.run {
                    self.imageCache[cacheKey] = diskImage
                    if let index = self.venues.firstIndex(where: { $0.id == venue.id }) {
                        self.venues[index].image = diskImage
                    }
                }
            } else {
                // Not on disk, needs network
                venuesNeedingNetwork.append(venue)
            }
        }
        
        guard !venuesNeedingNetwork.isEmpty else { return }
        
        // 2. Prioritize the first 6 venues (Visible on screen)
        let priorityCount = 6
        let priorityVenues = Array(venuesNeedingNetwork.prefix(priorityCount))
        let remainingVenues = Array(venuesNeedingNetwork.dropFirst(priorityCount))
        
        // Fetch priority batch immediately
        if !priorityVenues.isEmpty {
            await fetchBatch(venues: priorityVenues)
        }
        
        // 3. Fetch the rest in smaller, slower batches to avoid throttling
        let batchSize = 4
        
        for chunk in remainingVenues.chunked(into: batchSize) {
            if Task.isCancelled { return }
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2.0 seconds
            await fetchBatch(venues: chunk)
        }
    }
    
    private func fetchBatch(venues: [Venue]) async {
        await withTaskGroup(of: (UUID, UIImage?, String).self) { group in
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
                    if Task.isCancelled { return (item.id, nil, item.cacheKey) }
                    
                    // Double check cache
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
            
            var updates: [(UUID, UIImage, String)] = []
            for await (id, image, key) in group {
                if let image = image {
                    updates.append((id, image, key))
                }
            }
            
            if !updates.isEmpty {
                await MainActor.run {
                    var currentVenues = self.venues
                    var hasChanges = false
                    
                    for (id, image, key) in updates {
                        self.imageCache[key] = image
                        
                        if let index = currentVenues.firstIndex(where: { $0.id == id }) {
                            currentVenues[index].image = image
                            hasChanges = true
                            
                            // Save image to disk cache
                            Task {
                                await self.cacheManager.saveImage(image, for: id)
                            }
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

