import Foundation

struct BusynessReport: Codable, Identifiable, Sendable {
    let reportId: String
    let userId: String
    let busynessLevel: BusynessLevel
    let waitMinutes: Int?
    let timestamp: Date
    let venueName: String
    let venueType: String

    var id: String { reportId }

    /// How many minutes ago this report was submitted
    var ageMinutes: Double {
        Date().timeIntervalSince(timestamp) / 60.0
    }

    /// Whether the report is still within the valid TTL window
    var isValid: Bool {
        Date().timeIntervalSince(timestamp) < AppConstants.reportTTL
    }
}

// MARK: - API Response Wrappers

/// Response from GET /venues/{venueId}/reports
struct VenueReportsResponse: Codable, Sendable {
    let venueId: String
    let reports: [BusynessReport]
}

/// Response from GET /reports?lat=&lng=&radius=
struct NearbyReportsResponse: Codable, Sendable {
    let venues: [VenueReportSummary]
}

struct VenueReportSummary: Codable, Sendable {
    let venueId: String
    let avgBusyness: Double
    let reportCount: Int
    let lastReportedAt: Date?
    let avgWaitMinutes: Int?
}

struct SubmitReportRequest: Codable, Sendable {
    let venueId: String
    let busynessLevel: Int
    let waitMinutes: Int?
    let venueName: String
    let venueType: String
    let lat: Double
    let lng: Double
    let timezone: String
}
