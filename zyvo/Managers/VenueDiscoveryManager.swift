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
        let searchRegion = MKCoordinateRegion(
            center: center,
            latitudinalMeters: searchRadius * 2,
            longitudinalMeters: searchRadius * 2
        )
        
        // Queries to cover: bars, pubs, restaurants, cafes, clubs
        let queries = ["Food", "Nightlife"]
        
        let group = DispatchGroup()
        var foundVenues: [Venue] = []
        
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
                    foundVenues.append(contentsOf: venues)
                }
            }
        }
        
        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            
            // Deduplicate results
            let uniqueVenues = Array(Set(foundVenues))
            self.venues = uniqueVenues
            self.isSearching = false
            
            // Start fetching images for venues
            Task {
                await self.fetchImages(for: uniqueVenues)
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
