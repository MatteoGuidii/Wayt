import Combine
import CoreLocation
import Foundation

@MainActor
final class DiscoverViewModel: ObservableObject {

    // MARK: - Published

    @Published var venues: [Venue] = []
    @Published var filteredVenues: [Venue] = []
    @Published var popularVenues: [Venue] = []
    @Published var sweetSpotVenues: [Venue] = []

    // MARK: - Discover-Only Filters

    @Published var openNowOnly: Bool = false
    @Published var ratingFilter: DiscoverRatingFilter?
    @Published var priceFilter: DiscoverPriceFilter?

    enum DiscoverRatingFilter: Double, CaseIterable {
        case threeHalf = 3.5
        case four      = 4.0
        case fourHalf  = 4.5

        var label: String {
            switch self {
            case .threeHalf: return "3.5+"
            case .four:      return "4+"
            case .fourHalf:  return "4.5+"
            }
        }
    }

    enum DiscoverPriceFilter: String, CaseIterable {
        case budget   // $
        case mid      // $$
        case upscale  // $$$+

        var label: String {
            switch self {
            case .budget:  return "$"
            case .mid:     return "$$"
            case .upscale: return "$$$+"
            }
        }

        func matches(priceLevel: String?) -> Bool {
            switch self {
            case .budget:
                return priceLevel == "PRICE_LEVEL_FREE" || priceLevel == "PRICE_LEVEL_INEXPENSIVE"
            case .mid:
                return priceLevel == "PRICE_LEVEL_MODERATE"
            case .upscale:
                return priceLevel == "PRICE_LEVEL_EXPENSIVE" || priceLevel == "PRICE_LEVEL_VERY_EXPENSIVE"
            }
        }
    }

    var hasActiveDiscoverFilters: Bool {
        openNowOnly || ratingFilter != nil || priceFilter != nil
    }

    func clearDiscoverFilters() {
        openNowOnly = false
        ratingFilter = nil
        priceFilter = nil
        applyFilter()
    }

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
            self?.applyFilter()
        }
    }

    // MARK: - Cached Derived State

    /// Count of nearby venues per busyness level (1–5) for the vibe pulse.
    /// Stored property — recomputed only when venues change, not on every view render.
    @Published private(set) var vibePulse: [Int: Int] = [1: 0, 2: 0, 3: 0, 4: 0, 5: 0]

    /// Count of venues per category.
    /// Stored property — recomputed only when venues change, not on every view render.
    @Published private(set) var categoryCounts: [VenueCategory: Int] = [:]

    /// Recompute cached derived state from the current venues array.
    /// VibePulse uses all venues (area mood). Category counts respect busyness filter
    /// so pill counts match what the user actually sees.
    private func recomputeDerivedState() {
        var pulse: [Int: Int] = [1: 0, 2: 0, 3: 0, 4: 0, 5: 0]
        for venue in venues {
            if let level = venue.busyness?.rawValue {
                pulse[level, default: 0] += 1
            }
        }
        vibePulse = pulse

        let base: [Venue]
        if let level = filterState?.selectedBusynessLevel {
            base = venues.filter { $0.busyness == level }
        } else {
            base = venues
        }
        categoryCounts = Dictionary(grouping: base, by: \.category).mapValues(\.count)
    }

    /// Dominant busyness level in the area
    var areaMood: BusynessLevel? {
        let withBusyness = venues.compactMap { $0.busyness }
        guard !withBusyness.isEmpty else { return nil }
        let avg = Double(withBusyness.map(\.rawValue).reduce(0, +)) / Double(withBusyness.count)
        return BusynessLevel(rawValue: Int(avg.rounded())) ?? .moderate
    }

    /// Time-of-day greeting
    var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "Good morning!"
        case 12..<17: return "Good afternoon!"
        case 17..<21: return "Good evening!"
        default:       return "Night owl?"
        }
    }

    /// Contextual subtitle based on time
    var greetingSubtitle: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<10:  return "Find a cozy coffee spot"
        case 10..<14: return "Where should we eat?"
        case 14..<17: return "Grab a bite or a drink"
        case 17..<21: return "Where to tonight?"
        default:       return "Still out? Let's find a spot"
        }
    }

    // MARK: - Update Venues (from MapViewModel)

    /// Last known location used for sorting — skip re-sort if user hasn't moved significantly.
    private var lastSortLocation: CLLocation?
    /// Venue IDs at the time of last sort — detect content changes without relying on first-element check.
    private var lastSortedVenueIDs: Set<String> = []

    /// Receives venues from the shared MapViewModel and sorts by distance.
    /// Skips the O(n log n) sort if venue set is unchanged AND user hasn't moved more than 50m.
    func updateVenues(_ newVenues: [Venue], userLocation: CLLocation?) {
        let newIDs = Set(newVenues.map(\.id))
        let venuesChanged = newIDs != lastSortedVenueIDs

        let needsSort: Bool = {
            guard let location = userLocation else { return false }
            if venuesChanged { return true }
            guard let lastLoc = lastSortLocation else { return true }
            return location.distance(from: lastLoc) > 50
        }()

        if needsSort, let location = userLocation {
            var sorted = newVenues
            sorted.sort { a, b in
                let locA = CLLocation(latitude: a.coordinate.latitude, longitude: a.coordinate.longitude)
                let locB = CLLocation(latitude: b.coordinate.latitude, longitude: b.coordinate.longitude)
                return location.distance(from: locA) < location.distance(from: locB)
            }
            venues = sorted
            lastSortLocation = location
            lastSortedVenueIDs = newIDs
        } else if venuesChanged {
            // Venue set changed but no location — use unsorted order
            venues = newVenues
            lastSortedVenueIDs = newIDs
        } else {
            // Same venue set, user hasn't moved — merge updated data while preserving sort order
            let updatedLookup = Dictionary(newVenues.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
            venues = venues.map { updatedLookup[$0.id] ?? $0 }
        }
        applyFilter()
    }

    // MARK: - Filter

    /// Public entry point for Discover-only filter changes.
    func applyFilterPublic() {
        applyFilter()
    }

    private func applyFilter() {
        recomputeDerivedState()

        // Apply shared filter logic (category + busyness)
        var base = filterState?.apply(to: venues) ?? venues

        // Apply Discover-only filters
        if openNowOnly {
            base = base.filter { $0.isOpen == true }
        }
        if let ratingFilter {
            base = base.filter { ($0.rating ?? 0) >= ratingFilter.rawValue }
        }
        if let priceFilter {
            base = base.filter { priceFilter.matches(priceLevel: $0.priceLevel) }
        }

        // Popular / buzzing: busyness >= 4 (busy + packed)
        popularVenues = base
            .filter { ($0.busyness?.rawValue ?? 0) >= 4 }
            .sorted { ($0.busyness?.rawValue ?? 0) > ($1.busyness?.rawValue ?? 0) }
            .prefix(10)
            .map { $0 }

        // Go Now picks: quiet or moderate (1–3) — comfortable, not dead
        sweetSpotVenues = base
            .filter {
                let level = $0.busyness?.rawValue ?? 0
                return level >= 1 && level <= 3
            }
            .prefix(8)
            .map { $0 }

        // Sort by rating when a rating filter is active
        if ratingFilter != nil {
            filteredVenues = base.sorted { ($0.rating ?? 0) > ($1.rating ?? 0) }
        } else {
            filteredVenues = base
        }
    }
}
