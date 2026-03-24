import Combine
import SwiftUI

/// Shared filter state synced between Discover and Map tabs.
@MainActor
final class VenueFilterState: ObservableObject {

    @Published var selectedCategory: VenueCategory?
    @Published var selectedBusynessLevel: BusynessLevel?

    func selectCategory(_ category: VenueCategory?) {
        if selectedCategory == category {
            selectedCategory = nil
        } else {
            selectedCategory = category
        }
    }

    func selectBusynessLevel(_ level: BusynessLevel?) {
        if selectedBusynessLevel == level {
            selectedBusynessLevel = nil
        } else {
            selectedBusynessLevel = level
        }
    }

    func clearAll() {
        selectedCategory = nil
        selectedBusynessLevel = nil
    }

    /// Apply active filters to a venue list. Shared between Map and Discover.
    func apply(to venues: [Venue]) -> [Venue] {
        var result = venues
        if let category = selectedCategory {
            result = result.filter { $0.category == category }
        }
        if let level = selectedBusynessLevel {
            result = result.filter { $0.busyness == level }
        }
        return result
    }
}
