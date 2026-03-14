import Foundation

/// Estimates venue busyness from server-computed fused signals (primary)
/// or from cached user reports when offline (fallback).
struct BusynessEngine: Sendable {

    static let shared = BusynessEngine()

    // MARK: - Primary Path (Server-Computed)

    /// Consume a pre-computed fused estimate from the server.
    func estimate(from response: FusedEstimateResponse) -> BusynessEstimate {
        BusynessEstimate(
            level: BusynessLevel(closestTo: response.busynessScore * 5.0),
            confidence: BusynessConfidence(rawValue: response.confidence) ?? .estimated,
            reportCount: response.reportCount,
            waitMinutes: response.waitMinutes
        )
    }

    // MARK: - Offline Fallback

    /// Estimate busyness from cached user reports only.
    /// No heuristic — if there are no reports, returns a neutral `.moderate` / `.estimated`.
    func estimateOffline(
        reports: [BusynessReport] = [],
        at date: Date = Date()
    ) -> BusynessEstimate {
        let validReports = reports.filter { $0.isValid }

        guard !validReports.isEmpty else {
            return BusynessEstimate(
                level: .moderate,
                confidence: .none,
                reportCount: 0,
                waitMinutes: nil
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
            waitMinutes: avgWait
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
}

// MARK: - Server Response Model

/// Response from the Signal Fusion Engine (`GET /v1/venues/{id}/busyness` or embedded in nearby response).
struct FusedEstimateResponse: Codable, Sendable {
    let busynessScore: Double      // 0.0–1.0 normalized
    let confidence: String         // "none", "estimated", "low", "high"
    let reportCount: Int
    let waitMinutes: Int?
}

// MARK: - BusynessLevel Helpers

extension BusynessLevel {
    /// Initialize from a continuous value (1.0–5.0), rounding to nearest case.
    init(closestTo value: Double) {
        let clamped = min(5.0, max(1.0, value))
        let rounded = Int(clamped.rounded())
        self = BusynessLevel(rawValue: rounded) ?? .moderate
    }
}
