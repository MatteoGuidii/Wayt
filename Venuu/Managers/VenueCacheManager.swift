import Foundation
import UIKit
import CoreLocation
import MapKit

actor VenueCacheManager {
    static let shared = VenueCacheManager()

    enum CacheError: Error {
        case imageCompressionFailed
        case fileWriteFailed
        case fileReadFailed
    }

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
        let data = try JSONEncoder().encode(venues)
        try data.write(to: venuesFile, options: .atomic)
    }
    
    func saveImages(for venues: [Venue]) async throws {
        for venue in venues {
            if let image = venue.image {
                try await saveImage(image, for: venue.id)
            }
        }
    }
    
    func loadVenues() async -> [Venue] {
        guard let data = try? Data(contentsOf: venuesFile),
              let cachedVenues = try? JSONDecoder().decode([CachedVenue].self, from: data) else {
            return []
        }
        
        var venues: [Venue] = []
        for cached in cachedVenues {
            // Reconstruct a basic MKMapItem using modern API
            _ = CLLocationCoordinate2D(latitude: cached.latitude, longitude: cached.longitude)
            let location = CLLocation(latitude: cached.latitude, longitude: cached.longitude)

            // Create MKMapItem using modern iOS 26+ API
            let mapItem = MKMapItem(location: location, address: nil)

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
            throw CacheError.imageCompressionFailed
        }
        try data.write(to: fileURL, options: .atomic)
    }
    
    func loadImage(for id: UUID) async -> UIImage? {
        let fileURL = imagesDirectory.appendingPathComponent("\(id.uuidString).jpg")
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        return UIImage(data: data)
    }
    
    func clearCache() {
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
    }
}
