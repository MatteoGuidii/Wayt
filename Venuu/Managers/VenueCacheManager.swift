import Foundation
import UIKit
import CoreLocation
import MapKit
import os.log

actor VenueCacheManager {
    static let shared = VenueCacheManager()

    enum CacheError: Error {
        case imageCompressionFailed
        case fileWriteFailed
        case fileReadFailed
        case encodingFailed
        case decodingFailed
    }

    private let logger = Logger(subsystem: "com.venuu.app", category: "VenueCacheManager")

    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private let venuesFile: URL
    private let imagesDirectory: URL // Subdirectory for images
    
    init() {
        // Setup directories
        let paths = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        cacheDirectory = paths[0].appendingPathComponent("VenueCache")
        venuesFile = cacheDirectory.appendingPathComponent("venues.json")
        imagesDirectory = cacheDirectory.appendingPathComponent("Images")
        
        // Create directories if needed
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
    }
    
    // MARK: - Venues
    
    struct CachedVenue: Codable {
        let id: UUID
        let name: String
        let latitude: Double
        let longitude: Double
        let categoryRawValue: String?
        let imageData: Data? // Small thumbnail data if needed, or just rely on disk cache
        // Note: We can't easily cache MKMapItem, so we reconstruct what we can
        // or we just cache the essential data for display.
        // For a full app, we might want to store more metadata.
    }
    
    func saveVenues(_ venues: [CachedVenue]) async throws {
        do {
            let data = try JSONEncoder().encode(venues)
            try data.write(to: venuesFile, options: .atomic)
            logger.info("Successfully saved \(venues.count) venues to cache")
        } catch let error as EncodingError {
            logger.error("Failed to encode venues: \(error.localizedDescription)")
            throw CacheError.encodingFailed
        } catch {
            logger.error("Failed to write venues to disk: \(error.localizedDescription)")
            throw CacheError.fileWriteFailed
        }
    }
    
    func saveImages(for venues: [Venue]) async throws {
        var savedCount = 0
        for venue in venues {
            if let image = venue.image {
                do {
                    try await saveImage(image, for: venue.id)
                    savedCount += 1
                } catch {
                    logger.warning("Failed to save image for venue \(venue.id): \(error.localizedDescription)")
                }
            }
        }
        logger.info("Successfully saved \(savedCount) images out of \(venues.count) venues")
    }
    
    func loadVenues() async -> [Venue] {
        guard let data = try? Data(contentsOf: venuesFile) else {
            logger.info("No cached venues file found")
            return []
        }

        guard let cachedVenues = try? JSONDecoder().decode([CachedVenue].self, from: data) else {
            logger.error("Failed to decode cached venues")
            return []
        }

        logger.info("Loading \(cachedVenues.count) cached venues")
        
        var venues: [Venue] = []
        for cached in cachedVenues {
            // Reconstruct a basic MKMapItem using iOS 18 compatible API
            let coordinate = CLLocationCoordinate2D(latitude: cached.latitude, longitude: cached.longitude)

            // Create MKMapItem using MKPlacemark (iOS 18 compatible)
            let placemark = MKPlacemark(coordinate: coordinate)
            let mapItem = MKMapItem(placemark: placemark)

            mapItem.name = cached.name
            if let catRaw = cached.categoryRawValue {
                mapItem.pointOfInterestCategory = MKPointOfInterestCategory(rawValue: catRaw)
            }

            let image = await loadImage(for: cached.id)
            let venue: Venue = await MainActor.run {
                var v = Venue(mapItem: mapItem)
                if let image {
                    v.image = image
                }
                return v
            }
            venues.append(venue)
        }
        return venues
    }
    
    // MARK: - Images
    
    func saveImage(_ image: UIImage, for id: UUID) async throws {
        let fileURL = imagesDirectory.appendingPathComponent("\(id.uuidString).jpg")
        guard let data = await image.jpegData(compressionQuality: AppConfiguration.ImageService.compressionQuality) else {
            logger.error("Failed to compress image for venue \(id)")
            throw CacheError.imageCompressionFailed
        }

        do {
            try data.write(to: fileURL, options: .atomic)
            logger.debug("Saved image for venue \(id)")
        } catch {
            logger.error("Failed to write image for venue \(id): \(error.localizedDescription)")
            throw CacheError.fileWriteFailed
        }
    }
    
    func loadImage(for id: UUID) async -> UIImage? {
        let fileURL = imagesDirectory.appendingPathComponent("\(id.uuidString).jpg")
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        return UIImage(data: data)
    }
    
    func clearCache() {
        do {
            try fileManager.removeItem(at: cacheDirectory)
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
            logger.info("Successfully cleared venue cache")
        } catch {
            logger.error("Failed to clear cache: \(error.localizedDescription)")
        }
    }
}
