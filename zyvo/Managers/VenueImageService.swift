import Foundation
import MapKit
import UIKit

@MainActor
class VenueImageService {
    static let shared = VenueImageService()
    
    private var imageCache: [String: UIImage] = [:]
    private let cacheManager = VenueCacheManager.shared
    private let maxImageFetchCount = 10
    
    func fetchImages(for venues: [Venue], onUpdate: @escaping (UUID, UIImage) -> Void) async {
        // 0. Check memory cache first and identify candidates
        var venuesToProcess: [Venue] = []
        
        for (index, venue) in venues.enumerated() {
            let cacheKey = "\(venue.name)_\(venue.coordinate.latitude)_\(venue.coordinate.longitude)"
            
            // Check memory cache
            if let cachedImage = imageCache[cacheKey] {
                if venue.image == nil {
                    onUpdate(venue.id, cachedImage)
                }
            } else {
                // Not in memory, so we need to process it (check disk, then network)
                // Only queue if within limit
                if index < maxImageFetchCount {
                    venuesToProcess.append(venue)
                }
            }
        }
        
        guard !venuesToProcess.isEmpty else { return }
        
        // 1. Check disk cache for these venues
        var venuesNeedingNetwork: [Venue] = []
        
        for venue in venuesToProcess {
            if Task.isCancelled { return }
            
            if let diskImage = await cacheManager.loadImage(for: venue.id) {
                // Found on disk, update UI and memory cache
                let cacheKey = "\(venue.name)_\(venue.coordinate.latitude)_\(venue.coordinate.longitude)"
                imageCache[cacheKey] = diskImage
                onUpdate(venue.id, diskImage)
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
            await fetchBatch(venues: priorityVenues, onUpdate: onUpdate)
        }
        
        // 3. Fetch the rest in smaller, slower batches to avoid throttling
        let batchSize = 4
        
        for chunk in remainingVenues.chunked(into: batchSize) {
            if Task.isCancelled { return }
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2.0 seconds
            await fetchBatch(venues: chunk, onUpdate: onUpdate)
        }
    }
    
    private func fetchBatch(venues: [Venue], onUpdate: @escaping (UUID, UIImage) -> Void) async {
        await withTaskGroup(of: (UUID, UIImage?, String).self) { group in
            let items: [(id: UUID, mapItem: MKMapItem, cacheKey: String)] = venues.map { venue in
                (
                    id: venue.id,
                    mapItem: venue.mapItem,
                    cacheKey: "\(venue.name)_\(venue.coordinate.latitude)_\(venue.coordinate.longitude)"
                )
            }
            
            for item in items {
                group.addTask {
                    if Task.isCancelled { return (item.id, nil, item.cacheKey) }
                    
                    // Double check cache (though we checked before calling this, it might have been updated)
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
            
            for await (id, image, key) in group {
                if let image = image {
                    self.imageCache[key] = image
                    onUpdate(id, image)
                    
                    // Save image to disk cache
                    Task {
                        await self.cacheManager.saveImage(image, for: id)
                    }
                }
            }
        }
    }
}
