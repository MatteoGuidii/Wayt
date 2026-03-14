import Testing
import Foundation
@testable import Venuu

@Suite("BusynessEngine")
@MainActor
struct BusynessEngineTests {

    let engine = BusynessEngine.shared

    // MARK: - Date Helper

    private func makeDate(day: Int, hour: Int, minute: Int = 0) -> Date {
        // Jan 1 2023 = Sunday (weekday 1), Jan 2 = Monday, ..., Jan 6 = Friday, Jan 7 = Saturday
        Calendar.current.date(from: DateComponents(
            year: 2023, month: 1, day: day, hour: hour, minute: minute
        )) ?? Date()
    }

    // MARK: - Heuristic Only

    @Test("Bar at 11pm Friday returns packed, confidence estimated")
    func barPeakFridayNight() {
        let date = makeDate(day: 6, hour: 23) // Friday 11pm
        let estimate = engine.estimate(venueType: .bar, reports: [], at: date)
        #expect(estimate.confidence == .estimated)
        #expect(estimate.reportCount == 0)
        #expect(estimate.level.rawValue >= 4)
    }

    @Test("Bar at 9am Tuesday returns empty or quiet, confidence estimated")
    func barOffPeakTuesdayMorning() {
        let date = makeDate(day: 3, hour: 9) // Tuesday 9am
        let estimate = engine.estimate(venueType: .bar, reports: [], at: date)
        #expect(estimate.confidence == .estimated)
        #expect(estimate.level.rawValue <= 2)
    }

    @Test("Restaurant at 7pm Saturday returns busy")
    func restaurantPeakSaturdayEvening() {
        let date = makeDate(day: 7, hour: 19) // Saturday 7pm
        let estimate = engine.estimate(venueType: .restaurant, reports: [], at: date)
        #expect(estimate.confidence == .estimated)
        #expect(estimate.level.rawValue >= 4)
    }

    @Test("Cafe at 8am Monday returns moderate or higher")
    func cafePeakMondayMorning() {
        let date = makeDate(day: 2, hour: 8) // Monday 8am
        let estimate = engine.estimate(venueType: .cafe, reports: [], at: date)
        #expect(estimate.confidence == .estimated)
        #expect(estimate.level.rawValue >= 3)
    }

    @Test("Club at 2am Saturday returns packed")
    func clubPeakSaturdayNight() {
        let date = makeDate(day: 7, hour: 2) // Saturday 2am
        let estimate = engine.estimate(venueType: .club, reports: [], at: date)
        #expect(estimate.confidence == .estimated)
        #expect(estimate.level.rawValue >= 4)
    }

    @Test("Club at 3pm Wednesday returns empty")
    func clubOffPeakWednesdayAfternoon() {
        let date = makeDate(day: 4, hour: 15) // Wednesday 3pm
        let estimate = engine.estimate(venueType: .club, reports: [], at: date)
        #expect(estimate.confidence == .estimated)
        #expect(estimate.level == .empty)
    }

    // MARK: - Report Blending

    @Test("One packed report at quiet time blends to mid-range, low confidence")
    func oneReportBlendsWithHeuristic() {
        let date = makeDate(day: 3, hour: 9) // bar 9am Tuesday, heuristic = .empty (1)
        let report = TestFactories.makeReport(busynessLevel: .packed) // 0.70 * 5 + 0.30 * 1 = 3.8 → .busy
        let estimate = engine.estimate(venueType: .bar, reports: [report], at: date)
        #expect(estimate.confidence == .low)
        #expect(estimate.reportCount == 1)
        #expect(estimate.level.rawValue >= 3)
    }

    @Test("Three reports reach high confidence and heuristic is ignored")
    func threeReportsHighConfidence() {
        let peakDate = makeDate(day: 7, hour: 23) // bar 11pm Saturday, heuristic = .packed
        let reports = [
            TestFactories.makeReport(busynessLevel: .quiet),
            TestFactories.makeReport(busynessLevel: .quiet),
            TestFactories.makeReport(busynessLevel: .quiet)
        ]
        let estimate = engine.estimate(venueType: .bar, reports: reports, at: peakDate)
        #expect(estimate.confidence == .high)
        #expect(estimate.reportCount == 3)
        #expect(estimate.level == .quiet)
    }

    @Test("Reports older than TTL are filtered out and treated as no reports")
    func expiredReportsExcluded() {
        let expiredTimestamp = Date().addingTimeInterval(-(AppConstants.reportTTL + 60))
        let report = TestFactories.makeReport(busynessLevel: .packed, timestamp: expiredTimestamp)
        let estimate = engine.estimate(venueType: .bar, reports: [report])
        #expect(estimate.confidence == .estimated)
        #expect(estimate.reportCount == 0)
    }

    // MARK: - Exponential Decay

    @Test("Recent report has more weight than old report")
    func exponentialDecayFavorsRecentReport() {
        let recentTimestamp = Date().addingTimeInterval(-5 * 60)   // 5 min ago
        let oldTimestamp    = Date().addingTimeInterval(-90 * 60)  // 90 min ago

        let reports = [
            TestFactories.makeReport(busynessLevel: .packed, timestamp: recentTimestamp), // 5
            TestFactories.makeReport(busynessLevel: .empty,  timestamp: oldTimestamp)     // 1
        ]
        let estimate = engine.estimate(venueType: .restaurant, reports: reports)
        // Weighted average biased toward packed (recent) → should be busy or packed, not quiet/empty
        #expect(estimate.level.rawValue >= 4)
    }

    @Test("Older report pulls result lower than single fresh packed report would give")
    func olderReportReducesWeightedAverage() {
        let now = Date()
        let singleFreshReport = [TestFactories.makeReport(busynessLevel: .packed, timestamp: now)]
        let freshPlusOldEmpty = [
            TestFactories.makeReport(busynessLevel: .packed, timestamp: now),
            TestFactories.makeReport(busynessLevel: .empty,  timestamp: now.addingTimeInterval(-90 * 60))
        ]
        let estimateSingle = engine.estimate(venueType: .restaurant, reports: singleFreshReport)
        let estimateBlended = engine.estimate(venueType: .restaurant, reports: freshPlusOldEmpty)
        #expect(estimateBlended.level.rawValue <= estimateSingle.level.rawValue)
    }

    // MARK: - Wait Time Aggregation

    @Test("Multiple reports with wait times produce weighted average")
    func waitTimeWeightedAverage() {
        let now = Date()
        let reports = [
            TestFactories.makeReport(busynessLevel: .busy, waitMinutes: 10, timestamp: now),
            TestFactories.makeReport(busynessLevel: .busy, waitMinutes: 30, timestamp: now)
        ]
        let estimate = engine.estimate(venueType: .restaurant, reports: reports)
        #expect(estimate.waitMinutes == 20)
    }

    @Test("Only reports with wait times contribute to wait average")
    func waitTimeIgnoresNilReports() {
        let reports = [
            TestFactories.makeReport(busynessLevel: .busy, waitMinutes: nil),
            TestFactories.makeReport(busynessLevel: .busy, waitMinutes: 20),
            TestFactories.makeReport(busynessLevel: .busy, waitMinutes: nil)
        ]
        let estimate = engine.estimate(venueType: .restaurant, reports: reports)
        #expect(estimate.waitMinutes == 20)
    }

    @Test("No reports with wait times returns nil wait")
    func allReportsWithoutWaitReturnsNilWait() {
        let reports = [
            TestFactories.makeReport(busynessLevel: .busy, waitMinutes: nil),
            TestFactories.makeReport(busynessLevel: .busy, waitMinutes: nil)
        ]
        let estimate = engine.estimate(venueType: .restaurant, reports: reports)
        #expect(estimate.waitMinutes == nil)
    }

    // MARK: - Edge Cases

    @Test("Empty reports array falls back to pure heuristic")
    func emptyReportsFallsBackToHeuristic() {
        let estimate = engine.estimate(venueType: .bar, reports: [])
        #expect(estimate.confidence == .estimated)
        #expect(estimate.reportCount == 0)
    }

    @Test("All expired reports treated as no reports")
    func allExpiredReportsTreatedAsEmpty() {
        let expired = Date().addingTimeInterval(-(AppConstants.reportTTL + 1))
        let reports = [
            TestFactories.makeReport(timestamp: expired),
            TestFactories.makeReport(timestamp: expired)
        ]
        let estimate = engine.estimate(venueType: .bar, reports: reports)
        #expect(estimate.confidence == .estimated)
        #expect(estimate.reportCount == 0)
    }

    @Test("Report just past TTL boundary is excluded")
    func reportJustPastTTLExcluded() {
        let justExpired = Date().addingTimeInterval(-(AppConstants.reportTTL + 1))
        let report = TestFactories.makeReport(busynessLevel: .packed, timestamp: justExpired)
        let estimate = engine.estimate(venueType: .bar, reports: [report])
        #expect(estimate.confidence == .estimated)
        #expect(estimate.reportCount == 0)
    }
}
