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

        /// Maximum number of venues we keep in memory and cache after each search
        /// Increased to 200 to ensure comprehensive coverage in dense urban areas
        /// Map clustering handles display of large venue counts efficiently
        static let maxResultCount = 200

        /// Grid size for multi-cell search (NxN grid)
        /// 3x3 = 9 searches, providing better coverage in dense areas
        static let searchGridSize = 3
    }

    // MARK: - Venue Scoring Configuration

    enum VenueScoring {
        /// Number of venues in a result set considered "high density"
        /// Use a higher threshold in dense urban cores so we can be more selective
        static let highDensityThreshold: Int = 80

        /// Number of venues in a result set considered "low density"
        /// Be more inclusive when there are few candidates
        static let lowDensityThreshold: Int = 20

        /// Minimum nightlife confidence score (0-100) required in high density areas
        /// Relaxed from 70 to 50 to include more legitimate venues
        static let minimumNightlifeScoreHighDensity: Int = 50

        /// Minimum nightlife confidence score (0-100) required in low density areas
        static let minimumNightlifeScoreLowDensity: Int = 35

        /// Default minimum nightlife confidence score (0-100) for medium density areas
        /// Relaxed from 55 to 45 to include more legitimate venues
        static let minimumNightlifeScore: Int = 45
    }

    // MARK: - Map Configuration

    enum Map {
        /// Minimum radius in meters
        static let minimumRadius: CLLocationDistance = 500

        /// Maximum radius in meters
        static let maximumRadius: CLLocationDistance = 50_000

        /// Default camera distance when focusing on a location (meters)
        static let defaultCameraDistance: CLLocationDistance = 500

        /// Camera distance when viewing selected venue (meters)
        static let selectedVenueCameraDistance: CLLocationDistance = 300

        /// Clustering threshold factor (percentage of visible map span)
        static let clusteringThresholdFactor: Double = 0.12

        /// Minimum threshold change ratio to trigger cluster recalculation
        static let clusterRecalculationThreshold: Double = 0.2

        /// Minimum threshold in meters below which clustering is disabled
        static let minimumClusteringThreshold: CLLocationDistance = 50

        /// Zoom level threshold for showing venue titles (latitude delta)
        static let showTitleZoomThreshold: Double = 0.02

        /// Cluster zoom padding scale factor
        static let clusterZoomPaddingScale: Double = 1.4
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
}
