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
}
