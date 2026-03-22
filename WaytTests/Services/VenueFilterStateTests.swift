import Testing
import Foundation
@testable import Wayt

@Suite("VenueFilterState")
@MainActor
struct VenueFilterStateTests {

    // MARK: - Initial State

    @Test("Starts with no category selected")
    func initialCategoryIsNil() {
        let state = VenueFilterState()
        #expect(state.selectedCategory == nil)
    }

    @Test("Starts with no busyness level selected")
    func initialBusynessIsNil() {
        let state = VenueFilterState()
        #expect(state.selectedBusynessLevel == nil)
    }

    // MARK: - selectCategory

    @Test("selectCategory sets the category")
    func selectCategorySets() {
        let state = VenueFilterState()
        state.selectCategory(.drinks)
        #expect(state.selectedCategory == .drinks)
    }

    @Test("selectCategory with same category toggles off")
    func selectCategoryTogglesOff() {
        let state = VenueFilterState()
        state.selectCategory(.drinks)
        state.selectCategory(.drinks)
        #expect(state.selectedCategory == nil)
    }

    @Test("selectCategory with different category switches")
    func selectCategorySwitches() {
        let state = VenueFilterState()
        state.selectCategory(.drinks)
        state.selectCategory(.food)
        #expect(state.selectedCategory == .food)
    }

    @Test("selectCategory with nil clears selection")
    func selectCategoryNilClears() {
        let state = VenueFilterState()
        state.selectCategory(.drinks)
        state.selectCategory(nil)
        #expect(state.selectedCategory == nil)
    }

    @Test("selectCategory nil when already nil stays nil")
    func selectCategoryNilWhenNilStaysNil() {
        let state = VenueFilterState()
        state.selectCategory(nil)
        #expect(state.selectedCategory == nil)
    }

    @Test("selectCategory cycles through all categories")
    func selectCategoryCyclesAll() {
        let state = VenueFilterState()
        for category in VenueCategory.allCases {
            state.selectCategory(category)
            #expect(state.selectedCategory == category)
        }
    }

    // MARK: - selectBusynessLevel

    @Test("selectBusynessLevel sets the level")
    func selectBusynessLevelSets() {
        let state = VenueFilterState()
        state.selectBusynessLevel(.busy)
        #expect(state.selectedBusynessLevel == .busy)
    }

    @Test("selectBusynessLevel with same level toggles off")
    func selectBusynessLevelTogglesOff() {
        let state = VenueFilterState()
        state.selectBusynessLevel(.busy)
        state.selectBusynessLevel(.busy)
        #expect(state.selectedBusynessLevel == nil)
    }

    @Test("selectBusynessLevel with different level switches")
    func selectBusynessLevelSwitches() {
        let state = VenueFilterState()
        state.selectBusynessLevel(.busy)
        state.selectBusynessLevel(.quiet)
        #expect(state.selectedBusynessLevel == .quiet)
    }

    @Test("selectBusynessLevel with nil clears selection")
    func selectBusynessLevelNilClears() {
        let state = VenueFilterState()
        state.selectBusynessLevel(.packed)
        state.selectBusynessLevel(nil)
        #expect(state.selectedBusynessLevel == nil)
    }

    @Test("selectBusynessLevel nil when already nil stays nil")
    func selectBusynessLevelNilWhenNilStaysNil() {
        let state = VenueFilterState()
        state.selectBusynessLevel(nil)
        #expect(state.selectedBusynessLevel == nil)
    }

    @Test("selectBusynessLevel cycles through all levels")
    func selectBusynessLevelCyclesAll() {
        let state = VenueFilterState()
        for level in BusynessLevel.allCases {
            state.selectBusynessLevel(level)
            #expect(state.selectedBusynessLevel == level)
        }
    }

    // MARK: - clearAll

    @Test("clearAll resets both filters")
    func clearAllResetsBoth() {
        let state = VenueFilterState()
        state.selectCategory(.nightlife)
        state.selectBusynessLevel(.packed)
        state.clearAll()
        #expect(state.selectedCategory == nil)
        #expect(state.selectedBusynessLevel == nil)
    }

    @Test("clearAll is safe when already cleared")
    func clearAllWhenAlreadyClear() {
        let state = VenueFilterState()
        state.clearAll()
        #expect(state.selectedCategory == nil)
        #expect(state.selectedBusynessLevel == nil)
    }

    @Test("clearAll only resets filters, not other state")
    func clearAllIdempotent() {
        let state = VenueFilterState()
        state.selectCategory(.food)
        state.clearAll()
        state.clearAll()
        #expect(state.selectedCategory == nil)
        #expect(state.selectedBusynessLevel == nil)
    }

    // MARK: - Independence

    @Test("Category and busyness filters are independent")
    func filtersAreIndependent() {
        let state = VenueFilterState()
        state.selectCategory(.drinks)
        state.selectBusynessLevel(.busy)
        #expect(state.selectedCategory == .drinks)
        #expect(state.selectedBusynessLevel == .busy)

        state.selectCategory(.drinks) // toggle off category
        #expect(state.selectedCategory == nil)
        #expect(state.selectedBusynessLevel == .busy) // busyness unchanged
    }

    @Test("Toggling busyness does not affect category")
    func busynessToggleDoesNotAffectCategory() {
        let state = VenueFilterState()
        state.selectCategory(.coffee)
        state.selectBusynessLevel(.packed)
        state.selectBusynessLevel(.packed) // toggle off
        #expect(state.selectedCategory == .coffee) // category unchanged
        #expect(state.selectedBusynessLevel == nil)
    }
}
