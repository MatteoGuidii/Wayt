import Foundation
import UIKit
import CoreLocation
import MapKit

actor VenueCacheManager {
    static let shared = VenueCacheManager()
    
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
    
    func saveVenues(_ venues: [CachedVenue]) {
        do {
            let data = try JSONEncoder().encode(venues)
            try data.write(to: venuesFile)
        } catch {
            print("Failed to save venues: \(error)")
        }
    }
    
    func saveImages(for venues: [Venue]) {
        for venue in venues {
            if let image = venue.image {
                saveImage(image, for: venue.id)
            }
        }
    }
    
    func loadVenues() -> [Venue] {
        guard let data = try? Data(contentsOf: venuesFile),
              let cachedVenues = try? JSONDecoder().decode([CachedVenue].self, from: data) else {
            return []
        }
        
        return cachedVenues.map { cached in
            // Reconstruct Venue
            // Since we can't fully reconstruct MKMapItem easily without a network lookup,
            // we will create a "lite" version or use a placeholder MKMapItem.
            // For this implementation, we'll create a basic MKMapItem with a placemark.
            
            let coordinate = CLLocationCoordinate2D(latitude: cached.latitude, longitude: cached.longitude)
            let placemark = MKPlacemark(coordinate: coordinate)
            let mapItem = MKMapItem(placemark: placemark)
            mapItem.name = cached.name
            if let catRaw = cached.categoryRawValue {
                mapItem.pointOfInterestCategory = MKPointOfInterestCategory(rawValue: catRaw)
            }
            
            var venue = Venue(mapItem: mapItem)
            // Load image
            if let image = loadImage(for: cached.id) {
                venue.image = image
            }
            
            return venue
        }
    }
    
    // MARK: - Images
    
    func saveImage(_ image: UIImage, for id: UUID) {
        let fileURL = imagesDirectory.appendingPathComponent("\(id.uuidString).jpg")
        if let data = image.jpegData(compressionQuality: 0.7) {
            try? data.write(to: fileURL)
        }
    }
    
    func loadImage(for id: UUID) -> UIImage? {
        let fileURL = imagesDirectory.appendingPathComponent("\(id.uuidString).jpg")
        if let data = try? Data(contentsOf: fileURL) {
            return UIImage(data: data)
        }
        return nil
    }
    
    func clearCache() {
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
    }
}
