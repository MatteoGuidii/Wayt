import Foundation
import MapKit
import Combine
import UIKit

@MainActor
class VenueDiscoveryManager: ObservableObject {
    @Published var venues: [Venue] = []
    @Published var isSearching = false
    @Published var searchError: String?
    @Published var searchedRegion: MKCoordinateRegion?

    private var lastSearchLocation: CLLocation?
    private var lastSearchRadius: CLLocationDistance = AppConfiguration.Search.defaultSearchRadius
    private var lastSuccessfulLocation: CLLocation?

    /// Stores previous venues to merge with new results for persistence
    private var persistedVenues: [String: Venue] = [:]

    private let searchService = VenueSearchService()
    private let cacheManager = VenueCacheManager.shared
    private let imageService = VenueImageService.shared

    private var searchTask: Task<Void, Never>?

    /// Throttle region searches to prevent hitting Apple's rate limit
    private var lastRegionSearchTime: Date?
    private let regionSearchThrottleInterval: TimeInterval = 3.0

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

        let searchService = self.searchService
        let cacheManager = self.cacheManager
        let imageService = self.imageService
        let searchCenter = center
        let currentPersistedVenues = self.persistedVenues

        searchTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            // Debounce only for discovery mode
            if mode == .discovery {
                try? await Task.sleep(nanoseconds: AppConfiguration.Search.debounceDelayNanoseconds)
            }

            if Task.isCancelled { return }

            var currentRadius = radius
            var allFoundVenues: [Venue] = []
            var searchAttempt = 0
            let maxAttempts = mode == .discovery ? 2 : 1

            while searchAttempt < maxAttempts {
                searchAttempt += 1

                let searchRegion = MKCoordinateRegion(
                    center: searchCenter,
                    latitudinalMeters: currentRadius * 2,
                    longitudinalMeters: currentRadius * 2
                )

                await MainActor.run {
                    self.searchedRegion = searchRegion
                }

                let queries = await searchService.getQueries(for: searchText)

                // Use an actor to safely collect venues from concurrent tasks
                actor VenueCollector {
                    private var venues: [Venue] = []
                    private var seenVenueKeys: Set<String> = []

                    func add(_ newVenues: [(venue: Venue, key: String)]) {
                        for item in newVenues {
                            if !seenVenueKeys.contains(item.key) {
                                venues.append(item.venue)
                                seenVenueKeys.insert(item.key)
                            }
                        }
                    }

                    func getVenues() -> [Venue] {
                        return venues
                    }
                }

                let collector = VenueCollector()
                var throttleError: Error?

                await withTaskGroup(of: [(venue: Venue, key: String)].self) { group in
                    for query in queries {
                        group.addTask {
                            do {
                                let venues: [Venue]
                                if mode == .regionSearch {
                                    venues = try await searchService.search(query: query, region: searchRegion)
                                } else {
                                    venues = try await searchService.searchWithGrid(query: query, region: searchRegion)
                                }

                                return await MainActor.run {
                                    venues.map { venue in
                                        let key = "\(venue.name)_\(String(format: "%.5f", venue.coordinate.latitude))_\(String(format: "%.5f", venue.coordinate.longitude))"
                                        return (venue: venue, key: key)
                                    }
                                }
                            } catch let error as NSError {
                                if error.domain == "GEOErrorDomain" && error.code == -3 {
                                    throttleError = error
                                }
                                return []
                            } catch {
                                return []
                            }
                        }
                    }

                    for await venues in group {
                        await collector.add(venues)
                    }
                }

                // Handle throttle errors
                if let error = throttleError as? NSError,
                   let timeUntilReset = error.userInfo["timeUntilReset"] as? Int {
                    await MainActor.run {
                        self.searchError = "Search limit reached. Please wait \(timeUntilReset) seconds."
                        self.isSearching = false
                        Task {
                            try? await Task.sleep(nanoseconds: UInt64(timeUntilReset) * 1_000_000_000)
                            await MainActor.run {
                                if self.searchError?.contains("Search limit") == true {
                                    self.searchError = nil
                                }
                            }
                        }
                    }
                    return
                } else if throttleError != nil {
                    await MainActor.run {
                        self.searchError = "Search limit reached. Please wait a minute."
                        self.isSearching = false
                        Task {
                            try? await Task.sleep(nanoseconds: 60_000_000_000)
                            await MainActor.run {
                                if self.searchError?.contains("Search limit") == true {
                                    self.searchError = nil
                                }
                            }
                        }
                    }
                    return
                }

                if Task.isCancelled { return }

                allFoundVenues = await collector.getVenues()

                // Expand radius if too few results in discovery mode
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

            let userLocation = CLLocation(latitude: searchCenter.latitude, longitude: searchCenter.longitude)
            let effectiveRadius = currentRadius

            // Filter by text if searching
            var filteredVenues: [Venue]
            if !searchText.isEmpty {
                let searchLower = searchText.lowercased()
                filteredVenues = allFoundVenues.filter { venue in
                    venue.name.lowercased().contains(searchLower)
                }
                if filteredVenues.isEmpty {
                    filteredVenues = allFoundVenues
                }
            } else {
                filteredVenues = allFoundVenues
            }

            // Filter by distance and sort
            let venuesInRange = filteredVenues.filter { venue in
                let venueLoc = CLLocation(latitude: venue.coordinate.latitude, longitude: venue.coordinate.longitude)
                return venueLoc.distance(from: userLocation) <= effectiveRadius
            }

            let sortedVenues = venuesInRange.sorted { v1, v2 in
                let loc1 = CLLocation(latitude: v1.coordinate.latitude, longitude: v1.coordinate.longitude)
                let loc2 = CLLocation(latitude: v2.coordinate.latitude, longitude: v2.coordinate.longitude)
                return loc1.distance(from: userLocation) < loc2.distance(from: userLocation)
            }

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

            let shouldPersistResults = await MainActor.run { [weak self] () -> Bool in
                guard let self = self else { return false }
                defer { self.isSearching = false }

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

            // Cache venues
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

            // Fetch images
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
}

// MARK: - Helpers

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
