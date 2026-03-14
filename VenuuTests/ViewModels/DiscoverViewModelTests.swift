import Testing
import Foundation
@testable import Venuu

@Suite("DiscoverViewModel")
@MainActor
struct DiscoverViewModelTests {

    // MARK: - Category Filtering

    @Test("selectCategory filters to matching type only")
    func selectCategoryFiltersToType() {
        let vm = DiscoverViewModel()
        vm.venues = [
            TestFactories.makeVenue(name: "Bar One",   type: .bar),
            TestFactories.makeVenue(name: "Bar Two",   type: .bar),
            TestFactories.makeVenue(name: "Restaurant", type: .restaurant)
        ]
        vm.selectCategory(.bar)
        #expect(vm.filteredVenues.count == 2)
        #expect(vm.filteredVenues.allSatisfy { $0.type == .bar })
    }

    @Test("selectCategory nil shows all venues")
    func selectCategoryNilShowsAll() {
        let vm = DiscoverViewModel()
        vm.venues = [
            TestFactories.makeVenue(name: "Bar",        type: .bar),
            TestFactories.makeVenue(name: "Cafe",       type: .cafe),
            TestFactories.makeVenue(name: "Restaurant", type: .restaurant)
        ]
        vm.selectCategory(.bar)
        vm.selectCategory(nil)
        #expect(vm.filteredVenues.count == 3)
    }

    @Test("selectCategory updates selectedCategory property")
    func selectCategoryUpdatesProp() {
        let vm = DiscoverViewModel()
        vm.selectCategory(.cafe)
        #expect(vm.selectedCategory == .cafe)
        vm.selectCategory(nil)
        #expect(vm.selectedCategory == nil)
    }

    @Test("Filtering by type with no matching venues returns empty")
    func filterWithNoMatchReturnsEmpty() {
        let vm = DiscoverViewModel()
        vm.venues = [TestFactories.makeVenue(name: "Bar", type: .bar)]
        vm.selectCategory(.club)
        #expect(vm.filteredVenues.isEmpty)
    }

    // MARK: - popularVenues

    @Test("popularVenues only includes venues with busyness >= 3")
    func popularVenuesThresholdIsThree() {
        let vm = DiscoverViewModel()
        vm.venues = [
            TestFactories.makeVenue(name: "Quiet",    busyness: .quiet),    // 2 — excluded
            TestFactories.makeVenue(name: "Moderate", busyness: .moderate), // 3 — included
            TestFactories.makeVenue(name: "Busy",     busyness: .busy),     // 4 — included
            TestFactories.makeVenue(name: "Packed",   busyness: .packed),   // 5 — included
            TestFactories.makeVenue(name: "Empty",    busyness: .empty)     // 1 — excluded
        ]
        #expect(vm.popularVenues.count == 3)
        #expect(vm.popularVenues.allSatisfy { ($0.busyness?.rawValue ?? 0) >= 3 })
    }

    @Test("popularVenues is sorted by busyness descending")
    func popularVenuesSortedDescending() {
        let vm = DiscoverViewModel()
        vm.venues = [
            TestFactories.makeVenue(name: "Moderate", busyness: .moderate), // 3
            TestFactories.makeVenue(name: "Packed",   busyness: .packed),   // 5
            TestFactories.makeVenue(name: "Busy",     busyness: .busy)      // 4
        ]
        let popular = vm.popularVenues
        #expect(popular.count == 3)
        #expect(popular[0].busyness == .packed)
        #expect(popular[1].busyness == .busy)
        #expect(popular[2].busyness == .moderate)
    }

    @Test("popularVenues excludes venues with nil busyness")
    func popularVenuesExcludesNilBusyness() {
        let vm = DiscoverViewModel()
        vm.venues = [
            TestFactories.makeVenue(name: "NoBusyness", busyness: nil),
            TestFactories.makeVenue(name: "Busy",       busyness: .busy)
        ]
        #expect(vm.popularVenues.count == 1)
        #expect(vm.popularVenues[0].busyness == .busy)
    }

    @Test("popularVenues is empty when venues array is empty")
    func popularVenuesEmptyWhenNoVenues() {
        let vm = DiscoverViewModel()
        vm.venues = []
        #expect(vm.popularVenues.isEmpty)
    }

    @Test("filteredVenues is empty when venues array is empty")
    func filteredVenuesEmptyWhenNoVenues() {
        let vm = DiscoverViewModel()
        vm.venues = []
        vm.selectCategory(nil)
        #expect(vm.filteredVenues.isEmpty)
    }

    // MARK: - Initial State

    @Test("ViewModel starts with empty venues and no selected category")
    func initialState() {
        let vm = DiscoverViewModel()
        #expect(vm.venues.isEmpty)
        #expect(vm.filteredVenues.isEmpty)
        #expect(vm.selectedCategory == nil)
        #expect(vm.isLoading == false)
        #expect(vm.errorMessage == nil)
    }
}
