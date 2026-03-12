import Foundation
import CoreLocation

/// App-wide constants. Accessible from any isolation domain.
///
/// All properties are `nonisolated(unsafe)` so they can be read from
/// actors, the main actor, or any other concurrency context without warnings.
enum AppConstants {

    // MARK: - API

    /// Base URL for API Gateway — replace with your deployed endpoint
    static let apiBaseURL = "https://YOUR_API_ID.execute-api.us-east-1.amazonaws.com/prod"

    // MARK: - Search

    /// Default search radius in meters
    static let defaultSearchRadius: CLLocationDistance = 2_000

    /// Maximum venues to display on the map at once
    static let maxVisibleVenues = 100

    /// Debounce interval for region-change searches (seconds)
    static let searchDebounceInterval: TimeInterval = 0.8

    /// Minimum camera movement before "Search This Area" appears (degrees)
    static let searchThiAreaThreshold: Double = 0.005

    // MARK: - Busyness

    /// How long a user report is considered valid (seconds)
    static let reportTTL: TimeInterval = 2 * 60 * 60 // 2 hours

    /// Minimum reports needed for "Reported" confidence label
    static let highConfidenceReportCount = 3

    /// Blend weight for user reports vs heuristic (when 1-2 reports)
    static let reportBlendWeight: Double = 0.70

    // MARK: - Location

    /// Distance filter for location updates (meters)
    static let locationDistanceFilter: CLLocationDistance = 50

    // MARK: - Cache

    /// In-memory report cache TTL (seconds)
    static let reportCacheTTL: TimeInterval = 60 // 1 minute

    // MARK: - Live Refresh

    /// How often the map auto-refreshes busyness data (seconds)
    static let liveRefreshInterval: TimeInterval = 60 // every 60 seconds
}
