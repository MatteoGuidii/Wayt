import Foundation

/// The core differentiator: estimates venue busyness using time-based heuristics
/// and overlays real crowd-sourced reports when available.
struct BusynessEngine: Sendable {

    static let shared = BusynessEngine()

    // MARK: - Public

    /// Estimate busyness for a venue, blending heuristics with user reports.
    func estimate(
        venueType: VenueType,
        reports: [BusynessReport] = [],
        at date: Date = Date()
    ) -> BusynessEstimate {
        let validReports = reports.filter { $0.isValid }
        let heuristicLevel = heuristicBusyness(for: venueType, at: date)

        if validReports.isEmpty {
            return BusynessEstimate(
                level: heuristicLevel,
                confidence: .estimated,
                reportCount: 0,
                waitMinutes: nil
            )
        }

        // Weighted average of reports (exponential decay by age)
        let weightedAvg = weightedReportAverage(validReports)
        let avgWait = averageWait(validReports)

        if validReports.count >= AppConstants.highConfidenceReportCount {
            // High confidence: trust reports fully
            let level = BusynessLevel(closestTo: weightedAvg)
            return BusynessEstimate(
                level: level,
                confidence: .high,
                reportCount: validReports.count,
                waitMinutes: avgWait
            )
        } else {
            // Low confidence: blend reports with heuristic
            let blended = AppConstants.reportBlendWeight * weightedAvg
                + (1 - AppConstants.reportBlendWeight) * Double(heuristicLevel.rawValue)
            let level = BusynessLevel(closestTo: blended)
            return BusynessEstimate(
                level: level,
                confidence: .low,
                reportCount: validReports.count,
                waitMinutes: avgWait
            )
        }
    }

    // MARK: - Heuristic Algorithm

    /// Estimate busyness purely from venue type + current time.
    func heuristicBusyness(for type: VenueType, at date: Date = Date()) -> BusynessLevel {
        let score = heuristicScore(for: type, at: date)
        return BusynessLevel(closestTo: score * 5.0)
    }

    /// Returns a 0.0–1.0 score for how busy a venue type likely is right now.
    private func heuristicScore(for type: VenueType, at date: Date) -> Double {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let dayOfWeek = calendar.component(.weekday, from: date) // 1 = Sunday

        // Base: how close is the current hour to peak hours?
        let baseScore = hourProximityScore(hour: hour, peaks: type.peakHours)

        // Day multiplier
        let dayMultiplier: Double
        if type.peakDays.contains(dayOfWeek) {
            dayMultiplier = 1.25
        } else {
            dayMultiplier = 0.80
        }

        return min(1.0, max(0.0, baseScore * dayMultiplier))
    }

    /// Score based on how close the current hour is to peak hours.
    /// Returns 0.0 (far from any peak) to 1.0 (exactly at peak).
    private func hourProximityScore(hour: Int, peaks: [Int]) -> Double {
        if peaks.isEmpty { return 0.3 }

        // Direct peak hit
        if peaks.contains(hour) { return 0.85 }

        // Find minimum circular distance to any peak hour
        let minDistance = peaks.map { peak -> Int in
            let diff = abs(hour - peak)
            return min(diff, 24 - diff)
        }.min() ?? 12

        // Decay curve: score drops off as distance from peak increases
        switch minDistance {
        case 0:    return 0.85
        case 1:    return 0.65
        case 2:    return 0.45
        case 3:    return 0.30
        case 4:    return 0.18
        default:   return 0.08
        }
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

// MARK: - BusynessLevel Helpers

extension BusynessLevel {
    /// Initialize from a continuous value (1.0–5.0), rounding to nearest case.
    init(closestTo value: Double) {
        let clamped = min(5.0, max(1.0, value))
        let rounded = Int(clamped.rounded())
        self = BusynessLevel(rawValue: rounded) ?? .moderate
    }
}
