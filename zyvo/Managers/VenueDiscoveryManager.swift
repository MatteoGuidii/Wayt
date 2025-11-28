import Foundation
import MapKit
import Combine

class VenueDiscoveryManager: ObservableObject {
    @Published var venues: [Venue] = []
    @Published var isSearching = false
    
    private var lastSearchLocation: CLLocation?
    private let searchRadius: CLLocationDistance = 5000 // 5km
    
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
    
    private func performSearch(near center: CLLocationCoordinate2D) {
        guard !isSearching else { return }
        isSearching = true
        
        // Create a region with a 5km radius (10km diameter)
        // We still use the region for the initial search to get candidates
        let searchRegion = MKCoordinateRegion(
            center: center,
            latitudinalMeters: searchRadius * 2,
            longitudinalMeters: searchRadius * 2
        )
        
        // Refined queries for "discovery vibes"
        let queries = [
            "Cocktail Bar", "Wine Bar", "Pub", "Gastropub", 
            "Night Club", "Live Music", "Tapas", "Bistro",
            "Speakeasy", "Rooftop Bar", "Jazz Club"
        ]
        
        let group = DispatchGroup()
        
        // Store results grouped by category for balanced selection
        var resultsByCategory: [String: [Venue]] = [:]
        let lock = NSLock()
        
        for query in queries {
            group.enter()
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.region = searchRegion
            
            let search = MKLocalSearch(request: request)
            search.start { response, error in
                defer { group.leave() }
                
                if let response = response {
                    let venues = response.mapItems.map { Venue(mapItem: $0) }
                    lock.lock()
                    resultsByCategory[query] = venues
                    lock.unlock()
                }
            }
        }
        
        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            
            var curatedVenues: [Venue] = []
            var seenVenueIds: Set<Venue> = []
            let userLocation = CLLocation(latitude: center.latitude, longitude: center.longitude)
            
            // Balanced Category Mix: Round-robin selection
            // We loop through categories and pick one from each until we hit the limit or run out
            var activeCategories = queries
            var categoryIndices = queries.reduce(into: [String: Int]()) { $0[$1] = 0 }
            
            while curatedVenues.count < 50 && !activeCategories.isEmpty {
                var nextRoundCategories: [String] = []
                
                for category in activeCategories {
                    guard let venues = resultsByCategory[category],
                          let currentIndex = categoryIndices[category],
                          currentIndex < venues.count else {
                        // No more venues in this category
                        continue
                    }
                    
                    // Try to find the next valid venue in this category
                    var searchIndex = currentIndex
                    
                    while searchIndex < venues.count {
                        let candidate = venues[searchIndex]
                        searchIndex += 1
                        
                        // Check 1: Deduplication
                        if seenVenueIds.contains(candidate) {
                            continue
                        }
                        
                        // Check 2: Strict 5km Distance Filter
                        let venueLocation = CLLocation(latitude: candidate.coordinate.latitude, longitude: candidate.coordinate.longitude)
                        if venueLocation.distance(from: userLocation) > self.searchRadius {
                            continue
                        }
                        
                        // Check 3: Global Category Filter (Allowlist)
                        // We only allow specific social categories. This works globally unlike keyword blacklists.
                        let allowedCategories: Set<MKPointOfInterestCategory> = [
                            .restaurant,
                            .nightlife,
                            .cafe,
                            .brewery,
                            .winery,
                            .distillery,
                            .theater,
                            .musicVenue
                        ]
                        
                        guard let venueCategory = candidate.category, allowedCategories.contains(venueCategory) else {
                            continue
                        }
                        
                        // Found a valid one!
                        curatedVenues.append(candidate)
                        seenVenueIds.insert(candidate)
                        categoryIndices[category] = searchIndex
                        nextRoundCategories.append(category) // Keep category active
                        break
                    }
                    
                    // If we exhausted the category without finding a valid one, it won't be in nextRoundCategories
                }
                
                activeCategories = nextRoundCategories
            }
            
            self.venues = curatedVenues
            self.isSearching = false
            
            // Start fetching images for venues
            Task {
                await self.fetchImages(for: curatedVenues)
            }
        }
    }
    
    private func fetchImages(for venues: [Venue]) async {
        for venue in venues {
            // Check if we already have an image (optimization)
            // For now, we just try to fetch for all new ones
            do {
                let request = MKLookAroundSceneRequest(mapItem: venue.mapItem)
                if let scene = try await request.scene {
                    let snapshotter = MKLookAroundSnapshotter(scene: scene, options: .init())
                    let snapshot = try await snapshotter.snapshot
                    
                    await MainActor.run {
                        if let index = self.venues.firstIndex(of: venue) {
                            self.venues[index].image = snapshot.image
                        }
                    }
                }
            } catch {
                // Ignore errors, just no image
                continue
            }
        }
    }
}
