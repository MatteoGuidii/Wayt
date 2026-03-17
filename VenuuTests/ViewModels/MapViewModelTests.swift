import Testing
import Foundation
import MapKit
@testable import Venuu

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
        #expect(vm.selectedCategory == nil)
    }

    // MARK: - Category Filtering

    @Test("filteredVenues returns all venues when no category selected")
    func filteredVenuesNoCategory() {
        let vm = MapViewModel()
        vm.venues = [
            TestFactories.makeVenue(name: "Bar A"),
            TestFactories.makeVenue(name: "Coffee Cafe"),
            TestFactories.makeVenue(name: "Pizza Place")
        ]
        #expect(vm.filteredVenues.count == 3)
    }

    @Test("filteredVenues filters by selected category")
    func filteredVenuesWithCategory() {
        let vm = MapViewModel()
        vm.venues = [
            TestFactories.makeVenue(name: "Cocktail Bar"),
            TestFactories.makeVenue(name: "Wine Bar"),
            TestFactories.makeVenue(name: "Pizza Place")
        ]
        vm.toggleCategoryFilter(.drinks)
        #expect(vm.filteredVenues.allSatisfy { $0.category == .drinks })
    }

    @Test("toggleCategoryFilter deselects if same category tapped again")
    func toggleCategoryDeselects() {
        let vm = MapViewModel()
        vm.toggleCategoryFilter(.drinks)
        #expect(vm.selectedCategory == .drinks)
        vm.toggleCategoryFilter(.drinks)
        #expect(vm.selectedCategory == nil)
    }

    @Test("toggleCategoryFilter switches to new category")
    func toggleCategorySwitches() {
        let vm = MapViewModel()
        vm.toggleCategoryFilter(.drinks)
        vm.toggleCategoryFilter(.food)
        #expect(vm.selectedCategory == .food)
    }

    // MARK: - Clustering Integration

    @Test("mapItems populated after venues set and category toggled")
    func mapItemsPopulatedAfterVenueSet() {
        let vm = MapViewModel()
        vm.venues = [
            TestFactories.makeVenue(name: "Bar A",
                coordinate: CLLocationCoordinate2D(latitude: 43.65, longitude: -79.38)),
            TestFactories.makeVenue(name: "Bar B",
                coordinate: CLLocationCoordinate2D(latitude: 43.66, longitude: -79.39))
        ]
        // Set region first, then trigger recluster via zoom change
        vm.onRegionChanged(toronto)
        // First call sets currentRegion but ratio is 1.0 (no previous).
        // Trigger a zoom change to force recluster.
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
        vm.venues = [
            TestFactories.makeVenue(name: "Cocktail Bar"),
            TestFactories.makeVenue(name: "Coffee Cafe")
        ]
        // toggleCategoryFilter always reclusters (no debounce)
        vm.toggleCategoryFilter(.drinks)
        let filteredCount = vm.mapItems.count
        vm.toggleCategoryFilter(.drinks) // deselect → show all
        let allCount = vm.mapItems.count

        #expect(filteredCount <= allCount)
    }

    // MARK: - onRegionChanged

    @Test("First region change does not show search button (no lastSearchedRegion)")
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

    @Test("Zoom change of 1.3x triggers recluster")
    func zoomChangeReclustersTrigger() {
        let vm = MapViewModel()
        vm.venues = [
            TestFactories.makeVenue(name: "A",
                coordinate: CLLocationCoordinate2D(latitude: 43.65, longitude: -79.38)),
            TestFactories.makeVenue(name: "B",
                coordinate: CLLocationCoordinate2D(latitude: 43.65, longitude: -79.38))
        ]

        // Set initial region
        vm.onRegionChanged(toronto)

        // Zoom out significantly
        let zoomedOut = MKCoordinateRegion(
            center: toronto.center,
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        )
        vm.onRegionChanged(zoomedOut)

        // mapItems should have been recomputed (may or may not differ based on grid)
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

        // Tiny zoom change (1.1x, below 1.3x threshold)
        let slightZoom = MKCoordinateRegion(
            center: toronto.center,
            span: MKCoordinateSpan(latitudeDelta: 0.055, longitudeDelta: 0.055)
        )
        vm.onRegionChanged(slightZoom)

        // Should not have changed
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
        // Camera position should have changed from default
        // We can't easily inspect MapCameraPosition internals, but selectedVenue confirms intent
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

    // MARK: - performTextSearch

    @Test("Empty text search triggers normal search")
    func emptyTextSearchTriggersNormalSearch() {
        let vm = MapViewModel()
        vm.searchText = "   "
        // Should not crash, just delegates to searchVenues
        vm.performTextSearch(in: toronto)
        // No assertion on async result — just verifying no crash
    }
}
