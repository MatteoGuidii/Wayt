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
    @Published var popularVenues: [Venue] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    // MARK: - Private

    private let searchService = VenueSearchService()
    private let busynessEngine = BusynessEngine.shared

    // MARK: - Load Venues

    func loadVenues(near location: CLLocation?) async {
        guard let location else { return }
        isLoading = true
        errorMessage = nil

        let region = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: AppConstants.defaultSearchRadius * 2,
            longitudinalMeters: AppConstants.defaultSearchRadius * 2
        )

        var results = await searchService.searchAllTypes(region: region)

        // Apply offline fallback for venues without report data
        results = results.map { venue in
            guard venue.busyness == nil else { return venue }
            var v = venue
            let estimate = busynessEngine.estimateOffline()
            v.busyness = estimate.level
            v.busynessConfidence = estimate.confidence
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

    private func updateDerivedState() {
        applyFilter()
        popularVenues = venues
            .filter { ($0.busyness?.rawValue ?? 0) >= 3 }
            .sorted { ($0.busyness?.rawValue ?? 0) > ($1.busyness?.rawValue ?? 0) }
            .prefix(10)
            .map { $0 }
    }

    private func applyFilter() {
        if let category = selectedCategory {
            filteredVenues = venues.filter { $0.category == category }
        } else {
            filteredVenues = venues
        }
    }
}
