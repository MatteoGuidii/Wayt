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

    // MARK: - Computed

    /// Count of nearby venues per busyness level (1–5) for the vibe pulse
    var vibePulse: [Int: Int] {
        var counts: [Int: Int] = [:]
        for level in 1...5 { counts[level] = 0 }
        for venue in venues {
            if let level = venue.busyness?.rawValue {
                counts[level, default: 0] += 1
            }
        }
        return counts
    }

    /// Count of venues per category
    var categoryCounts: [VenueCategory: Int] {
        Dictionary(grouping: venues, by: \.category)
            .mapValues(\.count)
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

    /// Receives venues from the shared MapViewModel and sorts by distance.
    func updateVenues(_ newVenues: [Venue], userLocation: CLLocation?) {
        var sorted = newVenues
        if let location = userLocation {
            sorted.sort { a, b in
                let locA = CLLocation(latitude: a.coordinate.latitude, longitude: a.coordinate.longitude)
                let locB = CLLocation(latitude: b.coordinate.latitude, longitude: b.coordinate.longitude)
                return location.distance(from: locA) < location.distance(from: locB)
            }
        }
        venues = sorted
        applyFilter()
    }

    // MARK: - Filter

    private func applyFilter() {
        // Apply shared filter logic (category + busyness)
        let base = filterState?.apply(to: venues) ?? venues

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

        filteredVenues = base
    }
}
