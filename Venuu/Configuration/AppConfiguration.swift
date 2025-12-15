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
        /// Debounce delay for location-based searches in nanoseconds (0.15 seconds)
        static let debounceDelayNanoseconds: UInt64 = 150_000_000

        /// Minimum distance moved to trigger new search (meters)
        static let minimumDistanceForNewSearch: CLLocationDistance = 200

        /// Minimum radius change ratio to trigger new search (20%)
        static let minimumRadiusChangeRatio: Double = 0.2

        /// Default search radius (meters)
        static let defaultSearchRadius: CLLocationDistance = 5000

        /// Maximum number of venues we keep in memory and cache after each search
        static let maxResultCount = 60
    }

    // MARK: - Map Configuration

    enum Map {
        /// Minimum radius in meters
        static let minimumRadius: CLLocationDistance = 500

        /// Maximum radius in meters
        static let maximumRadius: CLLocationDistance = 50_000
    }

    // MARK: - Location Configuration

    enum Location {
        /// Balanced accuracy to avoid battery drain from navigation-grade tracking
        static let desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyNearestTenMeters

        /// Minimum distance change (meters) before requesting another location update
        static let distanceFilter: CLLocationDistance = 25

        /// Distance change used when we temporarily crank accuracy up for foreground tracking
        static let highAccuracyDistanceFilter: CLLocationDistance = 5

        /// Distance (meters) the user must move before we refresh the displayed city label
        static let cityRefreshDistance: CLLocationDistance = 750

        /// Minimum time (seconds) between reverse-geo lookups to cut network usage
        static let cityRefreshInterval: TimeInterval = 120

        /// Minimum time (seconds) we wait before retrying a failed reverse-geo lookup
        static let cityRefreshRetryInterval: TimeInterval = 15

        /// Heading filter so we only get callbacks when orientation changes meaningfully
        static let headingFilterDegrees: CLLocationDegrees = 10
    }

    // MARK: - Venue Scoring Configuration

    enum VenueScoring {
        /// Minimum confidence score (0-100) for a venue to be shown as nightlife-relevant
        /// 70 = Show restaurants with strong nightlife signals (keywords, location, hybrid category)
        /// 50 = More permissive, includes generic restaurants in nightlife areas
        /// 90 = Very strict, only explicit nightlife venues
        static let minimumNightlifeScore = 70

        /// Distance (meters) to search for nearby nightlife venues when calculating proximity score
        static let proximitySearchRadius: CLLocationDistance = 200

        /// Maximum proximity bonus points that can be awarded based on nearby venues
        static let maxProximityBonus = 20

        /// Points awarded per nearby nightlife venue (capped at maxProximityBonus)
        static let pointsPerNearbyVenue = 5
    }
}
