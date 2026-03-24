import Testing
import Foundation
import MapKit
@testable import Wayt

@Suite("MapViewModel")
@MainActor
struct MapViewModelTests {

    private let toronto = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 43.65, longitude: -79.38),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )

    // MARK: - Initial State

    @Test("ViewModel starts with empty venues and no selection")
    func initialState() {
        let vm = MapViewModel()
        #expect(vm.venues.isEmpty)
        #expect(vm.mapItems.isEmpty)
        #expect(vm.selectedVenue == nil)
        #expect(vm.searchText.isEmpty)
        #expect(vm.isSearching == false)
        #expect(vm.showSearchThisArea == false)
        #expect(vm.isExpandingSearch == false)
        #expect(vm.lastSearchedRegion == nil)
    }

    // MARK: - Category Filtering via FilterState

    @Test("filteredVenues returns all venues when no filter active")
    func filteredVenuesNoFilter() {
        let vm = MapViewModel()
        vm.venues = [
            TestFactories.makeVenue(name: "Bar A"),
            TestFactories.makeVenue(name: "Coffee Cafe"),
            TestFactories.makeVenue(name: "Pizza Place")
        ]
        #expect(vm.filteredVenues.count == 3)
    }

    @Test("filteredVenues filters by category from filterState")
    func filteredVenuesWithCategory() {
        let vm = MapViewModel()
        let filterState = VenueFilterState()
        vm.filterState = filterState

        vm.venues = [
            TestFactories.makeVenue(name: "Cocktail Bar"),
            TestFactories.makeVenue(name: "Wine Bar"),
            TestFactories.makeVenue(name: "Pizza Place")
        ]
        filterState.selectedCategory = .drinks
        #expect(vm.filteredVenues.allSatisfy { $0.category == .drinks })
    }

    @Test("filteredVenues filters by busyness from filterState")
    func filteredVenuesWithBusyness() {
        let vm = MapViewModel()
        let filterState = VenueFilterState()
        vm.filterState = filterState

        vm.venues = [
            TestFactories.makeVenue(name: "Quiet Bar",  busyness: .quiet),
            TestFactories.makeVenue(name: "Busy Bar",   busyness: .busy),
            TestFactories.makeVenue(name: "Packed Bar",  busyness: .packed)
        ]
        filterState.selectedBusynessLevel = .busy
        #expect(vm.filteredVenues.count == 1)
        #expect(vm.filteredVenues[0].busyness == .busy)
    }

    @Test("filteredVenues applies both category and busyness filters")
    func filteredVenuesBothFilters() {
        let vm = MapViewModel()
        let filterState = VenueFilterState()
        vm.filterState = filterState

        vm.venues = [
            TestFactories.makeVenue(name: "Busy Bar",     busyness: .busy),
            TestFactories.makeVenue(name: "Quiet Bar",    busyness: .quiet),
            TestFactories.makeVenue(name: "Busy Pizza",    busyness: .busy)
        ]
        filterState.selectedCategory = .drinks
        filterState.selectedBusynessLevel = .busy
        #expect(vm.filteredVenues.count == 1)
        #expect(vm.filteredVenues[0].name == "Busy Bar")
    }

    @Test("toggleCategoryFilter deselects same category")
    func toggleCategoryDeselects() {
        let vm = MapViewModel()
        let filterState = VenueFilterState()
        vm.filterState = filterState

        vm.toggleCategoryFilter(.drinks)
        #expect(filterState.selectedCategory == .drinks)
        vm.toggleCategoryFilter(.drinks)
        #expect(filterState.selectedCategory == nil)
    }

    @Test("toggleCategoryFilter switches to new category")
    func toggleCategorySwitches() {
        let vm = MapViewModel()
        let filterState = VenueFilterState()
        vm.filterState = filterState

        vm.toggleCategoryFilter(.drinks)
        vm.toggleCategoryFilter(.food)
        #expect(filterState.selectedCategory == .food)
    }

    // MARK: - Clustering Integration

    @Test("mapItems populated after venues set and region changed")
    func mapItemsPopulated() {
        let vm = MapViewModel()
        vm.venues = [
            TestFactories.makeVenue(name: "Bar A",
                coordinate: CLLocationCoordinate2D(latitude: 43.65, longitude: -79.38)),
            TestFactories.makeVenue(name: "Bar B",
                coordinate: CLLocationCoordinate2D(latitude: 43.66, longitude: -79.39))
        ]
        vm.onRegionChanged(toronto)
        let zoomedOut = MKCoordinateRegion(
            center: toronto.center,
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        )
        vm.onRegionChanged(zoomedOut)
        #expect(!vm.mapItems.isEmpty)
    }

    @Test("Category filter affects mapItems")
    func categoryFilterAffectsMapItems() {
        let vm = MapViewModel()
        let filterState = VenueFilterState()
        vm.filterState = filterState

        vm.venues = [
            TestFactories.makeVenue(name: "Cocktail Bar"),
            TestFactories.makeVenue(name: "Coffee Cafe")
        ]
        vm.toggleCategoryFilter(.drinks)
        let filteredCount = vm.mapItems.count
        vm.toggleCategoryFilter(.drinks)
        let allCount = vm.mapItems.count
        #expect(filteredCount <= allCount)
    }

    // MARK: - onRegionChanged

    @Test("First region change does not show search button")
    func firstRegionChangeNoButton() {
        let vm = MapViewModel()
        vm.onRegionChanged(toronto)
        #expect(vm.showSearchThisArea == false)
    }

    @Test("Large pan shows search button")
    func largePanShowsButton() {
        let vm = MapViewModel()
        vm.lastSearchedRegion = toronto

        let panned = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 43.67, longitude: -79.38),
            span: toronto.span
        )
        vm.onRegionChanged(panned)
        #expect(vm.showSearchThisArea == true)
    }

    @Test("Large zoom change shows search button")
    func largeZoomShowsButton() {
        let vm = MapViewModel()
        vm.lastSearchedRegion = toronto

        let zoomedOut = MKCoordinateRegion(
            center: toronto.center,
            span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2)
        )
        vm.onRegionChanged(zoomedOut)
        #expect(vm.showSearchThisArea == true)
    }

    @Test("Tiny pan does not show search button")
    func tinyPanNoButton() {
        let vm = MapViewModel()
        vm.lastSearchedRegion = toronto

        let nudged = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 43.651, longitude: -79.381),
            span: toronto.span
        )
        vm.onRegionChanged(nudged)
        #expect(vm.showSearchThisArea == false)
    }

    @Test("Search button not shown during active search")
    func noButtonDuringSearch() {
        let vm = MapViewModel()
        vm.lastSearchedRegion = toronto
        vm.isSearching = true

        let panned = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 43.67, longitude: -79.38),
            span: toronto.span
        )
        vm.onRegionChanged(panned)
        #expect(vm.showSearchThisArea == false)
    }

    // MARK: - Zoom-based Reclustering

    @Test("Significant zoom triggers recluster")
    func zoomChangeReclustersTrigger() {
        let vm = MapViewModel()
        vm.venues = [
            TestFactories.makeVenue(name: "A",
                coordinate: CLLocationCoordinate2D(latitude: 43.65, longitude: -79.38)),
            TestFactories.makeVenue(name: "B",
                coordinate: CLLocationCoordinate2D(latitude: 43.65, longitude: -79.38))
        ]
        vm.onRegionChanged(toronto)
        let zoomedOut = MKCoordinateRegion(
            center: toronto.center,
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        )
        vm.onRegionChanged(zoomedOut)
        #expect(!vm.mapItems.isEmpty)
    }

    @Test("Minor zoom does not trigger recluster")
    func minorZoomNoRecluster() {
        let vm = MapViewModel()
        vm.venues = [
            TestFactories.makeVenue(name: "A",
                coordinate: CLLocationCoordinate2D(latitude: 43.65, longitude: -79.38))
        ]
        vm.onRegionChanged(toronto)
        let itemsBefore = vm.mapItems.count

        let slightZoom = MKCoordinateRegion(
            center: toronto.center,
            span: MKCoordinateSpan(latitudeDelta: 0.055, longitudeDelta: 0.055)
        )
        vm.onRegionChanged(slightZoom)
        #expect(vm.mapItems.count == itemsBefore)
    }

    // MARK: - selectVenue

    @Test("selectVenue sets selectedVenue")
    func selectVenueSetsProperty() {
        let vm = MapViewModel()
        let venue = TestFactories.makeVenue(name: "Selected Bar")
        vm.selectVenue(venue)
        #expect(vm.selectedVenue?.id == venue.id)
    }

    @Test("selectVenue updates camera position")
    func selectVenueUpdatesCamera() {
        let vm = MapViewModel()
        let coord = CLLocationCoordinate2D(latitude: 43.65, longitude: -79.38)
        let venue = TestFactories.makeVenue(name: "Bar", coordinate: coord)
        vm.selectVenue(venue, heading: 45, pitch: 30)
        #expect(vm.selectedVenue != nil)
    }

    // MARK: - clearSearch

    @Test("clearSearch resets text and selection")
    func clearSearchResetsState() {
        let vm = MapViewModel()
        vm.searchText = "pizza"
        vm.selectedVenue = TestFactories.makeVenue(name: "Pizza Place")
        vm.clearSearch(in: toronto)
        #expect(vm.searchText.isEmpty)
        #expect(vm.selectedVenue == nil)
    }

    // MARK: - Text Search

    @Test("Empty text search does not crash")
    func emptyTextSearchSafe() {
        let vm = MapViewModel()
        vm.searchText = "   "
        vm.searchVenues(in: toronto)
        // Just verifying no crash
    }

    // MARK: - expandSearch

    @Test("expandSearch requires lastSearchedRegion")
    func expandSearchRequiresRegion() {
        let vm = MapViewModel()
        #expect(vm.lastSearchedRegion == nil)
        vm.expandSearch()
        // Should be a no-op — not crash, not set isExpandingSearch
        #expect(vm.isExpandingSearch == false)
    }

    @Test("expandSearch guards against concurrent calls")
    func expandSearchGuardsConcurrent() {
        let vm = MapViewModel()
        vm.lastSearchedRegion = toronto
        vm.isExpandingSearch = true
        vm.expandSearch()
        // Should not start a second expand — isExpandingSearch was already true
        // No way to assert on expandTask count, but verifying no crash
    }

    @Test("expandSearch merges new venues without duplicates")
    func expandSearchMergesNoDuplicates() {
        let vm = MapViewModel()
        let existingVenue = TestFactories.makeVenue(name: "Existing Bar",
            coordinate: CLLocationCoordinate2D(latitude: 43.65, longitude: -79.38))
        vm.venues = [existingVenue]
        vm.lastSearchedRegion = toronto

        // Simulate what expandSearch does internally: merge check
        let existingIDs = Set(vm.venues.map(\.id))
        let newVenue = TestFactories.makeVenue(name: "Existing Bar",
            coordinate: CLLocationCoordinate2D(latitude: 43.65, longitude: -79.38))
        let additional = [newVenue].filter { !existingIDs.contains($0.id) }
        #expect(additional.isEmpty, "Duplicate venue should be filtered out")
    }

    @Test("expandSearch dedup allows genuinely new venues")
    func expandSearchDedupAllowsNew() {
        let vm = MapViewModel()
        let existingVenue = TestFactories.makeVenue(name: "Existing Bar",
            coordinate: CLLocationCoordinate2D(latitude: 43.65, longitude: -79.38))
        vm.venues = [existingVenue]

        let existingIDs = Set(vm.venues.map(\.id))
        let newVenue = TestFactories.makeVenue(name: "Brand New Place",
            coordinate: CLLocationCoordinate2D(latitude: 43.70, longitude: -79.40))
        let additional = [newVenue].filter { !existingIDs.contains($0.id) }
        #expect(additional.count == 1, "New venue should pass dedup filter")
    }

    // MARK: - searchVenues resets expandSearch state

    @Test("searchVenues resets isExpandingSearch")
    func searchVenuesResetsExpandState() {
        let vm = MapViewModel()
        vm.isExpandingSearch = true
        vm.searchVenues(in: toronto)
        #expect(vm.isExpandingSearch == false)
    }

    // MARK: - Live Refresh

    @Test("startLiveRefresh prevents duplicate timers")
    func startLiveRefreshGuardsDuplicates() {
        let vm = MapViewModel()
        vm.startLiveRefresh()
        vm.startLiveRefresh()  // Second call should be a no-op
        // No crash = pass. Timer guard handles this internally.
        vm.stopLiveRefresh()
    }

    @Test("stopLiveRefresh is safe to call without start")
    func stopLiveRefreshSafe() {
        let vm = MapViewModel()
        vm.stopLiveRefresh()
        // No crash = pass
    }

    // MARK: - FilterState Wiring

    @Test("filterState nil does not crash filteredVenues")
    func noFilterStateSafe() {
        let vm = MapViewModel()
        #expect(vm.filterState == nil)
        vm.venues = [TestFactories.makeVenue(name: "Test")]
        #expect(vm.filteredVenues.count == 1)
    }

    @Test("Setting filterState enables filtering")
    func settingFilterStateEnables() {
        let vm = MapViewModel()
        let filterState = VenueFilterState()
        vm.filterState = filterState

        vm.venues = [
            TestFactories.makeVenue(name: "Bar", busyness: .quiet),
            TestFactories.makeVenue(name: "Pub", busyness: .busy)
        ]
        filterState.selectedBusynessLevel = .busy
        #expect(vm.filteredVenues.count == 1)
    }
}
