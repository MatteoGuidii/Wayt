import Testing
import Foundation
@testable import Wayt

@Suite("ReportService")
@MainActor
struct ReportServiceTests {

    // MARK: - Cache Invalidation

    @Test("invalidateCache does not crash when called on a fresh instance")
    func invalidateCacheOnFreshInstance() {
        let service = ReportService()
        service.invalidateCache()
    }

    @Test("invalidateCache is idempotent")
    func invalidateCacheIsIdempotent() {
        let service = ReportService()
        service.invalidateCache()
        service.invalidateCache()
        service.invalidateCache()
    }

    @Test("Cache timestamp of distantPast is always stale relative to TTL")
    func distantPastAlwaysStale() {
        let elapsed = Date().timeIntervalSince(.distantPast)
        #expect(elapsed > AppConstants.reportCacheTTL)
    }

    // MARK: - SubmitReportRequest Codable

    @Test("SubmitReportRequest encodes and decodes correctly")
    func submitReportRequestCodableRoundTrip() throws {
        let request = SubmitReportRequest(
            venueId: "test-venue-id",
            busynessLevel: 4,
            waitMinutes: 15,
            venueName: "The Test Bar",
            venueType: "bar",
            lat: 43.65107,
            lng: -79.34723
        )
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(SubmitReportRequest.self, from: data)

        #expect(decoded.venueId == request.venueId)
        #expect(decoded.busynessLevel == request.busynessLevel)
        #expect(decoded.waitMinutes == request.waitMinutes)
        #expect(decoded.venueName == request.venueName)
        #expect(decoded.venueType == request.venueType)
        #expect(decoded.lat == request.lat)
        #expect(decoded.lng == request.lng)
    }

    @Test("SubmitReportRequest with nil waitMinutes encodes correctly")
    func submitReportRequestNilWait() throws {
        let request = SubmitReportRequest(
            venueId: "id",
            busynessLevel: 2,
            waitMinutes: nil,
            venueName: "Cafe",
            venueType: "cafe",
            lat: 0.0,
            lng: 0.0
        )
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(SubmitReportRequest.self, from: data)
        #expect(decoded.waitMinutes == nil)
    }

    // MARK: - VenueReportSummary Codable

    @Test("VenueReportSummary encodes and decodes correctly")
    func venueReportSummaryCodableRoundTrip() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let now = Date()
        let summary = VenueReportSummary(
            venueId: "venue-abc",
            avgBusyness: 3.5,
            reportCount: 4,
            lastReportedAt: now,
            avgWaitMinutes: 10
        )
        let data = try encoder.encode(summary)
        let decoded = try decoder.decode(VenueReportSummary.self, from: data)

        #expect(decoded.venueId == summary.venueId)
        #expect(decoded.avgBusyness == summary.avgBusyness)
        #expect(decoded.reportCount == summary.reportCount)
        #expect(decoded.avgWaitMinutes == summary.avgWaitMinutes)
    }
}
