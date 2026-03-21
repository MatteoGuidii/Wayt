import Foundation
import os

/// Centralized structured logging for Venuu.
///
/// Uses Apple's `os.Logger` — lazy-evaluated (zero cost when not collected),
/// integrated with Console.app and Xcode's log viewer.
///
/// Filter in Console.app by subsystem or category:
///   subsystem: com.venuu.app   category: api | auth | search | ...
///
/// Usage:
///   Log.api.info("GET /reports -> 200 (42ms)")
///   Log.search.notice("Rate limited, returning stale cache")
///   Log.auth.error("Token fetch failed: \(error.localizedDescription)")
enum Log {
    private nonisolated static let subsystem = Bundle.main.bundleIdentifier ?? "com.venuu.app"

    /// HTTP requests, responses, status codes, timing
    nonisolated static let api      = Logger(subsystem: subsystem, category: "api")
    /// Cognito session, sign-in/out, token fetching
    nonisolated static let auth     = Logger(subsystem: subsystem, category: "auth")
    /// CoreLocation updates, permissions, accuracy filtering
    nonisolated static let location = Logger(subsystem: subsystem, category: "location")
    /// MapKit venue search, rate limiting, caching
    nonisolated static let search   = Logger(subsystem: subsystem, category: "search")
    /// Signal fusion estimates, batch fetches, cache
    nonisolated static let fusion   = Logger(subsystem: subsystem, category: "fusion")
    /// Busyness report submission and fetching
    nonisolated static let reports  = Logger(subsystem: subsystem, category: "reports")
    /// Saved venues operations and persistence
    nonisolated static let saved    = Logger(subsystem: subsystem, category: "savedVenues")
    /// User profile load, update, image upload
    nonisolated static let profile  = Logger(subsystem: subsystem, category: "profile")
    /// Map view orchestration, clustering, refresh
    nonisolated static let map      = Logger(subsystem: subsystem, category: "map")
    /// Busyness estimation engine
    nonisolated static let engine   = Logger(subsystem: subsystem, category: "engine")
    /// App lifecycle, configuration
    nonisolated static let app      = Logger(subsystem: subsystem, category: "app")
}
