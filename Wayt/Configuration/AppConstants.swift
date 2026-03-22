import Foundation
import CoreLocation

// MARK: - Notification Names

extension Notification.Name {
    /// Posted after a busyness report is successfully submitted.
    static let reportSubmitted = Notification.Name("reportSubmitted")
}

/// App-wide constants. Accessible from any isolation domain.
enum AppConstants {

    // MARK: - API

    /// Base URL for the deployed API Gateway endpoint
    static let apiBaseURL = "https://ajwkls2g42.execute-api.ca-central-1.amazonaws.com/dev"

    // MARK: - Search

    /// Default search radius in meters
    static let defaultSearchRadius: CLLocationDistance = 2_000

    /// Maximum venues to load per search (clustering keeps rendered annotations low)
    static let maxVisibleVenues = 300

    /// Per-query timeout for MapKit searches (seconds)
    static let mapKitQueryTimeout: TimeInterval = 8

    /// Minimum camera movement before "Search This Area" appears (degrees)
    static let searchThisAreaThreshold: Double = 0.005

    // MARK: - Busyness

    /// How long a user report is considered valid (seconds)
    static let reportTTL: TimeInterval = 2 * 60 * 60 // 2 hours

    /// Minimum reports needed for "Reported" confidence label
    static let highConfidenceReportCount = 3

    /// Blend weight for user reports vs heuristic (when 1-2 reports)
    static let reportBlendWeight: Double = 0.70

    // MARK: - Location

    /// Distance filter for location updates (meters)
    static let locationDistanceFilter: CLLocationDistance = 10

    /// Maximum distance from a venue to allow submitting a report (meters)
    static let reportProximityRadius: CLLocationDistance = 200

    // MARK: - Cache

    /// In-memory fusion cache TTL (seconds).
    /// 5 minutes — cache survives the 2-minute auto-refresh interval and
    /// is still invalidated on >500m movement by FusionService.
    static let reportCacheTTL: TimeInterval = 300 // 5 minutes

    // MARK: - Live Refresh

    /// How often the map auto-refreshes busyness data (seconds)
    static let liveRefreshInterval: TimeInterval = 120 // every 2 minutes
}
