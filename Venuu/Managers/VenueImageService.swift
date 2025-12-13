import Foundation
import MapKit
import UIKit

actor VenueImageService {
    static let shared = VenueImageService()

    private let cacheManager = VenueCacheManager.shared
    private let maxImageFetchCount = AppConfiguration.ImageService.maxImageFetchCount
    private let memoryCache = NSCache<NSString, UIImage>()

    private init() {
        memoryCache.countLimit = 60
        memoryCache.totalCostLimit = 32 * 1024 * 1024 // ~32MB
    }

    func fetchImages(
        for venues: [Venue],
        onUpdate: @MainActor @escaping (UUID, UIImage) -> Void
    ) async {
        var venuesToProcess: [Venue] = []

        for (index, venue) in venues.enumerated() {
            let key = cacheKey(for: venue.id)

            if let cachedImage = memoryCache.object(forKey: key) {
                if venue.image == nil {
                    await onUpdate(venue.id, cachedImage)
                }
                continue
            }

            if index < maxImageFetchCount {
                venuesToProcess.append(venue)
            }
        }

        guard !venuesToProcess.isEmpty else { return }

        var venuesNeedingNetwork: [Venue] = []

        for venue in venuesToProcess {
            if Task.isCancelled { return }

            if let diskImage = await cacheManager.loadImage(for: venue.id) {
                memoryCache.setObject(diskImage, forKey: cacheKey(for: venue.id), cost: imageCost(for: diskImage))
                await onUpdate(venue.id, diskImage)
            } else {
                venuesNeedingNetwork.append(venue)
            }
        }

        guard !venuesNeedingNetwork.isEmpty else { return }

        let priorityVenues = Array(venuesNeedingNetwork.prefix(AppConfiguration.ImageService.priorityCount))
        let remainingVenues = Array(venuesNeedingNetwork.dropFirst(AppConfiguration.ImageService.priorityCount))

        if !priorityVenues.isEmpty {
            await fetchSequentially(venues: priorityVenues, onUpdate: onUpdate)
        }

        let batchSize = AppConfiguration.ImageService.batchSize
        for i in stride(from: 0, to: remainingVenues.count, by: batchSize) {
            if Task.isCancelled { return }
            try? await Task.sleep(nanoseconds: AppConfiguration.ImageService.batchDelayNanoseconds)
            let endIndex = Swift.min(i + batchSize, remainingVenues.count)
            let chunk = Array(remainingVenues[i..<endIndex])
            await fetchSequentially(venues: chunk, onUpdate: onUpdate)
        }
    }

    private func fetchSequentially(
        venues: [Venue],
        onUpdate: @MainActor @escaping (UUID, UIImage) -> Void
    ) async {
        for venue in venues {
            if Task.isCancelled { return }

            guard let image = await loadSnapshot(for: venue) else {
                continue
            }

            memoryCache.setObject(image, forKey: cacheKey(for: venue.id), cost: imageCost(for: image))

            await onUpdate(venue.id, image)

            do {
                try await cacheManager.saveImage(image, for: venue.id)
            } catch {
                // Cache save failures are non-fatal
            }
        }
    }

    private func loadSnapshot(for venue: Venue) async -> UIImage? {
        do {
            let request = MKLookAroundSceneRequest(mapItem: venue.mapItem)
            if let scene = try await request.scene {
                let options = MKLookAroundSnapshotter.Options()
                options.size = CGSize(width: 300, height: 200)

                let snapshotter = MKLookAroundSnapshotter(scene: scene, options: options)
                let snapshot = try await snapshotter.snapshot
                return snapshot.image
            }
        } catch {
            // Ignore network or Look Around coverage failures
        }
        return nil
    }

    private func cacheKey(for id: UUID) -> NSString {
        NSString(string: id.uuidString)
    }

    private func imageCost(for image: UIImage) -> Int {
        let scale = image.scale == 0 ? 1 : image.scale
        let pixels = image.size.width * image.size.height * scale * scale
        return Int(pixels)
    }
}
