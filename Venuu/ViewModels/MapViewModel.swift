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
    private var lastSearchedRegion: MKCoordinateRegion?
    private var searchTask: Task<Void, Never>?
    private var refreshTimer: Task<Void, Never>?

    // MARK: - Search Venues

    /// Search venues in the given region. Called on appear and when tapping "Search This Area".
    func searchVenues(in region: MKCoordinateRegion) {
        searchTask?.cancel()
        searchTask = Task {
            isSearching = true
            errorMessage = nil
            showSearchThisArea = false

            print("[MapViewModel] Searching region: \(region.center.latitude), \(region.center.longitude) span: \(region.span.latitudeDelta)")

            do {
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

                // Apply busyness heuristics to each venue
                results = results.map { venue in
                    var v = venue
                    let estimate = busynessEngine.estimate(venueType: v.type)
                    v.busyness = estimate.level
                    v.busynessConfidence = estimate.confidence
                    return v
                }

                // Try to overlay real reports from the API
                await overlayReports(on: &results, region: region)

                venues = results
                lastSearchedRegion = region
                print("[MapViewModel] Loaded \(venues.count) venues with busyness")
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
        let latDelta = abs(region.center.latitude - last.center.latitude)
        let lngDelta = abs(region.center.longitude - last.center.longitude)

        if latDelta > AppConstants.searchThiAreaThreshold
            || lngDelta > AppConstants.searchThiAreaThreshold {
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
        refreshTimer?.cancel()
        refreshTimer = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(AppConstants.liveRefreshInterval))
                guard !Task.isCancelled, !venues.isEmpty, let region = lastSearchedRegion else { continue }

                // Invalidate cache so we get fresh data
                ReportService.shared.invalidateCache()
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

    /// Fetch real reports from API and overlay on venues.
    /// Fails silently if API is unavailable (heuristics are the fallback).
    private func overlayReports(
        on venues: inout [Venue],
        region: MKCoordinateRegion
    ) async {
        do {
            let summaries = try await ReportService.shared.fetchNearbyReports(
                latitude: region.center.latitude,
                longitude: region.center.longitude,
                radiusMeters: region.span.latitudeDelta * 111_000 // rough degrees→meters
            )

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
        } catch {
            // API not available — heuristics already applied, this is fine
            print("[MapViewModel] Reports unavailable: \(error.localizedDescription)")
        }
    }
}
