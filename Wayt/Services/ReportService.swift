import CoreLocation
import Foundation
import os

/// Handles submitting and fetching busyness reports from the API.
/// Includes a lightweight in-memory cache for nearby reports.
@MainActor
final class ReportService {

    static let shared = ReportService()

    // MARK: - Cache

    private var cachedReports: [String: VenueReportSummary] = [:]
    private var cacheTimestamp: Date = .distantPast

    private var isCacheValid: Bool {
        Date().timeIntervalSince(cacheTimestamp) < AppConstants.reportCacheTTL
    }

    // MARK: - Submit Report

    func submitReport(
        venue: Venue,
        level: BusynessLevel,
        waitMinutes: Int?
    ) async throws {
        let body = SubmitReportRequest(
            venueId: venue.id,
            busynessLevel: level.rawValue,
            waitMinutes: waitMinutes,
            venueName: venue.name,
            venueType: venue.category.rawValue,
            lat: venue.coordinate.latitude,
            lng: venue.coordinate.longitude,
            timezone: TimeZone.current.identifier
        )
        Log.reports.info("Submitting report for venue \(venue.id, privacy: .public): level=\(level.rawValue)")
        try await APIClient.shared.post(path: "/reports", body: body)
        Log.reports.info("Report submitted successfully for \(venue.id, privacy: .public)")

        // Invalidate cache so next fetch gets fresh data
        invalidateCache()
    }

    // MARK: - Fetch Nearby Reports

    func fetchNearbyReports(
        latitude: Double,
        longitude: Double,
        radiusMeters: Double = 2_000
    ) async throws -> [String: VenueReportSummary] {
        // Return cache if valid
        if isCacheValid {
            Log.reports.debug("Nearby reports cache hit (\(self.cachedReports.count) venues)")
            return cachedReports
        }

        Log.reports.debug("Fetching nearby reports at (\(latitude), \(longitude)) radius=\(Int(radiusMeters))m")
        let queryItems = [
            URLQueryItem(name: "lat", value: String(latitude)),
            URLQueryItem(name: "lng", value: String(longitude)),
            URLQueryItem(name: "radius", value: String(Int(radiusMeters)))
        ]

        let response: NearbyReportsResponse = try await APIClient.shared.get(
            path: "/reports",
            queryItems: queryItems
        )

        // Index by venue ID for O(1) lookup
        var indexed: [String: VenueReportSummary] = [:]
        for summary in response.venues {
            indexed[summary.venueId] = summary
        }

        Log.reports.info("Fetched \(indexed.count) venue report summaries")
        cachedReports = indexed
        cacheTimestamp = Date()
        return indexed
    }

    // MARK: - Fetch Single Venue Reports

    func fetchVenueReports(venueId: String) async throws -> [BusynessReport] {
        Log.reports.debug("Fetching reports for venue \(venueId, privacy: .public)")
        // URL-encode the venue ID (contains spaces + special chars)
        let encoded = venueId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? venueId
        let response: VenueReportsResponse = try await APIClient.shared.get(
            path: "/venues/\(encoded)/reports"
        )
        Log.reports.debug("Got \(response.reports.count) reports for \(venueId, privacy: .public)")
        return response.reports
    }

    // MARK: - Cache Control

    func invalidateCache() {
        Log.reports.debug("Report cache invalidated")
        cachedReports = [:]
        cacheTimestamp = .distantPast
    }
}
