import Combine
import Foundation
import MapKit
import CoreLocation

@MainActor
final class DiscoverViewModel: ObservableObject {

    // MARK: - Published

    @Published var venues: [Venue] = [] {
        didSet { updateDerivedState() }
    }
    @Published var filteredVenues: [Venue] = []
    @Published var selectedCategory: VenueCategory?
    @Published var selectedBusynessLevel: BusynessLevel?
    @Published var popularVenues: [Venue] = []
    @Published var sweetSpotVenues: [Venue] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil

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

    // MARK: - Private

    private let searchService = VenueSearchService()
    private let busynessEngine = BusynessEngine.shared

    // MARK: - Load Venues

    func loadVenues(near location: CLLocation?) async {
        guard let location else { return }
        isLoading = true

        let region = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: AppConstants.defaultSearchRadius * 2,
            longitudinalMeters: AppConstants.defaultSearchRadius * 2
        )

        var results = await searchService.searchAllTypes(region: region)

        // ⚠️ TEST ONLY — REMOVE BEFORE PRODUCTION
        // Assigns random busyness levels for UI testing.
        // Revert to: busynessEngine.estimateOffline() fallback for venues with nil busyness.
        results = results.map { venue in
            var v = venue
            v.busyness = BusynessLevel.allCases.randomElement() ?? .moderate
            v.busynessConfidence = .estimated
            return v
        }

        // Sort by distance from user
        results.sort { a, b in
            let locA = CLLocation(latitude: a.coordinate.latitude, longitude: a.coordinate.longitude)
            let locB = CLLocation(latitude: b.coordinate.latitude, longitude: b.coordinate.longitude)
            return location.distance(from: locA) < location.distance(from: locB)
        }

        venues = results
        isLoading = false
    }

    // MARK: - Filter

    func selectCategory(_ category: VenueCategory?) {
        selectedCategory = category
        applyFilter()
    }

    func selectBusynessLevel(_ level: BusynessLevel?) {
        if selectedBusynessLevel == level {
            selectedBusynessLevel = nil
        } else {
            selectedBusynessLevel = level
        }
        applyFilter()
    }

    private func updateDerivedState() {
        applyFilter()
    }

    private func applyFilter() {
        // Base set: apply category filter if active
        var base = venues
        if let category = selectedCategory {
            base = base.filter { $0.category == category }
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

        // Filtered venues: apply both category + busyness filter
        if let level = selectedBusynessLevel {
            base = base.filter { $0.busyness == level }
        }

        filteredVenues = base
    }
}
