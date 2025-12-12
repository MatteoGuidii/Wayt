import Foundation
import MapKit
import UIKit

@MainActor
class VenueImageService {
    static let shared = VenueImageService()

    private var imageCache: [String: UIImage] = [:]
    private let cacheManager = VenueCacheManager.shared
    private let maxImageFetchCount = AppConfiguration.ImageService.maxImageFetchCount
    
    func fetchImages(for venues: [Venue], onUpdate: @escaping (UUID, UIImage) -> Void) async {
        // 0. Check memory cache first and identify candidates
        var venuesToProcess: [Venue] = []

        for (index, venue) in venues.enumerated() {
            let cacheKey = venue.id.uuidString

            // Check memory cache
            if let cachedImage = imageCache[cacheKey] {
                if venue.image == nil {
                    onUpdate(venue.id, cachedImage)
                }
            } else {
                // Not in memory, so we need to process it (check disk, then network)
                // Only queue if within limit
                if index < AppConfiguration.ImageService.maxImageFetchCount {
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
                let cacheKey = venue.id.uuidString
                imageCache[cacheKey] = diskImage
                onUpdate(venue.id, diskImage)
            } else {
                // Not on disk, needs network
                venuesNeedingNetwork.append(venue)
            }
        }
        
        guard !venuesNeedingNetwork.isEmpty else { return }
        
        // 2. Prioritize the first venues (Visible on screen)
        let priorityVenues = Array(venuesNeedingNetwork.prefix(AppConfiguration.ImageService.priorityCount))
        let remainingVenues = Array(venuesNeedingNetwork.dropFirst(AppConfiguration.ImageService.priorityCount))

        // Fetch priority batch immediately
        if !priorityVenues.isEmpty {
            await fetchBatch(venues: priorityVenues, onUpdate: onUpdate)
        }

        // 3. Fetch the rest in smaller, slower batches to avoid throttling
        for chunk in remainingVenues.chunked(into: AppConfiguration.ImageService.batchSize) {
            if Task.isCancelled { return }
            try? await Task.sleep(nanoseconds: AppConfiguration.ImageService.batchDelayNanoseconds)
            await fetchBatch(venues: chunk, onUpdate: onUpdate)
        }
    }
    
    private func fetchBatch(venues: [Venue], onUpdate: @escaping (UUID, UIImage) -> Void) async {
        await withTaskGroup(of: (UUID, UIImage?).self) { group in
            for venue in venues {
                group.addTask {
                    if Task.isCancelled { return (venue.id, nil) }

                    // Double check cache (though we checked before calling this, it might have been updated)
                    let cacheKey = venue.id.uuidString
                    if let cached = await MainActor.run(body: { self.imageCache[cacheKey] }) {
                        return (venue.id, cached)
                    }
                    
                    do {
                        let request = await MKLookAroundSceneRequest(mapItem: venue.mapItem)
                        if let scene = try await request.scene {
                            let options = MKLookAroundSnapshotter.Options()
                            options.size = CGSize(width: 300, height: 200)

                            let snapshotter = MKLookAroundSnapshotter(scene: scene, options: options)
                            let snapshot = try await snapshotter.snapshot
                            return (venue.id, snapshot.image)
                        }
                    } catch {
                        // Ignore errors
                    }
                    return (venue.id, nil)
                }
            }

            for await (id, image) in group {
                if let image = image {
                    self.imageCache[id.uuidString] = image
                    onUpdate(id, image)
                    
                    // Save image to disk cache
                    Task {
                        do {
                            try await self.cacheManager.saveImage(image, for: id)
                        } catch {
                            // Cache save failed, but continue - this is non-critical
                        }
                    }
                }
            }
        }
    }
}
