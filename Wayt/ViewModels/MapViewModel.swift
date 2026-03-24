import Combine
import Foundation
import MapKit
import os
import SwiftUI

@MainActor
final class MapViewModel: ObservableObject {

    // MARK: - Published State

    @Published var venues: [Venue] = []
    @Published var selectedVenue: Venue?
    @Published var searchText: String = ""
    @Published var isSearching: Bool = false
    @Published var showSearchThisArea: Bool = false
    @Published var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)

    /// Clustered map items for the current zoom level.
    @Published var mapItems: [VenueMapItem] = []

    /// The current visible region, used for clustering calculations.
    private var currentRegion: MKCoordinateRegion?

    // MARK: - Shared Filter

    var filterState: VenueFilterState? {
        didSet { observeFilter() }
    }

    private var filterCancellable: AnyCancellable?

    private func observeFilter() {
        guard let filterState else { return }
        filterCancellable = Publishers.Merge(
            filterState.$selectedCategory.map { _ in () },
            filterState.$selectedBusynessLevel.map { _ in () }
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            self?.recomputeClusters()
        }
    }

    /// Venues filtered by the shared category + busyness filters.
    var filteredVenues: [Venue] {
        filterState?.apply(to: venues) ?? venues
    }

    func toggleCategoryFilter(_ category: VenueCategory) {
        withAnimation(.easeInOut(duration: 0.2)) {
            filterState?.selectCategory(category)
        }
        // No explicit recomputeClusters() — the filterState observer handles it
    }

    /// Pending cluster recomputation (debounce during progressive loading).
    private var clusterDebounceTask: Task<Void, Never>?

    /// Recompute clusters from current venues and zoom level.
    /// When `debounce` is true, coalesces rapid calls (e.g. progressive loading batches).
    private func recomputeClusters(debounce: Bool = false) {
        if debounce {
            clusterDebounceTask?.cancel()
            clusterDebounceTask = Task {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                applyClustering()
            }
        } else {
            clusterDebounceTask?.cancel()
            applyClustering()
        }
    }

    private func applyClustering() {
        guard let region = currentRegion else {
            mapItems = filteredVenues.map { .single($0) }
            return
        }

        if VenueClusterer.shouldCluster(region: region) {
            mapItems = VenueClusterer.cluster(venues: filteredVenues, in: region)
        } else {
            mapItems = filteredVenues.map { .single($0) }
        }
    }

    // MARK: - Internal State

    private let searchService = VenueSearchService()
    private let busynessEngine = BusynessEngine.shared
    private let fusionService = FusionService.shared
    /// The region used for the most recent search (internal for testability).
    internal var lastSearchedRegion: MKCoordinateRegion?
    private var searchTask: Task<Void, Never>?
    private var refreshTimer: Task<Void, Never>?
    private var prefetchTask: Task<Void, Never>?
    private var followUpTask: Task<Void, Never>?

    /// Approximate search radius in meters, accounting for longitude compression at higher latitudes.
    private func searchRadius(for region: MKCoordinateRegion) -> Double {
        let latMeters = region.span.latitudeDelta * 111_000
        let lngMeters = region.span.longitudeDelta * 111_000 * cos(region.center.latitude * .pi / 180)
        return max(latMeters, lngMeters)
    }

    deinit {
        searchTask?.cancel()
        refreshTimer?.cancel()
        clusterDebounceTask?.cancel()
        expandTask?.cancel()
        prefetchTask?.cancel()
        followUpTask?.cancel()
    }

    // MARK: - Search Venues

    /// Search venues in the given region. Called on appear and when tapping "Search This Area".
    ///
    /// Two-phase approach for instant busyness colors:
    /// - Phase A: Fire area pre-fetch + MapKit concurrently. Venues appear colored
    ///   from the pre-fetched cache as each MapKit batch arrives.
    /// - Phase B: Identify venues with no cached busyness and compute them via a
    ///   single POST request. Update colors when the response arrives.
    func searchVenues(in region: MKCoordinateRegion) {
        let isInitialSearch = venues.isEmpty && lastSearchedRegion == nil
        searchTask?.cancel()
        expandTask?.cancel()
        followUpTask?.cancel()
        isExpandingSearch = false
        lastExpandedRegion = nil

        // User-initiated search — reset rate limiter so queries aren't silently skipped
        searchService.resetRateLimit()

        searchTask = Task {
            // Skip debounce on first launch for instant results
            if !isInitialSearch {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
            }

            isSearching = true
            showSearchThisArea = false

            let radius = searchRadius(for: region)
            Log.map.debug("Searching region: (\(region.center.latitude), \(region.center.longitude)) span: \(region.span.latitudeDelta)")

            do {
                // Phase A: Fire area pre-fetch concurrently with MapKit discovery.
                // The pre-fetch populates the fusion cache so onBatch can color venues instantly.
                async let prefetch: Void = fusionService.prefetchArea(
                    lat: region.center.latitude,
                    lng: region.center.longitude,
                    radius: radius
                )

                var results: [Venue]
                if searchText.isEmpty {
                    // Progressive loading: show venues as each query type completes
                    results = await searchService.searchAllTypes(region: region) { [weak self] partial in
                        guard let self, !Task.isCancelled else { return }
                        self.venues = self.applyOfflineBusyness(to: self.applyCachedEstimates(to: self.carryOverExistingBusyness(to: partial)))
                        self.recomputeClusters(debounce: true)
                        self.isSearching = false // stop spinner on first batch
                    }
                } else {
                    results = try await searchService.search(
                        query: searchText,
                        region: region
                    )
                }

                // Ensure pre-fetch completed before checking for uncached venues
                await prefetch

                guard !Task.isCancelled else { return }

                Log.map.info("Found \(results.count) venues")

                // Apply cached estimates from pre-fetch + carry-over + offline fallback
                results = carryOverExistingBusyness(to: results)
                results = applyCachedEstimates(to: results)
                results = applyOfflineBusyness(to: results)

                // Phase B: Dispatch uncached venues to backend (non-blocking).
                // The backend returns instantly and computes in the background.
                // We schedule a quick follow-up refresh to pick up results.
                let uncached = results.filter { $0.busynessConfidence == .none }
                if !uncached.isEmpty {
                    Log.map.info("\(uncached.count) venues uncached — dispatching to backend")
                    let uncachedInfos = uncached.map { VenueInfo(venue: $0) }
                    let capturedRegion = region
                    let capturedRadius = radius
                    // Fire-and-forget: send venues to backend for background computation
                    Task {
                        do {
                            // This returns instantly now (backend only returns cached + dispatches async)
                            let computed = try await fusionService.fetchMissingEstimates(
                                lat: capturedRegion.center.latitude,
                                lng: capturedRegion.center.longitude,
                                radius: capturedRadius,
                                venues: uncachedInfos
                            )
                            if !computed.isEmpty {
                                var updated = self.venues
                                self.applyFusedEstimates(computed, to: &updated)
                                self.venues = updated
                                self.recomputeClusters()
                            }
                        } catch {
                            Log.map.notice("Background dispatch failed: \(error.localizedDescription)")
                        }
                    }
                    // Schedule progressive follow-ups to pick up background results
                    scheduleProgressiveRefreshes(region: region)
                }

                // Update display immediately — don't wait for backend
                if !results.isEmpty {
                    venues = results
                    lastSearchedRegion = region
                    recomputeClusters()
                }
                Log.map.info("Loaded \(results.count) venues, \(self.filteredVenues.count) after filters, \(self.mapItems.count) map items")
            } catch {
                guard !Task.isCancelled else { return }
                Log.map.error("Search error: \(error.localizedDescription)")
            }

            isSearching = false
        }
    }

    /// Ensures an initial search has been triggered. Safe to call from any tab.
    /// Uses the provided region only if no search has happened yet.
    func ensureInitialSearch(region: MKCoordinateRegion) {
        guard venues.isEmpty, lastSearchedRegion == nil, searchTask == nil else { return }
        searchVenues(in: region)
    }

    /// Called when user pans/zooms the map
    func onRegionChanged(_ region: MKCoordinateRegion) {
        // Always update current region for clustering
        let previousRegion = currentRegion
        currentRegion = region

        // Recompute clusters if zoom changed meaningfully
        let zoomRatio: Double = {
            guard let prev = previousRegion, prev.span.latitudeDelta > 0 else { return 1.0 }
            return region.span.latitudeDelta / prev.span.latitudeDelta
        }()
        if zoomRatio > 1.3 || zoomRatio < (1.0 / 1.3) {
            recomputeClusters()
        }

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

            // Pre-fetch fusion data for the new area so it's cached
            // before the user taps "Search This Area"
            prefetchTask?.cancel()
            prefetchTask = Task {
                let radius = searchRadius(for: region)
                await fusionService.prefetchArea(
                    lat: region.center.latitude,
                    lng: region.center.longitude,
                    radius: radius
                )
            }
        }
    }

    /// Select a venue (tap on marker)
    func selectVenue(_ venue: Venue, heading: Double = 0, pitch: Double = 0) {
        selectedVenue = venue
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            cameraPosition = .camera(MapCamera(
                centerCoordinate: venue.coordinate,
                distance: 800,
                heading: heading,
                pitch: pitch
            ))
        }
    }

    /// Navigate to a coordinate (e.g. from a saved venue in Profile).
    /// Pans the camera and triggers a search in that area.
    func navigateToCoordinate(_ coordinate: CLLocationCoordinate2D) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            cameraPosition = .camera(MapCamera(
                centerCoordinate: coordinate,
                distance: 800,
                heading: 0,
                pitch: 0
            ))
        }
        let region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
        Task { searchVenues(in: region) }
    }

    /// Expand the search area to find more venues for Discover.
    /// Merges new results into existing venues without affecting the Map's search state.
    @Published var isExpandingSearch: Bool = false

    private var expandTask: Task<Void, Never>?
    /// Tracks the last expanded region so repeated taps keep widening.
    private var lastExpandedRegion: MKCoordinateRegion?

    /// Maximum expand span (~35 km at equator) to avoid runaway API costs.
    private static let maxExpandSpan: Double = 0.32

    func expandSearch() {
        guard !isExpandingSearch else { return }
        let base = lastExpandedRegion ?? lastSearchedRegion
        guard let base else { return }

        let newLatDelta = min(base.span.latitudeDelta * 2, Self.maxExpandSpan)
        let newLngDelta = min(base.span.longitudeDelta * 2, Self.maxExpandSpan)

        // Stop if already at max
        guard newLatDelta > base.span.latitudeDelta else { return }

        let expanded = MKCoordinateRegion(
            center: base.center,
            span: MKCoordinateSpan(
                latitudeDelta: newLatDelta,
                longitudeDelta: newLngDelta
            )
        )

        // User-initiated expand — reset rate limiter so queries aren't silently skipped
        searchService.resetRateLimit()

        expandTask?.cancel()
        expandTask = Task {
            isExpandingSearch = true

            let radius = searchRadius(for: expanded)

            // Pre-fetch fusion data for expanded area so cached estimates are available
            await fusionService.prefetchArea(
                lat: expanded.center.latitude,
                lng: expanded.center.longitude,
                radius: radius
            )

            let newResults = await searchService.searchAllTypes(region: expanded)

            guard !Task.isCancelled else {
                isExpandingSearch = false
                return
            }

            // Merge: keep existing venues, add new ones with busyness data
            let existingIDs = Set(venues.map(\.id))
            var additional = newResults.filter { !existingIDs.contains($0.id) }
            additional = applyCachedEstimates(to: additional)
            additional = applyOfflineBusyness(to: additional)

            if !additional.isEmpty {
                venues.append(contentsOf: additional)
                recomputeClusters()

                // Phase B: dispatch uncached expanded venues to backend
                let uncached = additional.filter { $0.busynessConfidence == .none }
                if !uncached.isEmpty {
                    let uncachedInfos = uncached.map { VenueInfo(venue: $0) }
                    Task {
                        do {
                            let computed = try await fusionService.fetchMissingEstimates(
                                lat: expanded.center.latitude,
                                lng: expanded.center.longitude,
                                radius: radius,
                                venues: uncachedInfos
                            )
                            if !computed.isEmpty {
                                var updated = self.venues
                                self.applyFusedEstimates(computed, to: &updated)
                                self.venues = updated
                                self.recomputeClusters()
                            }
                        } catch {
                            Log.map.notice("Expand dispatch failed: \(error.localizedDescription)")
                        }
                    }
                }
            }

            lastExpandedRegion = expanded
            isExpandingSearch = false
        }
    }

    /// Clear search text and selection
    func clearSearch(in region: MKCoordinateRegion) {
        searchText = ""
        selectedVenue = nil
        searchVenues(in: region)
    }

    /// Refresh busyness data after a report was submitted.
    /// Invalidates caches and re-applies busyness data to existing venues.
    func refreshAfterReport() {
        ReportService.shared.invalidateCache()
        fusionService.invalidateCache()
        guard let region = lastSearchedRegion else { return }
        Task {
            var updated = venues
            await overlayBusynessData(on: &updated, region: region)
            venues = updated
            recomputeClusters()
        }
    }

    // MARK: - Progressive Follow-Up Refreshes

    /// Schedule progressive follow-up refreshes after dispatching venues to background compute.
    /// Fires at 5s (warm phase), 15s (early cold), 45s (bulk cold).
    /// Exits early if all venues already have real data or the user navigated away.
    private func scheduleProgressiveRefreshes(region: MKCoordinateRegion) {
        // Cumulative delays from dispatch time; sleep the delta between each.
        // +2s catches batch-matched quick estimates, +5s catches warm venues, +12s final sweep.
        let cumulativeDelays = [2, 5, 12]
        followUpTask?.cancel()
        followUpTask = Task {
            var previous = 0
            for cumulative in cumulativeDelays {
                try? await Task.sleep(for: .seconds(cumulative - previous))
                previous = cumulative
                guard !Task.isCancelled else { return }
                guard !venues.isEmpty else { return }

                // Stop if all venues have at least some busyness data (quick-estimate or better)
                let needsRefresh = venues.contains { $0.busynessConfidence == .none }
                guard needsRefresh else {
                    Log.map.debug("Progressive refresh: all venues have real data, stopping")
                    return
                }

                Log.map.debug("Progressive refresh at +\(cumulative)s: fetching background results")
                fusionService.invalidateCache()

                var updated = venues
                await overlayBusynessData(on: &updated, region: region)
                venues = updated
                recomputeClusters()
            }
            Log.map.debug("Progressive refreshes complete")
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
                await overlayBusynessData(on: &updated, region: region)
                venues = updated
                recomputeClusters()
                Log.map.debug("Live refresh complete")
            }
        }
    }

    /// Stop the live refresh timer.
    func stopLiveRefresh() {
        refreshTimer?.cancel()
        refreshTimer = nil
    }

    // MARK: - Busyness Data Overlay

    /// Overlay busyness data onto venues: tries the v1 fusion endpoint first,
    /// then falls back to the legacy reports endpoint.
    private func overlayBusynessData(
        on venues: inout [Venue],
        region: MKCoordinateRegion
    ) async {
        let radius = searchRadius(for: region)

        // Try fusion service first
        do {
            let venueInfos = venues.map { VenueInfo(venue: $0) }
            let fused = try await fusionService.fetchNearbyEstimates(
                lat: region.center.latitude,
                lng: region.center.longitude,
                radius: radius,
                venues: venueInfos
            )
            applyFusedEstimates(fused, to: &venues)
            return
        } catch {
            Log.map.notice("Fusion unavailable, falling back to reports: \(error.localizedDescription)")
        }

        // Fallback: use legacy reports endpoint
        let summaries = await fetchReportSummaries(region: region)
        applyReports(summaries, to: &venues)
    }

    /// Apply fused estimates from the v1 fusion engine.
    private func applyFusedEstimates(
        _ estimates: [String: FusedEstimateResponse],
        to venues: inout [Venue]
    ) {
        guard !estimates.isEmpty else { return }
        for i in venues.indices {
            if let response = estimates[venues[i].id] {
                // Always apply Google Places hours (independent of crowd reports)
                venues[i].isOpen = response.isOpen ?? venues[i].isOpen
                venues[i].hoursToday = response.hoursToday ?? venues[i].hoursToday

                // Only apply busyness scores when real signal data exists
                guard (response.sourceCount ?? 0) > 0 else { continue }
                let estimate = busynessEngine.estimate(from: response)
                venues[i].busyness = estimate.level
                venues[i].busynessConfidence = estimate.confidence
                venues[i].reportCount = estimate.reportCount
                venues[i].estimatedWaitMinutes = estimate.waitMinutes
            }
        }
    }

    /// Fetch report summaries from legacy API. Returns empty dict on failure.
    private func fetchReportSummaries(
        region: MKCoordinateRegion
    ) async -> [String: VenueReportSummary] {
        do {
            return try await ReportService.shared.fetchNearbyReports(
                latitude: region.center.latitude,
                longitude: region.center.longitude,
                radiusMeters: searchRadius(for: region)
            )
        } catch {
            Log.map.notice("Reports unavailable: \(error.localizedDescription)")
            return [:]
        }
    }

    /// Apply offline busyness estimates to venues that have no report data.
    /// Uses the BusynessEngine offline fallback (neutral moderate / no confidence).
    /// Carry over busyness data from the currently-displayed venues so markers
    /// never flash grey when the same venue reappears from a fresh MapKit search.
    private func carryOverExistingBusyness(to newVenues: [Venue]) -> [Venue] {
        guard !venues.isEmpty else { return newVenues }
        let lookup = Dictionary(venues.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return newVenues.map { venue in
            guard venue.busyness == nil, let existing = lookup[venue.id],
                  existing.busyness != nil else { return venue }
            var v = venue
            v.busyness = existing.busyness
            v.busynessConfidence = existing.busynessConfidence
            v.reportCount = existing.reportCount
            v.estimatedWaitMinutes = existing.estimatedWaitMinutes
            v.isOpen = existing.isOpen
            v.hoursToday = existing.hoursToday
            return v
        }
    }

    /// Apply cached fusion estimates to venues before the network call completes.
    /// Eliminates the grey flash for venues we already have data for.
    private func applyCachedEstimates(to venues: [Venue]) -> [Venue] {
        venues.map { venue in
            guard venue.busyness == nil else { return venue }
            guard let cached = fusionService.cachedEstimate(for: venue.id) else { return venue }
            var v = venue
            let estimate = busynessEngine.estimate(from: cached)
            v.busyness = estimate.level
            v.busynessConfidence = estimate.confidence
            v.reportCount = estimate.reportCount
            v.estimatedWaitMinutes = estimate.waitMinutes
            v.isOpen = estimate.isOpen
            v.hoursToday = estimate.hoursToday
            return v
        }
    }

    private func applyOfflineBusyness(to venues: [Venue]) -> [Venue] {
        venues.map { venue in
            guard venue.busyness == nil else { return venue }
            var v = venue
            let estimate = busynessEngine.estimateOffline()
            v.busyness = estimate.level
            v.busynessConfidence = estimate.confidence
            return v
        }
    }

    /// Apply fetched report summaries onto venue array (legacy fallback).
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
                venues[i].estimatedWaitMinutes = summary.avgWaitMinutes
                venues[i].busynessConfidence = summary.reportCount >= AppConstants.highConfidenceReportCount
                    ? .high : .low
            }
        }
    }
}
