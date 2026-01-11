import Foundation
import CoreLocation

/// Central configuration for app-wide constants
enum AppConfiguration {

    // MARK: - Image Service Configuration

    enum ImageService {
        /// Maximum number of images to fetch per search
        static let maxImageFetchCount = 20

        /// Number of priority images to fetch first (visible on screen)
        static let priorityCount = 2

        /// Batch size for throttled image fetching
        static let batchSize = 2

        /// Delay between batches in nanoseconds (8 seconds)
        static let batchDelayNanoseconds: UInt64 = 8_000_000_000

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

        /// Maximum search radius for dynamic expansion (meters)
        static let maxSearchRadius: CLLocationDistance = 15000

        /// Minimum venues before triggering radius expansion
        static let minVenuesBeforeExpansion: Int = 10

        /// Radius expansion multiplier when results are sparse
        static let radiusExpansionMultiplier: Double = 1.5

        /// Extended radius for text-based venue search (meters)
        static let textSearchRadius: CLLocationDistance = 25000

        /// Maximum number of venues to display
        static let maxResultCount = 300

        /// Grid size for multi-cell search (NxN grid)
        static let searchGridSize = 2
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

        // MARK: - Adaptive Marker Display Thresholds

        /// Zoom threshold for dot-only markers (latitude delta)
        /// Above this threshold, markers display as small colored dots
        static let dotOnlyZoomThreshold: Double = 0.05

        /// Zoom threshold for icon-only markers (latitude delta)
        /// Between this and dotOnlyZoomThreshold, markers show icon without title
        static let iconOnlyZoomThreshold: Double = 0.025

        /// Zoom threshold for full markers with titles (latitude delta)
        /// Below this threshold, markers show icon + venue name
        static let fullMarkerZoomThreshold: Double = 0.012
    }

    // MARK: - Location Configuration

    enum Location {
        /// Balanced accuracy to avoid battery drain
        static let desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyNearestTenMeters

        /// Minimum distance change (meters) before requesting another location update
        static let distanceFilter: CLLocationDistance = 25

        /// Distance change used when tracking in foreground
        static let highAccuracyDistanceFilter: CLLocationDistance = 5

        /// Distance (meters) the user must move before refreshing the city label
        static let cityRefreshDistance: CLLocationDistance = 750

        /// Minimum time (seconds) between reverse-geo lookups
        static let cityRefreshInterval: TimeInterval = 120

        /// Minimum time (seconds) before retrying a failed reverse-geo lookup
        static let cityRefreshRetryInterval: TimeInterval = 15

        /// Heading filter for orientation changes
        static let headingFilterDegrees: CLLocationDegrees = 10
    }
}
