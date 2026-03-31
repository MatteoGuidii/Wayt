import Combine
import CoreLocation
import Foundation
import os

@MainActor
final class VenueDetailViewModel: ObservableObject {

    // MARK: - Published

    @Published var estimate: BusynessEstimate
    @Published var recentReports: [BusynessReport] = []
    @Published var isLoadingReports: Bool = false
    @Published var showReportSheet: Bool = false
    @Published var reportSubmitted: Bool = false
    @Published var isWithinReportRange: Bool = false
    @Published var isOnCooldown: Bool = false
    @Published var cooldownRemaining: TimeInterval = 0
    @Published var venueDetailsFull: VenueDetailsFull?

    // MARK: - Private

    let venue: Venue
    private let busynessEngine = BusynessEngine.shared
    private var cooldownTask: Task<Void, Never>?

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
                waitMinutes: venue.estimatedWaitMinutes,
                isOpen: venue.isOpen,
                hoursToday: venue.hoursToday,
                businessStatus: venue.businessStatus,
                venueDetails: nil
            )
        } else {
            self.estimate = busynessEngine.estimateOffline()
        }
    }

    // MARK: - Load Reports

    func loadReports() async {
        isLoadingReports = true

        // Try fused estimate from v1 endpoint first (in parallel with report fetch)
        async let fusedFuture = loadFusedEstimate()
        async let reportsFuture = loadRecentReports()

        let fusedResult = await fusedFuture
        let reports = await reportsFuture

        recentReports = reports

        if let fused = fusedResult {
            // Use server-computed fused estimate (most accurate)
            estimate = fused
        } else if !reports.isEmpty {
            // Fallback: re-estimate from reports only
            estimate = busynessEngine.estimateOffline(reports: reports)
        }
        // else: keep the initial estimate from map overlay

        isLoadingReports = false
    }

    /// Fetch full venue data from the single-venue endpoint.
    /// Always prefers the fresh response (has hours, rating, reviews, price)
    /// over the nearby cache which may be incomplete for cold venues.
    private func loadFusedEstimate() async -> BusynessEstimate? {
        let vid = venue.id
        Log.fusion.info("[Detail] Fetching for \(vid, privacy: .public)")
        do {
            let response = try await FusionService.shared.fetchVenueBusyness(
                venueId: venue.id,
                venueName: venue.name,
                lat: venue.coordinate.latitude,
                lng: venue.coordinate.longitude,
                address: venue.address
            )
            let hasDetails = response.venueDetails != nil
            let hours = response.hoursToday ?? "nil"
            let rating = response.venueDetails?.rating
            Log.fusion.info("[Detail] OK: isOpen=\(String(describing: response.isOpen)) hours=\(hours, privacy: .public) hasDetails=\(hasDetails) rating=\(String(describing: rating))")
            venueDetailsFull = response.venueDetails
            return busynessEngine.estimate(from: response.toFusedEstimate())
        } catch {
            Log.fusion.error("[Detail] FAILED: \(String(describing: error))")
            // Fall back to nearby cache if single-venue endpoint fails
            if let cached = FusionService.shared.cachedEstimate(for: venue.id) {
                return busynessEngine.estimate(from: cached)
            }
            return nil
        }
    }

    /// Fetch individual user reports for the "Recent Reports" section.
    private func loadRecentReports() async -> [BusynessReport] {
        do {
            return try await ReportService.shared.fetchVenueReports(venueId: venue.id)
        } catch {
            Log.reports.notice("Reports unavailable for detail: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Proximity Check

    func updateProximity(userLocation: CLLocation?) {
        guard let userLocation else {
            isWithinReportRange = false
            return
        }
        let venueLocation = CLLocation(
            latitude: venue.coordinate.latitude,
            longitude: venue.coordinate.longitude
        )
        let distance = userLocation.distance(from: venueLocation)
        isWithinReportRange = distance <= AppConstants.reportProximityRadius
    }

    func distanceToVenue(from userLocation: CLLocation?) -> CLLocationDistance? {
        guard let userLocation else { return nil }
        let venueLocation = CLLocation(
            latitude: venue.coordinate.latitude,
            longitude: venue.coordinate.longitude
        )
        return userLocation.distance(from: venueLocation)
    }

    // MARK: - Cooldown

    /// Check local report history for an active cooldown on this venue.
    func checkCooldown(reportHistory: [ReportHistoryEntry]) {
        guard let lastReport = reportHistory.first(where: { $0.venueId == venue.id }) else {
            clearCooldown()
            return
        }
        let elapsed = Date().timeIntervalSince(lastReport.timestamp)
        let remaining = AppConstants.reportCooldown - elapsed
        if remaining > 0 {
            startCooldown(remaining: remaining)
        } else {
            clearCooldown()
        }
    }

    private func startCooldown(remaining: TimeInterval) {
        isOnCooldown = true
        cooldownRemaining = remaining
        cooldownTask?.cancel()
        cooldownTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                cooldownRemaining -= 1
                if cooldownRemaining <= 0 {
                    clearCooldown()
                    return
                }
            }
        }
    }

    private func clearCooldown() {
        isOnCooldown = false
        cooldownRemaining = 0
        cooldownTask?.cancel()
        cooldownTask = nil
    }

    // MARK: - Submit Report

    func submitReport(level: BusynessLevel, waitMinutes: Int?) async {
        // 1. Optimistic update — reflect the report INSTANTLY in the UI
        let previousEstimate = estimate
        let newReportCount = estimate.reportCount + 1
        let confidence: BusynessConfidence = newReportCount >= AppConstants.highConfidenceReportCount
            ? .high : .low
        estimate = BusynessEstimate(
            level: level,
            confidence: confidence,
            reportCount: newReportCount,
            waitMinutes: waitMinutes ?? estimate.waitMinutes,
            isOpen: estimate.isOpen,
            hoursToday: estimate.hoursToday,
            businessStatus: estimate.businessStatus,
            venueDetails: estimate.venueDetails
        )
        reportSubmitted = true

        // Start cooldown immediately for responsive UI
        startCooldown(remaining: AppConstants.reportCooldown)

        // 2. Send to API in background — don't block UI
        let venueSnapshot = venue
        let rollbackEstimate = previousEstimate
        Task.detached { [weak self] in
            do {
                try await ReportService.shared.submitReport(
                    venue: venueSnapshot,
                    level: level,
                    waitMinutes: waitMinutes
                )
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: .reportSubmitted,
                        object: venueSnapshot.id,
                        userInfo: [
                            "venueId": venueSnapshot.id,
                            "venueName": venueSnapshot.name,
                            "venueType": venueSnapshot.category.rawValue,
                            "busynessLevel": level.rawValue,
                        ]
                    )
                }
                Log.reports.info("Report submitted successfully for \(venueSnapshot.id, privacy: .public)")
            } catch APIError.rateLimited {
                // Backend rejected due to cooldown — roll back optimistic update
                await MainActor.run {
                    self?.estimate = rollbackEstimate
                    self?.reportSubmitted = false
                }
                Log.reports.notice("Report cooldown active for \(venueSnapshot.id, privacy: .public)")
            } catch {
                Log.reports.error("Report submission failed: \(error.localizedDescription)")
            }
        }
    }
}
