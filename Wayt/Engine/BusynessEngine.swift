import Foundation
import os

/// Estimates venue busyness from server-computed fused signals (primary)
/// or from cached user reports when offline (fallback).
struct BusynessEngine: Sendable {

    static let shared = BusynessEngine()

    // MARK: - Primary Path (Server-Computed)

    /// Consume a pre-computed fused estimate from the server.
    func estimate(from response: FusedEstimateResponse) -> BusynessEstimate {
        // Convert 0.0-1.0 normalized score to 1.0-5.0 level scale
        let levelValue = response.busynessScore * 4.0 + 1.0
        let result = BusynessEstimate(
            level: BusynessLevel(closestTo: levelValue),
            confidence: BusynessConfidence(fromServer: response.confidence),
            reportCount: response.reportCount,
            waitMinutes: response.waitMinutes,
            isOpen: response.isOpen,
            hoursToday: response.hoursToday,
            businessStatus: response.businessStatus
        )
        Log.engine.debug("Fused estimate: score=\(response.busynessScore) confidence=\(response.confidence, privacy: .public) sources=\(response.sourceCount ?? 0)")
        return result
    }

    // MARK: - Offline Fallback

    /// Estimate busyness from cached user reports only.
    /// No heuristic — if there are no reports, returns a neutral `.moderate` / `.none`.
    func estimateOffline(
        reports: [BusynessReport] = [],
        at date: Date = Date()
    ) -> BusynessEstimate {
        let validReports = reports.filter { $0.isValid }

        guard !validReports.isEmpty else {
            Log.engine.debug("Offline estimate: no valid reports, returning neutral")
            return BusynessEstimate(
                level: .moderate,
                confidence: .none,
                reportCount: 0,
                waitMinutes: nil,
                isOpen: nil,
                hoursToday: nil,
                businessStatus: nil
            )
        }

        let weightedAvg = weightedReportAverage(validReports)
        let avgWait = averageWait(validReports)
        let level = BusynessLevel(closestTo: weightedAvg)

        let confidence: BusynessConfidence =
            validReports.count >= AppConstants.highConfidenceReportCount ? .high : .low

        return BusynessEstimate(
            level: level,
            confidence: confidence,
            reportCount: validReports.count,
            waitMinutes: avgWait,
            isOpen: nil,
            hoursToday: nil,
            businessStatus: nil
        )
    }

    // MARK: - Report Aggregation

    /// Weighted average of report levels, with exponential decay by age.
    private func weightedReportAverage(_ reports: [BusynessReport]) -> Double {
        var totalWeight: Double = 0
        var weightedSum: Double = 0

        for report in reports {
            // exp(-age/60): full weight at 0 min, ~0.37 at 60 min, ~0.14 at 120 min
            let weight = exp(-report.ageMinutes / 60.0)
            weightedSum += Double(report.busynessLevel.rawValue) * weight
            totalWeight += weight
        }

        guard totalWeight > 0 else { return 3.0 }
        return weightedSum / totalWeight
    }

    /// Time-weighted average wait from reports that include one.
    /// Uses the same exponential decay as busyness: newer reports dominate.
    private func averageWait(_ reports: [BusynessReport]) -> Int? {
        var totalWeight: Double = 0
        var weightedSum: Double = 0

        for report in reports {
            guard let wait = report.waitMinutes else { continue }
            let weight = exp(-report.ageMinutes / 60.0)
            weightedSum += Double(wait) * weight
            totalWeight += weight
        }

        guard totalWeight > 0 else { return nil }
        return Int((weightedSum / totalWeight).rounded())
    }
}

// MARK: - Estimate Result

struct BusynessEstimate: Sendable {
    let level: BusynessLevel
    let confidence: BusynessConfidence
    let reportCount: Int
    let waitMinutes: Int?
    let isOpen: Bool?
    let hoursToday: String?
    let businessStatus: String?
}

// MARK: - Server Response Model

/// Response from the Signal Fusion Engine (`GET /v1/venues/{id}/busyness` or embedded in nearby response).
struct FusedEstimateResponse: Codable, Sendable {
    let busynessScore: Double      // 0.0–1.0 normalized
    let confidence: String         // "VERY_HIGH", "HIGH", "MEDIUM", "LOW", "ESTIMATED" (or legacy lowercase)
    let reportCount: Int
    let waitMinutes: Int?

    // Phase 6 additions (optional for backward compat with old endpoints)
    let venueId: String?
    let sourceCount: Int?
    let sources: [String]?
    let conflictDetected: Bool?
    let computedAt: String?

    // Google Places operating hours (optional)
    let isOpen: Bool?
    let hoursToday: String?
    let businessStatus: String?

    // Minimal init for backward compat (used by tests and legacy code)
    init(
        busynessScore: Double,
        confidence: String,
        reportCount: Int,
        waitMinutes: Int?,
        venueId: String? = nil,
        sourceCount: Int? = nil,
        sources: [String]? = nil,
        conflictDetected: Bool? = nil,
        computedAt: String? = nil,
        isOpen: Bool? = nil,
        hoursToday: String? = nil,
        businessStatus: String? = nil
    ) {
        self.busynessScore = busynessScore
        self.confidence = confidence
        self.reportCount = reportCount
        self.waitMinutes = waitMinutes
        self.venueId = venueId
        self.sourceCount = sourceCount
        self.sources = sources
        self.conflictDetected = conflictDetected
        self.computedAt = computedAt
        self.isOpen = isOpen
        self.hoursToday = hoursToday
        self.businessStatus = businessStatus
    }
}

// MARK: - BusynessLevel Helpers

extension BusynessLevel {
    /// Initialize from a continuous value (1.0–5.0), rounding to nearest case.
    init(closestTo value: Double) {
        let clamped = min(5.0, max(1.0, value))
        let rounded = Int(clamped.rounded(.toNearestOrAwayFromZero))
        self = BusynessLevel(rawValue: rounded) ?? .moderate
    }
}
