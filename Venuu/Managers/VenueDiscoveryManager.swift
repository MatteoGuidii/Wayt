import Foundation
import MapKit
import Combine
import UIKit

/// Manages venue discovery with tiered queries, spatial caching, and relevance scoring
@MainActor
class VenueDiscoveryManager: ObservableObject {

    // MARK: - Published State

    @Published var venues: [Venue] = []
    @Published var isSearching = false
    @Published var searchError: String?
    @Published var searchedRegion: MKCoordinateRegion?
    @Published var loadingState: LoadingState = .idle

    // MARK: - Loading State

    enum LoadingState: Equatable {
        case idle
        case loadingFromCache
        case loadingPrimary(progress: Double)
        case loadingSecondary(progress: Double)
        case complete
        case error(String)
    }

    // MARK: - Private State

    private var lastSearchLocation: CLLocation?
    private var lastSearchRadius: CLLocationDistance = AppConfiguration.Search.defaultSearchRadius
    private var lastSuccessfulLocation: CLLocation?

    /// Stores previous venues to merge with new results for persistence
    private var persistedVenues: [String: Venue] = [:]

    // MARK: - Dependencies

    private let searchService = VenueSearchService()
    private let cacheManager = VenueCacheManager.shared
    private let imageService = VenueImageService.shared
    private let queryExecutor = QueryExecutor()
    private let spatialCache = SpatialVenueCache()

    private var searchTask: Task<Void, Never>?

    /// Throttle region searches to prevent hitting Apple's rate limit
    private var lastRegionSearchTime: Date?
    private let regionSearchThrottleInterval: TimeInterval = 3.0

    // MARK: - Initialization

    init() {
        // Load cached venues on startup
        Task {
            let cached = await cacheManager.loadVenues()
            if !cached.isEmpty {
                self.venues = cached
                for venue in cached {
                    let key = venueKey(for: venue)
                    persistedVenues[key] = venue
                }
            }
        }
    }

    // MARK: - Public API

    /// Triggers a search around the user's location if they have moved significantly
    func updateUserLocation(_ location: CLLocation, radius: CLLocationDistance? = nil) {
        guard !isSearching else { return }

        let searchRadius = radius ?? AppConfiguration.Search.defaultSearchRadius

        guard let lastLocation = lastSearchLocation else {
            performSearch(near: location.coordinate, radius: searchRadius, mode: .discovery)
            lastSearchLocation = location
            lastSearchRadius = searchRadius
            return
        }

        let distance = location.distance(from: lastLocation)
        let radiusRatio = abs(searchRadius - lastSearchRadius) / lastSearchRadius

        if distance > AppConfiguration.Search.minimumDistanceForNewSearch ||
           radiusRatio > AppConfiguration.Search.minimumRadiusChangeRatio {
            performSearch(near: location.coordinate, radius: searchRadius, mode: .discovery)
            lastSearchLocation = location
            lastSearchRadius = searchRadius
        }
    }

    /// Performs a search with a specific query (e.g. from search bar)
    func search(text: String) {
        guard let location = lastSearchLocation else { return }
        let searchRadius = AppConfiguration.Search.textSearchRadius
        performSearch(near: location.coordinate, searchText: text, radius: searchRadius, mode: .textSearch)
    }

    /// Search a specific region (for "Search This Area" functionality)
    func searchRegion(_ region: MKCoordinateRegion) {
        let now = Date()
        if let lastSearch = lastRegionSearchTime {
            let timeSinceLastSearch = now.timeIntervalSince(lastSearch)
            if timeSinceLastSearch < regionSearchThrottleInterval {
                let waitTime = Int(ceil(regionSearchThrottleInterval - timeSinceLastSearch))
                searchError = "Please wait \(waitTime) second\(waitTime == 1 ? "" : "s") before searching again"
                Task {
                    try? await Task.sleep(nanoseconds: UInt64(waitTime) * 1_000_000_000)
                    await MainActor.run {
                        if self.searchError?.contains("Please wait") == true {
                            self.searchError = nil
                        }
                    }
                }
                return
            }
        }

        lastRegionSearchTime = now
        searchError = nil

        let radius = region.span.toRadius()
        performSearch(near: region.center, radius: radius, mode: .regionSearch)
        lastSearchLocation = CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)
        lastSearchRadius = radius
    }

    /// Clears text search and returns to discovery mode
    func clearSearch() {
        guard let location = lastSearchLocation else { return }
        performSearch(near: location.coordinate, radius: lastSearchRadius, mode: .discovery)
    }

    // MARK: - Private

    private enum SearchMode {
        case discovery
        case textSearch
        case regionSearch
    }

    private func venueKey(for venue: Venue) -> String {
        "\(venue.name)_\(String(format: "%.5f", venue.coordinate.latitude))_\(String(format: "%.5f", venue.coordinate.longitude))"
    }

    private func performSearch(
        near center: CLLocationCoordinate2D,
        searchText: String = "",
        radius: CLLocationDistance,
        mode: SearchMode
    ) {
        searchTask?.cancel()
        isSearching = true
        loadingState = .loadingFromCache

        let searchService = self.searchService
        let cacheManager = self.cacheManager
        let imageService = self.imageService
        let queryExecutor = self.queryExecutor
        let spatialCache = self.spatialCache
        let searchCenter = center
        let currentPersistedVenues = self.persistedVenues

        searchTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            // Debounce only for discovery mode
            if mode == .discovery {
                try? await Task.sleep(nanoseconds: AppConfiguration.Search.debounceDelayNanoseconds)
            }

            if Task.isCancelled { return }

            let searchRegion = MKCoordinateRegion(
                center: searchCenter,
                latitudinalMeters: radius * 2,
                longitudinalMeters: radius * 2
            )

            await MainActor.run {
                self.searchedRegion = searchRegion
            }

            // Step 1: Check spatial cache for immediate display
            if let cachedVenues = await spatialCache.getVenues(in: searchRegion), !cachedVenues.isEmpty {
                await MainActor.run {
                    self.venues = cachedVenues
                    self.loadingState = .loadingPrimary(progress: 0.1)
                }
            }

            if Task.isCancelled { return }

            // Step 2: Execute primary queries
            var allFoundVenues: [Venue] = []
            var currentRadius = radius
            let maxAttempts = mode == .discovery ? 2 : 1
            var searchAttempt = 0

            while searchAttempt < maxAttempts {
                searchAttempt += 1

                let expandedRegion = MKCoordinateRegion(
                    center: searchCenter,
                    latitudinalMeters: currentRadius * 2,
                    longitudinalMeters: currentRadius * 2
                )

                // Get queries based on mode
                let primaryQueries: [String]
                if !searchText.isEmpty {
                    primaryQueries = [searchText]
                } else {
                    primaryQueries = searchService.getInitialQueries()
                }

                do {
                    let primaryVenues = try await queryExecutor.execute(
                        queries: primaryQueries,
                        in: expandedRegion,
                        priority: .high,
                        useGrid: true
                    )
                    allFoundVenues.append(contentsOf: primaryVenues)

                    await MainActor.run {
                        self.loadingState = .loadingPrimary(progress: 0.5)
                    }
                } catch {
                    await self.handleSearchError(error)
                    if Task.isCancelled { return }
                }

                if Task.isCancelled { return }

                // Step 3: Execute secondary queries if needed (discovery mode only)
                if mode == .discovery && searchText.isEmpty &&
                   allFoundVenues.count < VenueQueryConfiguration.secondaryThreshold {

                    await MainActor.run {
                        self.loadingState = .loadingSecondary(progress: 0.6)
                    }

                    do {
                        let secondaryVenues = try await queryExecutor.execute(
                            queries: searchService.getSecondaryQueries(),
                            in: expandedRegion,
                            priority: .normal,
                            useGrid: true
                        )
                        allFoundVenues.append(contentsOf: secondaryVenues)

                        await MainActor.run {
                            self.loadingState = .loadingSecondary(progress: 0.8)
                        }
                    } catch {
                        // Secondary query failure is non-critical
                    }
                }

                if Task.isCancelled { return }

                // Check if we need to expand radius
                if mode == .discovery &&
                   allFoundVenues.count < AppConfiguration.Search.minVenuesBeforeExpansion &&
                   currentRadius < AppConfiguration.Search.maxSearchRadius {
                    currentRadius = min(
                        currentRadius * AppConfiguration.Search.radiusExpansionMultiplier,
                        AppConfiguration.Search.maxSearchRadius
                    )
                } else {
                    break
                }
            }

            if Task.isCancelled { return }

            // Deduplicate venues
            let deduplicatedVenues = await self.deduplicateVenues(allFoundVenues)

            // Step 4: Store in spatial cache
            await spatialCache.storeVenues(
                deduplicatedVenues,
                for: searchRegion,
                queryTerms: Set(searchText.isEmpty ? VenueQueryConfiguration.primaryQueries : [searchText])
            )

            // Step 5: Filter and sort
            let userLocation = CLLocation(latitude: searchCenter.latitude, longitude: searchCenter.longitude)
            let effectiveRadius = currentRadius

            // Filter by text if searching
            var filteredVenues: [Venue]
            if !searchText.isEmpty {
                let searchLower = searchText.lowercased()
                filteredVenues = deduplicatedVenues.filter { venue in
                    venue.name.lowercased().contains(searchLower)
                }
                if filteredVenues.isEmpty {
                    filteredVenues = deduplicatedVenues
                }
            } else {
                filteredVenues = deduplicatedVenues
            }

            // Filter by distance
            let venuesInRange = filteredVenues.filter { venue in
                let venueLoc = CLLocation(latitude: venue.coordinate.latitude, longitude: venue.coordinate.longitude)
                return venueLoc.distance(from: userLocation) <= effectiveRadius
            }

            // Step 6: Apply hybrid relevance scoring
            let scorer = searchText.isEmpty ? VenueRelevanceScorer.discovery : VenueRelevanceScorer.textSearch
            let sortedVenues = scorer.sortByDistanceThenRelevance(
                venues: venuesInRange,
                userLocation: userLocation,
                searchQuery: searchText.isEmpty ? nil : searchText,
                maxDistance: effectiveRadius
            )

            var limitedVenues = Array(sortedVenues.prefix(AppConfiguration.Search.maxResultCount))

            // Merge with persisted venues in discovery mode
            if mode == .discovery && !currentPersistedVenues.isEmpty {
                let existingKeys = Set(limitedVenues.map { venue in
                    "\(venue.name)_\(String(format: "%.5f", venue.coordinate.latitude))_\(String(format: "%.5f", venue.coordinate.longitude))"
                })

                for (key, venue) in currentPersistedVenues {
                    if !existingKeys.contains(key) {
                        let venueLoc = CLLocation(latitude: venue.coordinate.latitude, longitude: venue.coordinate.longitude)
                        let distance = venueLoc.distance(from: userLocation)
                        if distance <= effectiveRadius * 1.5 {
                            limitedVenues.append(venue)
                        }
                    }
                }

                limitedVenues = Array(limitedVenues.prefix(AppConfiguration.Search.maxResultCount))
            }

            // Step 7: Update UI
            let shouldPersistResults = await MainActor.run { [weak self] () -> Bool in
                guard let self = self else { return false }
                defer {
                    self.isSearching = false
                    self.loadingState = .complete
                }

                guard !limitedVenues.isEmpty else {
                    self.lastSuccessfulLocation = nil
                    return false
                }

                self.venues = limitedVenues

                for venue in limitedVenues {
                    let key = self.venueKey(for: venue)
                    self.persistedVenues[key] = venue
                }

                // Limit persisted venue cache size
                if self.persistedVenues.count > 500 {
                    let keysToRemove = Array(self.persistedVenues.keys.prefix(self.persistedVenues.count - 500))
                    for key in keysToRemove {
                        self.persistedVenues.removeValue(forKey: key)
                    }
                }

                self.lastSuccessfulLocation = userLocation
                return true
            }

            guard shouldPersistResults else { return }
            if Task.isCancelled { return }

            // Step 8: Cache venues to disk
            let cachedVenues = await MainActor.run {
                limitedVenues.map { venue in
                    VenueCacheManager.CachedVenue(
                        id: venue.id,
                        name: venue.name,
                        latitude: venue.coordinate.latitude,
                        longitude: venue.coordinate.longitude,
                        categoryRawValue: venue.category?.rawValue,
                        imageData: nil
                    )
                }
            }

            do {
                try await cacheManager.saveVenues(cachedVenues)
                try await cacheManager.saveImages(for: limitedVenues)
            } catch {
                // Cache save failures are non-critical
            }

            if Task.isCancelled { return }

            // Step 9: Fetch images
            await imageService.fetchImages(for: limitedVenues) { [weak self] id, image in
                Task { @MainActor in
                    guard let self = self else { return }
                    if let index = self.venues.firstIndex(where: { $0.id == id }) {
                        self.venues[index].image = image
                    }
                    for (key, var venue) in self.persistedVenues {
                        if venue.id == id {
                            venue.image = image
                            self.persistedVenues[key] = venue
                            break
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func deduplicateVenues(_ venues: [Venue]) -> [Venue] {
        var seen = Set<String>()
        var unique: [Venue] = []

        for venue in venues {
            let key = venueKey(for: venue)
            if !seen.contains(key) {
                seen.insert(key)
                unique.append(venue)
            }
        }

        return unique
    }

    private func handleSearchError(_ error: Error) async {
        if let queryError = error as? QueryExecutorError {
            await MainActor.run {
                switch queryError {
                case .rateLimited(let retryAfter):
                    self.searchError = "Search limit reached. Please wait \(Int(retryAfter)) seconds."
                    Task {
                        try? await Task.sleep(nanoseconds: UInt64(retryAfter) * 1_000_000_000)
                        await MainActor.run {
                            if self.searchError?.contains("Search limit") == true {
                                self.searchError = nil
                            }
                        }
                    }
                }
            }
        } else if let nsError = error as NSError?,
                  nsError.domain == "GEOErrorDomain" && nsError.code == -3 {
            await MainActor.run {
                self.searchError = "Search limit reached. Please wait a minute."
                Task {
                    try? await Task.sleep(nanoseconds: 60_000_000_000)
                    await MainActor.run {
                        if self.searchError?.contains("Search limit") == true {
                            self.searchError = nil
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Helpers

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
