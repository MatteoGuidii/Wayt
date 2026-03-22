import Testing
import Foundation
@testable import Wayt

@Suite("BusynessReport")
@MainActor
struct BusynessReportTests {

    // MARK: - ageMinutes

    @Test("ageMinutes reflects time since timestamp")
    func ageMinutesCalculation() {
        let expectedAge: Double = 30
        let timestamp = Date().addingTimeInterval(-expectedAge * 60)
        let report = TestFactories.makeReport(timestamp: timestamp)
        #expect(abs(report.ageMinutes - expectedAge) < 0.1)
    }

    @Test("ageMinutes is near zero for a just-created report")
    func ageMinutesNearZeroForFreshReport() {
        let report = TestFactories.makeReport(timestamp: Date())
        #expect(report.ageMinutes < 0.1)
    }

    // MARK: - isValid

    @Test("Report within TTL is valid")
    func reportWithinTTLIsValid() {
        let oneHourAgo = Date().addingTimeInterval(-60 * 60)
        let report = TestFactories.makeReport(timestamp: oneHourAgo)
        #expect(report.isValid == true)
    }

    @Test("Report older than TTL is invalid")
    func reportOlderThanTTLIsInvalid() {
        let threeHoursAgo = Date().addingTimeInterval(-3 * 60 * 60)
        let report = TestFactories.makeReport(timestamp: threeHoursAgo)
        #expect(report.isValid == false)
    }

    @Test("Fresh report is valid")
    func freshReportIsValid() {
        let report = TestFactories.makeReport(timestamp: Date())
        #expect(report.isValid == true)
    }

    @Test("Report just past TTL is invalid")
    func reportJustPastTTLIsInvalid() {
        let justExpired = Date().addingTimeInterval(-(AppConstants.reportTTL + 1))
        let report = TestFactories.makeReport(timestamp: justExpired)
        #expect(report.isValid == false)
    }

    @Test("Report just inside TTL is valid")
    func reportJustInsideTTLIsValid() {
        let justInside = Date().addingTimeInterval(-(AppConstants.reportTTL - 60))
        let report = TestFactories.makeReport(timestamp: justInside)
        #expect(report.isValid == true)
    }

    // MARK: - Codable Round-trip

    @Test("BusynessReport survives JSON encode/decode round-trip")
    func codableRoundTrip() throws {
        let original = TestFactories.makeReport(busynessLevel: .busy, waitMinutes: 15)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(BusynessReport.self, from: data)

        #expect(decoded.reportId == original.reportId)
        #expect(decoded.userId == original.userId)
        #expect(decoded.busynessLevel == original.busynessLevel)
        #expect(decoded.waitMinutes == original.waitMinutes)
        #expect(decoded.venueName == original.venueName)
        #expect(decoded.venueType == original.venueType)
        #expect(abs(decoded.timestamp.timeIntervalSince(original.timestamp)) < 1)
    }

    @Test("BusynessReport with nil waitMinutes survives round-trip")
    func codableRoundTripNilWait() throws {
        let original = TestFactories.makeReport(busynessLevel: .moderate, waitMinutes: nil)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(BusynessReport.self, from: data)

        #expect(decoded.waitMinutes == nil)
        #expect(decoded.busynessLevel == original.busynessLevel)
    }
}
