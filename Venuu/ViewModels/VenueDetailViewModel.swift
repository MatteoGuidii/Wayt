import Combine
import Foundation

@MainActor
final class VenueDetailViewModel: ObservableObject {

    // MARK: - Published

    @Published var estimate: BusynessEstimate
    @Published var recentReports: [BusynessReport] = []
    @Published var isLoadingReports: Bool = false
    @Published var showReportSheet: Bool = false
    @Published var reportSubmitted: Bool = false

    // MARK: - Private

    let venue: Venue
    private let busynessEngine = BusynessEngine.shared

    // MARK: - Init

    init(venue: Venue) {
        self.venue = venue
        // Start with the venue's existing busyness (from map, which may include API data)
        // rather than recalculating from scratch
        if let existingLevel = venue.busyness {
            self.estimate = BusynessEstimate(
                level: existingLevel,
                confidence: venue.busynessConfidence,
                reportCount: venue.reportCount,
                waitMinutes: venue.estimatedWaitMinutes
            )
        } else {
            self.estimate = busynessEngine.estimate(venueType: venue.type)
        }
    }

    // MARK: - Load Reports

    func loadReports() async {
        isLoadingReports = true
        do {
            let reports = try await ReportService.shared.fetchVenueReports(venueId: venue.id)
            recentReports = reports
            // Only re-estimate if we actually got reports — otherwise keep the
            // initial estimate (which already includes map overlay data)
            if !reports.isEmpty {
                estimate = busynessEngine.estimate(venueType: venue.type, reports: reports)
            }
        } catch {
            // Initial estimate is already set — this is fine
            print("[VenueDetail] Reports unavailable: \(error.localizedDescription)")
        }
        isLoadingReports = false
    }

    // MARK: - Submit Report

    func submitReport(level: BusynessLevel, waitMinutes: Int?) async {
        // 1. Optimistic update — reflect the report INSTANTLY in the UI
        let newReportCount = estimate.reportCount + 1
        let confidence: BusynessConfidence = newReportCount >= AppConstants.highConfidenceReportCount
            ? .high : .low
        estimate = BusynessEstimate(
            level: level,
            confidence: confidence,
            reportCount: newReportCount,
            waitMinutes: waitMinutes ?? estimate.waitMinutes
        )
        reportSubmitted = true

        // 2. Send to API in background — don't block UI
        Task.detached { [venue] in
            do {
                try await ReportService.shared.submitReport(
                    venue: venue,
                    level: level,
                    waitMinutes: waitMinutes
                )
                print("[VenueDetail] Report submitted successfully")
            } catch {
                print("[VenueDetail] Submit failed: \(error.localizedDescription)")
            }
        }
    }
}
