import Testing
import Foundation
@testable import Wayt

@Suite("BusynessEngine")
@MainActor
struct BusynessEngineTests {

    let engine = BusynessEngine.shared

    // MARK: - Offline Fallback (No Reports)

    @Test("No reports returns moderate with .none confidence")
    func noReportsReturnsModerateFallback() {
        let estimate = engine.estimateOffline(reports: [])
        #expect(estimate.confidence == .none)
        #expect(estimate.reportCount == 0)
        #expect(estimate.level == .moderate)
        #expect(estimate.waitMinutes == nil)
    }

    // MARK: - Report-Based Estimation

    @Test("Three reports reach high confidence")
    func threeReportsHighConfidence() {
        let reports = [
            TestFactories.makeReport(busynessLevel: .quiet),
            TestFactories.makeReport(busynessLevel: .quiet),
            TestFactories.makeReport(busynessLevel: .quiet)
        ]
        let estimate = engine.estimateOffline(reports: reports)
        #expect(estimate.confidence == .high)
        #expect(estimate.reportCount == 3)
        #expect(estimate.level == .quiet)
    }

    @Test("One report gives low confidence")
    func oneReportLowConfidence() {
        let report = TestFactories.makeReport(busynessLevel: .packed)
        let estimate = engine.estimateOffline(reports: [report])
        #expect(estimate.confidence == .low)
        #expect(estimate.reportCount == 1)
        #expect(estimate.level == .packed)
    }

    @Test("Reports older than TTL are filtered out")
    func expiredReportsExcluded() {
        let expiredTimestamp = Date().addingTimeInterval(-(AppConstants.reportTTL + 60))
        let report = TestFactories.makeReport(busynessLevel: .packed, timestamp: expiredTimestamp)
        let estimate = engine.estimateOffline(reports: [report])
        #expect(estimate.confidence == .none)
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
        let estimate = engine.estimateOffline(reports: reports)
        // Weighted average biased toward packed (recent)
        #expect(estimate.level.rawValue >= 4)
    }

    @Test("Older report pulls result lower than single fresh packed report")
    func olderReportReducesWeightedAverage() {
        let now = Date()
        let singleFreshReport = [TestFactories.makeReport(busynessLevel: .packed, timestamp: now)]
        let freshPlusOldEmpty = [
            TestFactories.makeReport(busynessLevel: .packed, timestamp: now),
            TestFactories.makeReport(busynessLevel: .empty,  timestamp: now.addingTimeInterval(-90 * 60))
        ]
        let estimateSingle = engine.estimateOffline(reports: singleFreshReport)
        let estimateBlended = engine.estimateOffline(reports: freshPlusOldEmpty)
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
        let estimate = engine.estimateOffline(reports: reports)
        #expect(estimate.waitMinutes == 20)
    }

    @Test("Only reports with wait times contribute to wait average")
    func waitTimeIgnoresNilReports() {
        let reports = [
            TestFactories.makeReport(busynessLevel: .busy, waitMinutes: nil),
            TestFactories.makeReport(busynessLevel: .busy, waitMinutes: 20),
            TestFactories.makeReport(busynessLevel: .busy, waitMinutes: nil)
        ]
        let estimate = engine.estimateOffline(reports: reports)
        #expect(estimate.waitMinutes == 20)
    }

    @Test("No reports with wait times returns nil wait")
    func allReportsWithoutWaitReturnsNilWait() {
        let reports = [
            TestFactories.makeReport(busynessLevel: .busy, waitMinutes: nil),
            TestFactories.makeReport(busynessLevel: .busy, waitMinutes: nil)
        ]
        let estimate = engine.estimateOffline(reports: reports)
        #expect(estimate.waitMinutes == nil)
    }

    // MARK: - Edge Cases

    @Test("All expired reports treated as no reports")
    func allExpiredReportsTreatedAsEmpty() {
        let expired = Date().addingTimeInterval(-(AppConstants.reportTTL + 1))
        let reports = [
            TestFactories.makeReport(timestamp: expired),
            TestFactories.makeReport(timestamp: expired)
        ]
        let estimate = engine.estimateOffline(reports: reports)
        #expect(estimate.confidence == .none)
        #expect(estimate.reportCount == 0)
    }

    @Test("Report just past TTL boundary is excluded")
    func reportJustPastTTLExcluded() {
        let justExpired = Date().addingTimeInterval(-(AppConstants.reportTTL + 1))
        let report = TestFactories.makeReport(busynessLevel: .packed, timestamp: justExpired)
        let estimate = engine.estimateOffline(reports: [report])
        #expect(estimate.confidence == .none)
        #expect(estimate.reportCount == 0)
    }

    // MARK: - Server Response Path

    @Test("estimate(from:) maps fused response correctly")
    func estimateFromFusedResponse() {
        let response = FusedEstimateResponse(
            busynessScore: 0.8,
            confidence: "high",
            reportCount: 5,
            waitMinutes: 15
        )
        let estimate = engine.estimate(from: response)
        #expect(estimate.level == .busy) // 0.8 * 5 = 4.0 → .busy
        #expect(estimate.confidence == .high)
        #expect(estimate.reportCount == 5)
        #expect(estimate.waitMinutes == 15)
    }

    @Test("estimate(from:) passes through businessStatus")
    func estimatePassesThroughBusinessStatus() {
        let response = FusedEstimateResponse(
            busynessScore: 0.5,
            confidence: "medium",
            reportCount: 1,
            waitMinutes: nil,
            businessStatus: "CLOSED_PERMANENTLY"
        )
        let estimate = engine.estimate(from: response)
        #expect(estimate.businessStatus == "CLOSED_PERMANENTLY")
    }

    @Test("estimate(from:) has nil businessStatus when not provided")
    func estimateNilBusinessStatus() {
        let response = FusedEstimateResponse(
            busynessScore: 0.5,
            confidence: "medium",
            reportCount: 1,
            waitMinutes: nil
        )
        let estimate = engine.estimate(from: response)
        #expect(estimate.businessStatus == nil)
    }
}
