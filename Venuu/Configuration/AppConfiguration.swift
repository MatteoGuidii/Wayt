import Foundation
import CoreLocation

/// Central configuration for app-wide constants
enum AppConfiguration {

    // MARK: - Image Service Configuration

    enum ImageService {
        /// Maximum number of images to fetch per search
        static let maxImageFetchCount = 10

        /// Number of priority images to fetch first (visible on screen)
        static let priorityCount = 6

        /// Batch size for throttled image fetching
        static let batchSize = 4

        /// Delay between batches in nanoseconds (2 seconds)
        static let batchDelayNanoseconds: UInt64 = 2_000_000_000

        /// JPEG compression quality for cached images (0.0 - 1.0)
        static let compressionQuality: CGFloat = 0.7
    }

    // MARK: - Search Configuration

    enum Search {
        /// Debounce delay for location-based searches in nanoseconds (0.5 seconds)
        static let debounceDelayNanoseconds: UInt64 = 500_000_000

        /// Minimum distance moved to trigger new search (meters)
        static let minimumDistanceForNewSearch: CLLocationDistance = 500

        /// Minimum radius change ratio to trigger new search (20%)
        static let minimumRadiusChangeRatio: Double = 0.2

        /// Default search radius (meters)
        static let defaultSearchRadius: CLLocationDistance = 5000
    }

    // MARK: - Map Configuration

    enum Map {
        /// Minimum radius in meters
        static let minimumRadius: CLLocationDistance = 500

        /// Maximum radius in meters
        static let maximumRadius: CLLocationDistance = 50_000
    }
}
