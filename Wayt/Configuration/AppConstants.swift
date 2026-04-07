import Foundation
import CoreLocation

// MARK: - Notification Names

extension Notification.Name {
    /// Posted after a busyness report is successfully submitted.
    static let reportSubmitted = Notification.Name("reportSubmitted")
}

/// App-wide constants. Accessible from any isolation domain.
nonisolated enum AppConstants {

    // MARK: - API

    /// Base URL for the deployed API Gateway endpoint
    static let apiBaseURL = "https://ndfwnjyukl.execute-api.ca-central-1.amazonaws.com/dev"

    // MARK: - Search 

    /// Default search radius in meters
    static let defaultSearchRadius: CLLocationDistance = 800

    /// Maximum venues to load per search (clustering keeps rendered annotations low)
    static let maxVisibleVenues = 300

    /// Per-query timeout for MapKit searches (seconds)
    static let mapKitQueryTimeout: TimeInterval = 8

    /// Minimum region span (degrees) passed to MapKit searches.
    /// Ensures MapKit searches a large enough area even when zoomed in tight.
    static let minimumSearchSpan: Double = 0.01

    /// Minimum camera movement before "Search This Area" appears (degrees)
    static let searchThisAreaThreshold: Double = 0.005

    // MARK: - Busyness

    /// How long a user report is considered valid (seconds)
    static let reportTTL: TimeInterval = 2 * 60 * 60 // 2 hours

    /// Minimum time between reports on the same venue by the same user (seconds)
    static let reportCooldown: TimeInterval = 30 * 60 // 30 minutes

    /// Minimum reports needed for "Reported" confidence label
    static let highConfidenceReportCount = 3

    /// Blend weight for user reports vs heuristic (when 1-2 reports)
    static let reportBlendWeight: Double = 0.70

    // MARK: - Location

    /// Distance filter for location updates (meters)
    static let locationDistanceFilter: CLLocationDistance = 10

    /// Maximum distance from a venue to allow submitting a report (meters)
    static let reportProximityRadius: CLLocationDistance = 200

    // MARK: - Walking

    /// Additive radius increment per expand tap (meters). ~12 min walk.
    static let expandIncrement: CLLocationDistance = 1_000

    /// Maximum search radius for expand (meters). ~60 min walk.
    static let maxWalkingRadius: CLLocationDistance = 5_000

    // MARK: - Cache

    /// In-memory fusion cache TTL (seconds).
    /// 5 minutes — cache survives the 2-minute auto-refresh interval and
    /// is still invalidated on >500m movement by FusionService.
    static let reportCacheTTL: TimeInterval = 300 // 5 minutes

    // MARK: - Live Refresh

    /// Default refresh interval when no adaptive hint is available (seconds)
    static let liveRefreshInterval: TimeInterval = 120 // every 2 minutes

    // MARK: - Adaptive Refresh

    /// Minimum adaptive refresh interval (seconds). Prevents excessive polling / battery drain.
    static let minAdaptiveRefreshInterval: TimeInterval = 15
    /// Maximum adaptive refresh interval (seconds). Same as default live refresh.
    static let maxAdaptiveRefreshInterval: TimeInterval = 120
}
