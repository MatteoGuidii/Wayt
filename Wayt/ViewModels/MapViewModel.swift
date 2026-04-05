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
    /// True when any venue detail sheet is open (Map or Discover).
    @Published var venueSheetOpen = false
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
    private var reportCancellable: AnyCancellable?

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

    // MARK: - Init

    init() {
        reportCancellable = NotificationCenter.default.publisher(for: .reportSubmitted)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                let venueId = notification.object as? String
                let reportedLevel = (notification.userInfo?["busynessLevel"] as? Int)
                    .flatMap { BusynessLevel(rawValue: $0) }
                let waitMinutes = notification.userInfo?["waitMinutes"] as? Int
                self?.refreshAfterReport(venueId: venueId, reportedLevel: reportedLevel, waitMinutes: waitMinutes)
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
    private var lastFullRefreshDate: Date = .distantPast
    private var hoursTransitionTask: Task<Void, Never>?
    private var prefetchTask: Task<Void, Never>?
    private var followUpTask: Task<Void, Never>?
    private var reportRefreshTask: Task<Void, Never>?
    /// Protects a venue's optimistic level after a report until fusion confirms it (sourceCount >= 2) or 30s expires.
    private var reportProtection: (venueId: String, expiry: Date)?

    /// Approximate search radius in meters, accounting for longitude compression at higher latitudes.
    private func searchRadius(for region: MKCoordinateRegion) -> Double {
        let latMeters = region.span.latitudeDelta * 111_000
        let lngMeters = region.span.longitudeDelta * 111_000 * cos(region.center.latitude * .pi / 180)
        return max(latMeters, lngMeters)
    }

    deinit {
        searchTask?.cancel()
        refreshTimer?.cancel()
        hoursTransitionTask?.cancel()
        clusterDebounceTask?.cancel()
        expandTask?.cancel()
        prefetchTask?.cancel()
        followUpTask?.cancel()
        reportRefreshTask?.cancel()
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
        isSearching = false
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
                // Phase A: Fire area pre-fetch in background — populates the fusion
                // cache so progressive refreshes can color venues without blocking.
                // When the prefetch returns, immediately apply cached estimates to any
                // venues already on screen (colors first MapKit batches faster).
                Task { [weak self, fusionService] in
                    await fusionService.prefetchArea(
                        lat: region.center.latitude,
                        lng: region.center.longitude,
                        radius: radius
                    )
                    guard let self, !Task.isCancelled else { return }
                    let uncached = self.venues.filter { $0.busynessConfidence == .none }
                    guard !uncached.isEmpty else { return }
                    var updated = self.venues
                    for i in updated.indices where updated[i].busynessConfidence == .none {
                        if let cached = fusionService.cachedEstimate(for: updated[i].id) {
                            let estimate = self.busynessEngine.estimate(from: cached)
                            updated[i].busyness = estimate.level
                            updated[i].busynessConfidence = estimate.confidence
                            updated[i].reportCount = estimate.reportCount
                            updated[i].estimatedWaitMinutes = estimate.waitMinutes
                            updated[i].isOpen = estimate.isOpen ?? updated[i].isOpen
                            updated[i].hoursToday = estimate.hoursToday ?? updated[i].hoursToday
                            updated[i].businessStatus = estimate.businessStatus ?? updated[i].businessStatus
                            if let details = cached.venueDetails {
                                updated[i].rating = details.rating
                                updated[i].userRatingCount = details.userRatingCount
                                updated[i].priceLevel = details.priceLevel
                                updated[i].priceRange = details.priceRange
                                updated[i].primaryTypeDisplayName = details.primaryTypeDisplayName
                            }
                        }
                    }
                    self.venues = updated
                    self.recomputeClusters()
                    Log.map.debug("Prefetch applied cached estimates to early batches")
                }

                var results: [Venue]
                if searchText.isEmpty {
                    // Progressive loading: merge new venues as each query type completes
                    results = await searchService.searchAllTypes(region: region) { [weak self] partial in
                        guard let self, !Task.isCancelled else { return }
                        // Merge: append only genuinely new venues (like expandSearch)
                        let existingIDs = Set(self.venues.map(\.id))
                        let newVenues = partial.filter { !existingIDs.contains($0.id) }
                        if !newVenues.isEmpty {
                            let withBusyness = self.applyAllBusynessData(to: newVenues)
                            self.venues.append(contentsOf: withBusyness)
                            self.recomputeClusters(debounce: true)
                        }
                        self.isSearching = false // stop spinner on first batch
                    }
                } else {
                    results = try await searchService.search(
                        query: searchText,
                        region: region
                    )
                }

                guard !Task.isCancelled else { return }

                Log.map.info("Found \(results.count) venues")

                // Apply all busyness data in a single pass (carry-over + cached + offline fallback)
                results = applyAllBusynessData(to: results)

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

                // Merge final results: keep existing in-region venues, add new ones
                if !results.isEmpty {
                    let newResultIDs = Set(results.map(\.id))
                    // Retain existing venues still within the new search region
                    var merged = venues.filter { venue in
                        newResultIDs.contains(venue.id) || region.containsWithBuffer(venue.coordinate)
                    }
                    // Add genuinely new results not already present
                    let mergedIDs = Set(merged.map(\.id))
                    let additional = results.filter { !mergedIDs.contains($0.id) }
                    merged.append(contentsOf: additional)

                    // Sort by distance from region center, cap at limit
                    let center = CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)
                    merged.sort { a, b in
                        let distA = center.distance(from: CLLocation(latitude: a.coordinate.latitude, longitude: a.coordinate.longitude))
                        let distB = center.distance(from: CLLocation(latitude: b.coordinate.latitude, longitude: b.coordinate.longitude))
                        return distA < distB
                    }
                    if merged.count > AppConstants.maxVisibleVenues {
                        merged = Array(merged.prefix(AppConstants.maxVisibleVenues))
                    }

                    venues = applyAllBusynessData(to: merged)
                    lastSearchedRegion = region
                    lastExpandedRegion = nil
                    recomputeClusters()
                    scheduleHoursTransitionRefresh()
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

    /// Sync a fresher busyness estimate from the detail sheet back to the map venue.
    /// Prevents the map marker color from being stale while the detail shows current data.
    func syncBusynessFromDetail(venueId: String, estimate: BusynessEstimate) {
        guard let idx = venues.firstIndex(where: { $0.id == venueId }),
              venues[idx].busyness != estimate.level else { return }
        venues[idx].busyness = estimate.level
        venues[idx].busynessConfidence = estimate.confidence
        venues[idx].reportCount = estimate.reportCount
        venues[idx].estimatedWaitMinutes = estimate.waitMinutes
        recomputeClusters()
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

    /// Navigate to a saved venue — preserves existing venues and ensures
    /// the target is present, then animates to it.
    func navigateToSavedVenue(_ savedVenue: SavedVenue) {
        let venue = Venue(savedVenue: savedVenue)

        if !venues.contains(where: { $0.id == venue.id }) {
            venues.insert(venue, at: 0)
        }
        recomputeClusters()
        selectedVenue = venue
        showSearchThisArea = true

        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            cameraPosition = .camera(MapCamera(
                centerCoordinate: savedVenue.coordinate,
                distance: 800,
                heading: 0,
                pitch: 0
            ))
        }
    }

    /// Navigate to a venue from a report history entry — same behavior as saved venues.
    func navigateToReportVenue(_ entry: ReportHistoryEntry) {
        let venue = Venue(reportEntry: entry)

        if !venues.contains(where: { $0.id == venue.id }) {
            venues.insert(venue, at: 0)
        }
        recomputeClusters()
        selectedVenue = venue
        showSearchThisArea = true

        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            cameraPosition = .camera(MapCamera(
                centerCoordinate: entry.coordinate,
                distance: 800,
                heading: 0,
                pitch: 0
            ))
        }
    }

    /// Expand the search area to find more venues for Discover.
    /// Merges new results into existing venues without affecting the Map's search state.
    @Published var isExpandingSearch: Bool = false

    private var expandTask: Task<Void, Never>?
    /// Tracks the last expanded region so repeated taps keep widening.
    private var lastExpandedRegion: MKCoordinateRegion?

    /// Whether the expand radius has reached the walking cap.
    var isAtMaxExpand: Bool {
        guard let region = lastExpandedRegion ?? lastSearchedRegion else { return false }
        let maxLatSpan = (AppConstants.maxWalkingRadius * 2) / 111_000
        return region.span.latitudeDelta >= maxLatSpan - 0.0001
    }

    func expandSearch() {
        guard !isSearching, !isExpandingSearch else { return }
        let base = lastExpandedRegion ?? lastSearchedRegion
        guard let base else { return }

        // Expand outward by a fixed increment each tap.
        // Deep-searching the same region with more keywords yields diminishing
        // returns — MapKit returns the same top-25 venues regardless of keyword.
        // A larger region is the only reliable way to find more venues.
        let incrementDeg = AppConstants.expandIncrement / 111_000
        let maxLatSpan = (AppConstants.maxWalkingRadius * 2) / 111_000
        let maxLngSpan = maxLatSpan / cos(base.center.latitude * .pi / 180)
        let newLatDelta = min(base.span.latitudeDelta + incrementDeg, maxLatSpan)
        let newLngDelta = min(base.span.longitudeDelta + incrementDeg, maxLngSpan)

        guard newLatDelta > base.span.latitudeDelta + 0.0001 else { return }

        let expanded = MKCoordinateRegion(
            center: base.center,
            span: MKCoordinateSpan(
                latitudeDelta: newLatDelta,
                longitudeDelta: newLngDelta
            )
        )

        searchService.resetRateLimit()
        searchService.invalidateCache()

        expandTask?.cancel()
        expandTask = Task {
            isExpandingSearch = true

            let radius = searchRadius(for: expanded)

            // Prefetch fusion data for the expanded area
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

            let existingIDs = Set(venues.map(\.id))
            var additional = newResults.filter { !existingIDs.contains($0.id) }
            additional = applyAllBusynessData(to: additional)

            let capacity = AppConstants.maxVisibleVenues - venues.count
            if additional.count > capacity {
                additional = Array(additional.prefix(max(0, capacity)))
            }

            if !additional.isEmpty {
                venues.append(contentsOf: additional)
                recomputeClusters()

                // Dispatch uncached venues for backend busyness computation
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
            Log.map.info("Expand found \(additional.count) new venues, total \(self.venues.count)")
        }
    }

    /// Clear search text and selection
    func clearSearch(in region: MKCoordinateRegion) {
        searchText = ""
        selectedVenue = nil
        searchVenues(in: region)
    }

    /// Refresh busyness data after a report: optimistic local update, then delayed
    /// retries at +5s/+10s to catch the backend's recomputed fused estimate.
    /// The optimistic level is preserved until fusion confirms the report was indexed.
    func refreshAfterReport(venueId: String? = nil, reportedLevel: BusynessLevel? = nil, waitMinutes: Int? = nil) {
        reportRefreshTask?.cancel()
        followUpTask?.cancel() // Prevent progressive refreshes from racing

        // Optimistic: immediately reflect the reported level on the map marker.
        // Set protection so no code path overwrites it until fusion confirms.
        if let venueId, let level = reportedLevel,
           let idx = venues.firstIndex(where: { $0.id == venueId }) {
            var v = venues[idx]
            v.busyness = level
            v.busynessConfidence = .low
            v.estimatedWaitMinutes = waitMinutes
            venues[idx] = v
            recomputeClusters()
            reportProtection = (venueId: venueId, expiry: Date().addingTimeInterval(30))
        }

        ReportService.shared.invalidateCache()
        if let venueId {
            fusionService.invalidateCacheForVenue(venueId)
        } else {
            fusionService.invalidateCache()
        }

        guard let region = lastSearchedRegion, let venueId else { return }

        // Delayed retries — reportProtection guards the optimistic level in
        // applyFusedEstimates, so stale fetches from other code paths are safe.
        reportRefreshTask = Task {
            let radius = searchRadius(for: region)

            for delay in [5, 5] {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                guard let venue = venues.first(where: { $0.id == venueId }) else { return }

                do {
                    let estimates = try await fusionService.fetchMissingEstimates(
                        lat: region.center.latitude,
                        lng: region.center.longitude,
                        radius: radius,
                        venues: [VenueInfo(venue: venue)]
                    )

                    var updated = venues
                    applyFusedEstimates(estimates, to: &updated)
                    venues = updated
                    recomputeClusters()

                    if reportProtection == nil {
                        Log.map.info("Report picked up by fusion for \(venueId, privacy: .public)")
                        return
                    }
                } catch {
                    Log.map.notice("Report retry fetch failed: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Clear all caches and map state on sign-out so the next user
    /// starts with a clean slate.
    func resetForSignOut() {
        searchTask?.cancel()
        expandTask?.cancel()
        refreshTimer?.cancel()
        followUpTask?.cancel()
        prefetchTask?.cancel()
        hoursTransitionTask?.cancel()
        clusterDebounceTask?.cancel()
        reportRefreshTask?.cancel()

        searchService.invalidateCache()
        searchService.resetRateLimit()
        filterState?.clearAll()
        venues = []
        mapItems = []
        selectedVenue = nil
        searchText = ""
        showSearchThisArea = false
        lastSearchedRegion = nil
    }

    // MARK: - Progressive Follow-Up Refreshes

    /// Schedule progressive follow-up refreshes after dispatching venues to background compute.
    /// Only fetches data for venues still missing busyness (`.none` confidence),
    /// avoiding redundant re-sends of already-colored venues.
    /// Timing aligned to backend processing phases:
    /// +3s catches Phase 1 batch-matched quick estimates,
    /// +7s catches Phase 2 warm venues, +14s final sweep for cold venues.
    private func scheduleProgressiveRefreshes(region: MKCoordinateRegion) {
        let cumulativeDelays = [3, 7, 14]
        let radius = searchRadius(for: region)
        followUpTask?.cancel()
        followUpTask = Task {
            var previous = 0
            for cumulative in cumulativeDelays {
                try? await Task.sleep(for: .seconds(cumulative - previous))
                previous = cumulative
                guard !Task.isCancelled else { return }
                guard !venues.isEmpty else { return }

                // Only fetch venues still missing busyness data
                let uncached = venues.filter { $0.busynessConfidence == .none }
                guard !uncached.isEmpty else {
                    Log.map.debug("Progressive refresh: all venues have real data, stopping")
                    return
                }

                Log.map.debug("Progressive refresh at +\(cumulative)s: \(uncached.count) venues still need data")
                let uncachedInfos = uncached.map { VenueInfo(venue: $0) }
                do {
                    let computed = try await fusionService.fetchMissingEstimates(
                        lat: region.center.latitude,
                        lng: region.center.longitude,
                        radius: radius,
                        venues: uncachedInfos
                    )
                    if !computed.isEmpty {
                        var updated = venues
                        applyFusedEstimates(computed, to: &updated)
                        venues = updated
                        recomputeClusters()
                    }
                } catch {
                    Log.map.notice("Progressive refresh failed: \(error.localizedDescription)")
                }
            }
            Log.map.debug("Progressive refreshes complete")
        }
    }

    // MARK: - Live Refresh

    func startLiveRefresh() {
        // Prevent duplicate timers if .task re-fires on tab return
        guard refreshTimer == nil else { return }
        refreshTimer = Task {
            while !Task.isCancelled {
                let interval = fusionService.secondsUntilNextRefresh()
                    .map { max(AppConstants.minAdaptiveRefreshInterval, min(AppConstants.maxAdaptiveRefreshInterval, $0)) }
                    ?? AppConstants.liveRefreshInterval

                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { break }

                // Skip refresh if app is backgrounded (saves battery + data)
                guard UIApplication.shared.applicationState == .active else { continue }
                guard !venues.isEmpty, let region = lastSearchedRegion else { continue }

                // Invalidate cache if any venue's hours transition has passed
                if hasHoursTransitionOccurred() {
                    fusionService.invalidateCache()
                }

                let timeSinceFullRefresh = Date().timeIntervalSince(lastFullRefreshDate)
                if timeSinceFullRefresh >= AppConstants.liveRefreshInterval {
                    var updated = venues
                    await overlayBusynessData(on: &updated, region: region)
                    venues = updated
                    recomputeClusters()
                    lastFullRefreshDate = Date()
                } else if interval < AppConstants.maxAdaptiveRefreshInterval {
                    await refreshActiveVenues(region: region)
                }
                scheduleHoursTransitionRefresh()
                Log.map.debug("Live refresh complete (interval: \(interval)s)")
            }
        }
    }

    // Avoids re-fetching all 50+ venues when only 1-2 have active reports.
    private func refreshActiveVenues(region: MKCoordinateRegion) async {
        let staleVenueIds = Set(fusionService.venueIdsNeedingRefresh())
        guard !staleVenueIds.isEmpty else { return }

        let staleVenues = venues.filter { staleVenueIds.contains($0.id) }
        guard !staleVenues.isEmpty else { return }

        let venueInfos = staleVenues.map { VenueInfo(venue: $0) }
        do {
            let refreshed = try await fusionService.fetchMissingEstimates(
                lat: region.center.latitude,
                lng: region.center.longitude,
                radius: searchRadius(for: region),
                venues: venueInfos
            )
            if !refreshed.isEmpty {
                var updated = venues
                applyFusedEstimates(refreshed, to: &updated)
                venues = updated
                recomputeClusters()
            }
        } catch {
            Log.map.notice("Active venue refresh failed: \(error.localizedDescription)")
        }
    }

    /// Stop the live refresh timer.
    func stopLiveRefresh() {
        refreshTimer?.cancel()
        refreshTimer = nil
        hoursTransitionTask?.cancel()
        hoursTransitionTask = nil
    }

    // MARK: - Hours Transition Refresh

    /// Check if any venue's opening/closing transition has passed since we last
    /// fetched data, meaning the cached `isOpen` is likely stale.
    private func hasHoursTransitionOccurred() -> Bool {
        let now = Date()
        for venue in venues {
            guard let hoursToday = venue.hoursToday else { continue }
            guard let transitionTime = parseTransitionTime(from: hoursToday, isOpen: venue.isOpen) else { continue }
            // Transition is in the past (already happened) and within the last refresh window
            if transitionTime <= now && now.timeIntervalSince(transitionTime) < AppConstants.liveRefreshInterval + 30 {
                return true
            }
        }
        return false
    }

    /// Schedule a one-shot refresh at the next venue hours transition (open→closed or closed→open).
    /// This ensures the UI updates within seconds of a venue opening or closing.
    private func scheduleHoursTransitionRefresh() {
        hoursTransitionTask?.cancel()

        let now = Date()
        var earliest: Date?

        for venue in venues {
            guard let hoursToday = venue.hoursToday else { continue }
            guard let transitionTime = parseTransitionTime(from: hoursToday, isOpen: venue.isOpen) else { continue }
            // Only care about upcoming transitions within the next hour
            guard transitionTime > now, transitionTime.timeIntervalSince(now) < 3600 else { continue }
            if earliest == nil || transitionTime < earliest! {
                earliest = transitionTime
            }
        }

        guard let target = earliest else { return }
        // Add a small buffer so the backend has time to reflect the change
        let delay = target.timeIntervalSince(now) + 5

        Log.map.debug("Hours transition scheduled in \(Int(delay))s")
        hoursTransitionTask = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            guard UIApplication.shared.applicationState == .active else { return }
            guard !venues.isEmpty, let region = lastSearchedRegion else { return }

            fusionService.invalidateCache()
            var updated = venues
            await overlayBusynessData(on: &updated, region: region)
            venues = updated
            recomputeClusters()
            Log.map.debug("Hours transition refresh complete")
        }
    }

    /// Parse the next open/close transition time from a `hoursToday` string.
    ///
    /// Recognized formats:
    /// - "Opens 11:00 AM" → venue is closed, transition at 11:00 AM
    /// - "Closes 10:00 PM" → venue is open, transition at 10:00 PM
    /// - "11:00 AM – 10:00 PM" → uses `isOpen` to pick opening or closing time
    private func parseTransitionTime(from hoursToday: String, isOpen: Bool?) -> Date? {
        let calendar = Calendar.current
        let now = Date()

        // "Opens 11:00 AM" or "Closes 10:00 PM"
        if let range = hoursToday.range(of: #"^(Opens|Closes)\s+"#, options: .regularExpression) {
            let timeStr = String(hoursToday[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            return todayDate(from: timeStr, calendar: calendar, now: now)
        }

        // "11:00 AM – 10:00 PM" (en-dash or hyphen)
        let parts = hoursToday.components(separatedBy: CharacterSet(charactersIn: "–-"))
        if parts.count == 2 {
            let openStr = parts[0].trimmingCharacters(in: .whitespaces)
            let closeStr = parts[1].trimmingCharacters(in: .whitespaces)
            // If currently closed, next transition is opening; if open, it's closing
            let target = (isOpen == true) ? closeStr : openStr
            return todayDate(from: target, calendar: calendar, now: now)
        }

        return nil
    }

    private static let hoursFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "h:mm a"
        return f
    }()

    private func todayDate(from timeString: String, calendar: Calendar, now: Date) -> Date? {
        guard let parsed = Self.hoursFormatter.date(from: timeString) else { return nil }
        let timeComponents = calendar.dateComponents([.hour, .minute], from: parsed)
        var todayComponents = calendar.dateComponents([.year, .month, .day], from: now)
        todayComponents.hour = timeComponents.hour
        todayComponents.minute = timeComponents.minute
        return calendar.date(from: todayComponents)
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
                // Always apply Google Places hours and status (independent of crowd reports)
                venues[i].isOpen = response.isOpen ?? venues[i].isOpen
                venues[i].hoursToday = response.hoursToday ?? venues[i].hoursToday
                venues[i].businessStatus = response.businessStatus ?? venues[i].businessStatus

                // Always apply venue details (independent of crowd reports)
                if let details = response.venueDetails {
                    venues[i].rating = details.rating ?? venues[i].rating
                    venues[i].userRatingCount = details.userRatingCount ?? venues[i].userRatingCount
                    venues[i].priceLevel = details.priceLevel ?? venues[i].priceLevel
                    venues[i].priceRange = details.priceRange ?? venues[i].priceRange
                    venues[i].primaryTypeDisplayName = details.primaryTypeDisplayName ?? venues[i].primaryTypeDisplayName
                }

                // Only apply busyness scores when real signal data exists
                guard (response.sourceCount ?? 0) > 0 else { continue }

                // Protect optimistic level after report until fusion includes it
                if let protection = reportProtection,
                   protection.venueId == venues[i].id,
                   Date() < protection.expiry {
                    if (response.sourceCount ?? 0) >= 2 {
                        reportProtection = nil
                    } else {
                        continue
                    }
                }

                let estimate = busynessEngine.estimate(from: response)
                venues[i].busyness = estimate.level
                venues[i].busynessConfidence = estimate.confidence
                venues[i].reportCount = estimate.reportCount
                venues[i].estimatedWaitMinutes = estimate.waitMinutes
            }
        }

        // Remove permanently closed venues (confirmed gone by Google Places)
        venues.removeAll { $0.businessStatus == "CLOSED_PERMANENTLY" }
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

    /// Single-pass busyness pipeline: applies existing carry-over, cached fusion estimates,
    /// and offline fallback in one iteration instead of three separate array copies.
    private func applyAllBusynessData(to newVenues: [Venue]) -> [Venue] {
        let existingLookup: [String: Venue]? = venues.isEmpty ? nil : Dictionary(
            venues.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }
        )

        return newVenues.map { venue in
            guard venue.busyness == nil else { return venue }
            var v = venue

            // Priority 1: Carry over from existing displayed venues (prevents grey flash)
            if let existing = existingLookup?[venue.id], existing.busyness != nil {
                v.busyness = existing.busyness
                v.busynessConfidence = existing.busynessConfidence
                v.reportCount = existing.reportCount
                v.estimatedWaitMinutes = existing.estimatedWaitMinutes
                v.isOpen = existing.isOpen
                v.hoursToday = existing.hoursToday
                v.businessStatus = existing.businessStatus
                v.rating = existing.rating
                v.userRatingCount = existing.userRatingCount
                v.priceLevel = existing.priceLevel
                v.priceRange = existing.priceRange
                v.primaryTypeDisplayName = existing.primaryTypeDisplayName
                return v
            }

            // Priority 2: Apply cached fusion estimates
            if let cached = fusionService.cachedEstimate(for: venue.id) {
                let estimate = busynessEngine.estimate(from: cached)
                v.busyness = estimate.level
                v.busynessConfidence = estimate.confidence
                v.reportCount = estimate.reportCount
                v.estimatedWaitMinutes = estimate.waitMinutes
                v.isOpen = estimate.isOpen ?? v.isOpen
                v.hoursToday = estimate.hoursToday ?? v.hoursToday
                v.businessStatus = estimate.businessStatus ?? v.businessStatus
                if let details = cached.venueDetails {
                    v.rating = details.rating
                    v.userRatingCount = details.userRatingCount
                    v.priceLevel = details.priceLevel
                    v.priceRange = details.priceRange
                    v.primaryTypeDisplayName = details.primaryTypeDisplayName
                }
                return v
            }

            // Priority 3: Offline fallback (neutral moderate / no confidence)
            let estimate = busynessEngine.estimateOffline()
            v.busyness = estimate.level
            v.busynessConfidence = estimate.confidence
            return v
        }
    }

    // Keep individual methods for backward compatibility in expandSearch path
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
            v.isOpen = estimate.isOpen ?? v.isOpen
            v.hoursToday = estimate.hoursToday ?? v.hoursToday
            v.businessStatus = estimate.businessStatus ?? v.businessStatus
            if let details = cached.venueDetails {
                v.rating = details.rating
                v.userRatingCount = details.userRatingCount
                v.priceLevel = details.priceLevel
                v.priceRange = details.priceRange
                v.primaryTypeDisplayName = details.primaryTypeDisplayName
            }
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
