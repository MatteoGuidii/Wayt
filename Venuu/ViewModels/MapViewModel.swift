import Combine
import Foundation
import MapKit
import SwiftUI

@MainActor
final class MapViewModel: ObservableObject {

    // MARK: - Published State

    @Published var venues: [Venue] = []
    @Published var selectedVenue: Venue?
    @Published var searchText: String = ""
    @Published var isSearching: Bool = false
    @Published var showSearchThisArea: Bool = false
    @Published var errorMessage: String?
    @Published var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)

    // MARK: - Internal State

    private let searchService = VenueSearchService()
    private let busynessEngine = BusynessEngine.shared
    /// The region used for the most recent search (internal for testability).
    internal var lastSearchedRegion: MKCoordinateRegion?
    private var searchTask: Task<Void, Never>?
    private var refreshTimer: Task<Void, Never>?

    // MARK: - Search Venues

    /// Search venues in the given region. Called on appear and when tapping "Search This Area".
    func searchVenues(in region: MKCoordinateRegion) {
        let isInitialSearch = venues.isEmpty && lastSearchedRegion == nil
        searchTask?.cancel()
        searchTask = Task {
            // Skip debounce on first launch for instant results
            if !isInitialSearch {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
            }

            isSearching = true
            errorMessage = nil
            showSearchThisArea = false

            print("[MapViewModel] Searching region: \(region.center.latitude), \(region.center.longitude) span: \(region.span.latitudeDelta)")

            do {
                // Start report fetch in parallel with venue search
                async let reportsFuture = fetchReportSummaries(region: region)

                var results: [Venue]
                if searchText.isEmpty {
                    results = await searchService.searchAllTypes(region: region)
                } else {
                    results = try await searchService.search(
                        query: searchText,
                        region: region
                    )
                }

                guard !Task.isCancelled else { return }

                print("[MapViewModel] Found \(results.count) venues")

                // Overlay real reports (fetched in parallel)
                let summaries = await reportsFuture
                applyReports(summaries, to: &results)

                // For venues without reports, apply offline fallback
                results = results.map { venue in
                    guard venue.busyness == nil else { return venue }
                    var v = venue
                    let estimate = busynessEngine.estimateOffline()
                    v.busyness = estimate.level
                    v.busynessConfidence = estimate.confidence
                    return v
                }

                // Only update if we got results — keep stale venues visible if rate-limited
                if !results.isEmpty {
                    venues = results
                    lastSearchedRegion = region
                }
                print("[MapViewModel] Loaded \(results.count) venues with busyness")
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
                print("[MapViewModel] Search error: \(error.localizedDescription)")
            }

            isSearching = false
        }
    }

    /// Text-based search
    func performTextSearch(in region: MKCoordinateRegion) {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else {
            // Clear text → reload default venues
            searchVenues(in: region)
            return
        }
        searchVenues(in: region)
    }

    /// Called when user pans/zooms the map
    func onRegionChanged(_ region: MKCoordinateRegion) {
        guard let last = lastSearchedRegion else { return }

        // Check center movement
        let latDelta = abs(region.center.latitude - last.center.latitude)
        let lngDelta = abs(region.center.longitude - last.center.longitude)
        let centerMoved = latDelta > AppConstants.searchThisAreaThreshold
            || lngDelta > AppConstants.searchThisAreaThreshold

        // Check zoom change (span ratio > 1.5 means meaningful zoom in/out)
        let zoomChanged: Bool = {
            guard last.span.latitudeDelta > 0 else { return false }
            let ratio = region.span.latitudeDelta / last.span.latitudeDelta
            return ratio > 1.5 || ratio < (1.0 / 1.5)
        }()

        if (centerMoved || zoomChanged) && !isSearching {
            showSearchThisArea = true
        }
    }

    /// Select a venue (tap on marker)
    func selectVenue(_ venue: Venue) {
        selectedVenue = venue
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            cameraPosition = .camera(MapCamera(
                centerCoordinate: venue.coordinate,
                distance: 800,
                heading: 0,
                pitch: 0
            ))
        }
    }

    /// Clear search text and selection
    func clearSearch(in region: MKCoordinateRegion) {
        searchText = ""
        selectedVenue = nil
        searchVenues(in: region)
    }

    /// Refresh busyness data after a report was submitted.
    /// Invalidates the report cache and re-applies reports to existing venues.
    func refreshAfterReport() {
        ReportService.shared.invalidateCache()
        guard let region = lastSearchedRegion else { return }
        Task {
            var updated = venues
            await overlayReports(on: &updated, region: region)
            venues = updated
        }
    }

    // MARK: - Live Refresh

    /// Start periodic background refresh of busyness data (every 60s).
    /// Only refreshes report overlay — doesn't re-search MapKit.
    func startLiveRefresh() {
        // Prevent duplicate timers if .task re-fires on tab return
        guard refreshTimer == nil else { return }
        refreshTimer = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(AppConstants.liveRefreshInterval))
                guard !Task.isCancelled else { break }

                // Skip refresh if app is backgrounded (saves battery + data)
                guard UIApplication.shared.applicationState == .active else { continue }
                guard !venues.isEmpty, let region = lastSearchedRegion else { continue }

                // Let cache TTL handle staleness — no manual invalidation needed
                var updated = venues
                await overlayReports(on: &updated, region: region)
                venues = updated
                print("[MapViewModel] Live refresh complete")
            }
        }
    }

    /// Stop the live refresh timer.
    func stopLiveRefresh() {
        refreshTimer?.cancel()
        refreshTimer = nil
    }

    // MARK: - Report Overlay

    /// Fetch report summaries from API. Returns empty dict on failure.
    private func fetchReportSummaries(
        region: MKCoordinateRegion
    ) async -> [String: VenueReportSummary] {
        do {
            return try await ReportService.shared.fetchNearbyReports(
                latitude: region.center.latitude,
                longitude: region.center.longitude,
                radiusMeters: region.span.latitudeDelta * 111_000
            )
        } catch {
            print("[MapViewModel] Reports unavailable: \(error.localizedDescription)")
            return [:]
        }
    }

    /// Apply fetched report summaries onto venue array.
    private func applyReports(
        _ summaries: [String: VenueReportSummary],
        to venues: inout [Venue]
    ) {
        guard !summaries.isEmpty else { return }
        for i in venues.indices {
            if let summary = summaries[venues[i].id] {
                let level = BusynessLevel(closestTo: summary.avgBusyness)
                venues[i].busyness = level
                venues[i].reportCount = summary.reportCount
                venues[i].lastReportedAt = summary.lastReportedAt
                venues[i].estimatedWaitMinutes = summary.avgWaitMinutes
                venues[i].busynessConfidence = summary.reportCount >= AppConstants.highConfidenceReportCount
                    ? .high : .low
            }
        }
    }

    /// Fetch real reports from API and overlay on venues.
    private func overlayReports(
        on venues: inout [Venue],
        region: MKCoordinateRegion
    ) async {
        let summaries = await fetchReportSummaries(region: region)
        applyReports(summaries, to: &venues)
    }
}
