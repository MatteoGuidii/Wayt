import Testing
import Foundation
import CoreLocation
import MapKit
@testable import Venuu

/// Tests the shared data flow: MapViewModel → DiscoverViewModel.
/// Verifies that Discover correctly mirrors Map's venue data,
/// that filters work across both, and that expandSearch integrates properly.
@Suite("Shared Data Flow (Map → Discover)")
@MainActor
struct SharedDataFlowTests {

    private let toronto = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 43.65, longitude: -79.38),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )

    /// Simulates the wiring in MainTabView + DiscoverScreen:
    /// MapViewModel as source of truth, DiscoverViewModel consuming its venues.
    private func makeWiredPair() -> (map: MapViewModel, discover: DiscoverViewModel, filter: VenueFilterState) {
        let mapVM = MapViewModel()
        let discoverVM = DiscoverViewModel()
        let filterState = VenueFilterState()

        mapVM.filterState = filterState
        discoverVM.filterState = filterState

        return (mapVM, discoverVM, filterState)
    }

    /// Simulates what DiscoverScreen.onChange does.
    private func propagateToDiscover(
        from mapVM: MapViewModel,
        to discoverVM: DiscoverViewModel,
        userLocation: CLLocation? = nil
    ) {
        discoverVM.updateVenues(mapVM.venues, userLocation: userLocation)
    }

    // MARK: - Basic Propagation

    @Test("Discover receives venues from Map")
    func discoverReceivesMapVenues() {
        let (mapVM, discoverVM, _) = makeWiredPair()

        mapVM.venues = [
            TestFactories.makeVenue(name: "Bar A", busyness: .busy),
            TestFactories.makeVenue(name: "Bar B", busyness: .quiet)
        ]
        propagateToDiscover(from: mapVM, to: discoverVM)

        #expect(discoverVM.venues.count == 2)
        #expect(discoverVM.filteredVenues.count == 2)
    }

    @Test("Discover venues have same busyness as Map venues")
    func discoverBusynessMatchesMap() {
        let (mapVM, discoverVM, _) = makeWiredPair()

        mapVM.venues = [
            TestFactories.makeVenue(name: "Packed Club", busyness: .packed)
        ]
        propagateToDiscover(from: mapVM, to: discoverVM)

        #expect(discoverVM.venues[0].busyness == .packed)
    }

    @Test("Empty Map means empty Discover")
    func emptyMapMeansEmptyDiscover() {
        let (mapVM, discoverVM, _) = makeWiredPair()

        mapVM.venues = []
        propagateToDiscover(from: mapVM, to: discoverVM)

        #expect(discoverVM.venues.isEmpty)
        #expect(discoverVM.popularVenues.isEmpty)
        #expect(discoverVM.sweetSpotVenues.isEmpty)
    }

    // MARK: - Venue Replacement

    @Test("Map venue replacement fully replaces Discover venues")
    func mapReplacementReplacesDiscover() {
        let (mapVM, discoverVM, _) = makeWiredPair()

        mapVM.venues = [TestFactories.makeVenue(name: "Old Bar", busyness: .quiet)]
        propagateToDiscover(from: mapVM, to: discoverVM)
        #expect(discoverVM.venues.count == 1)
        #expect(discoverVM.venues[0].name == "Old Bar")

        mapVM.venues = [
            TestFactories.makeVenue(name: "New A", busyness: .busy),
            TestFactories.makeVenue(name: "New B", busyness: .packed)
        ]
        propagateToDiscover(from: mapVM, to: discoverVM)
        #expect(discoverVM.venues.count == 2)
        #expect(discoverVM.venues.allSatisfy { $0.name.hasPrefix("New") })
    }

    // MARK: - Busyness Updates Propagate

    @Test("Busyness change on Map propagates to Discover")
    func busynessChangePropagates() {
        let (mapVM, discoverVM, _) = makeWiredPair()

        let coord = CLLocationCoordinate2D(latitude: 43.65, longitude: -79.38)
        mapVM.venues = [TestFactories.makeVenue(name: "The Bar", busyness: .quiet, coordinate: coord)]
        propagateToDiscover(from: mapVM, to: discoverVM)
        #expect(discoverVM.venues[0].busyness == .quiet)

        // Simulate live refresh changing busyness
        mapVM.venues[0].busyness = .packed
        propagateToDiscover(from: mapVM, to: discoverVM)
        #expect(discoverVM.venues[0].busyness == .packed)
    }

    // MARK: - Distance Sorting

    @Test("Discover sorts by distance while Map preserves search order")
    func discoverSortsByDistance() {
        let (mapVM, discoverVM, _) = makeWiredPair()
        let userLocation = CLLocation(latitude: 43.65, longitude: -79.38)

        let farCoord = CLLocationCoordinate2D(latitude: 43.70, longitude: -79.40)
        let nearCoord = CLLocationCoordinate2D(latitude: 43.651, longitude: -79.381)

        // Map has far venue first
        mapVM.venues = [
            TestFactories.makeVenue(name: "Far Bar", busyness: .busy, coordinate: farCoord),
            TestFactories.makeVenue(name: "Near Bar", busyness: .quiet, coordinate: nearCoord)
        ]
        #expect(mapVM.venues[0].name == "Far Bar")

        propagateToDiscover(from: mapVM, to: discoverVM, userLocation: userLocation)
        // Discover should reorder by distance
        #expect(discoverVM.venues[0].name == "Near Bar")
        #expect(discoverVM.venues[1].name == "Far Bar")
    }

    // MARK: - Shared Filter State

    @Test("Category filter affects both Map and Discover")
    func sharedCategoryFilter() {
        let (mapVM, discoverVM, filterState) = makeWiredPair()

        mapVM.venues = [
            TestFactories.makeVenue(name: "Cocktail Bar", busyness: .busy),
            TestFactories.makeVenue(name: "Pizza Place", busyness: .busy)
        ]
        propagateToDiscover(from: mapVM, to: discoverVM)

        filterState.selectedCategory = .drinks

        // Map's filteredVenues (used for markers)
        #expect(mapVM.filteredVenues.allSatisfy { $0.category == .drinks })

        // Trigger Discover re-filter (simulates what the Combine observer does)
        discoverVM.updateVenues(mapVM.venues, userLocation: nil)
        #expect(discoverVM.filteredVenues.allSatisfy { $0.category == .drinks })
    }

    @Test("Busyness filter affects both Map and Discover")
    func sharedBusynessFilter() {
        let (mapVM, discoverVM, filterState) = makeWiredPair()

        mapVM.venues = [
            TestFactories.makeVenue(name: "Quiet Bar", busyness: .quiet),
            TestFactories.makeVenue(name: "Busy Bar", busyness: .busy)
        ]
        propagateToDiscover(from: mapVM, to: discoverVM)

        filterState.selectedBusynessLevel = .busy

        #expect(mapVM.filteredVenues.count == 1)
        #expect(mapVM.filteredVenues[0].busyness == .busy)

        discoverVM.updateVenues(mapVM.venues, userLocation: nil)
        #expect(discoverVM.filteredVenues.count == 1)
        #expect(discoverVM.filteredVenues[0].busyness == .busy)
    }

    // MARK: - Expand Search Integration

    @Test("expandSearch appended venues propagate to Discover")
    func expandSearchPropagatesToDiscover() {
        let (mapVM, discoverVM, _) = makeWiredPair()

        let venue1 = TestFactories.makeVenue(name: "Original Bar",
            busyness: .busy,
            coordinate: CLLocationCoordinate2D(latitude: 43.65, longitude: -79.38))
        mapVM.venues = [venue1]
        mapVM.lastSearchedRegion = toronto
        propagateToDiscover(from: mapVM, to: discoverVM)
        #expect(discoverVM.venues.count == 1)

        // Simulate expand adding a new venue
        let venue2 = TestFactories.makeVenue(name: "Expanded Bar",
            busyness: .quiet,
            coordinate: CLLocationCoordinate2D(latitude: 43.70, longitude: -79.40))
        mapVM.venues.append(venue2)
        propagateToDiscover(from: mapVM, to: discoverVM)
        #expect(discoverVM.venues.count == 2)
    }

    @Test("searchVenues after expandSearch resets Discover to new region's venues")
    func searchAfterExpandResetsDiscover() {
        let (mapVM, discoverVM, _) = makeWiredPair()

        // Start with 2 venues (1 original + 1 from expand)
        mapVM.venues = [
            TestFactories.makeVenue(name: "Original", busyness: .busy,
                coordinate: CLLocationCoordinate2D(latitude: 43.65, longitude: -79.38)),
            TestFactories.makeVenue(name: "Expanded", busyness: .quiet,
                coordinate: CLLocationCoordinate2D(latitude: 43.70, longitude: -79.40))
        ]
        propagateToDiscover(from: mapVM, to: discoverVM)
        #expect(discoverVM.venues.count == 2)

        // Simulate "Search This Area" replacing with just 1 venue
        mapVM.venues = [
            TestFactories.makeVenue(name: "New Area Venue", busyness: .moderate,
                coordinate: CLLocationCoordinate2D(latitude: 43.68, longitude: -79.39))
        ]
        propagateToDiscover(from: mapVM, to: discoverVM)
        #expect(discoverVM.venues.count == 1)
        #expect(discoverVM.venues[0].name == "New Area Venue")
    }

    // MARK: - Derived Data Consistency

    @Test("Discover's vibePulse reflects Map's venue busyness distribution")
    func vibePulseReflectsMap() {
        let (mapVM, discoverVM, _) = makeWiredPair()

        mapVM.venues = [
            TestFactories.makeVenue(name: "A", busyness: .quiet),
            TestFactories.makeVenue(name: "B", busyness: .quiet),
            TestFactories.makeVenue(name: "C", busyness: .packed)
        ]
        propagateToDiscover(from: mapVM, to: discoverVM)

        #expect(discoverVM.vibePulse[2] == 2)  // 2 quiet venues
        #expect(discoverVM.vibePulse[5] == 1)  // 1 packed venue
        #expect(discoverVM.vibePulse[1] == 0)  // no empty
        #expect(discoverVM.vibePulse[3] == 0)  // no moderate
        #expect(discoverVM.vibePulse[4] == 0)  // no busy
    }

    @Test("Discover's areaMood reflects Map's average busyness")
    func areaMoodReflectsMap() {
        let (mapVM, discoverVM, _) = makeWiredPair()

        mapVM.venues = [
            TestFactories.makeVenue(name: "A", busyness: .empty),    // 1
            TestFactories.makeVenue(name: "B", busyness: .packed)    // 5
        ]
        propagateToDiscover(from: mapVM, to: discoverVM)
        // Average = 3 → moderate
        #expect(discoverVM.areaMood == .moderate)
    }

    @Test("Discover's categoryCounts match Map's venue distribution")
    func categoryCountsMatchMap() {
        let (mapVM, discoverVM, _) = makeWiredPair()

        mapVM.venues = [
            TestFactories.makeVenue(name: "Bar A"),      // drinks
            TestFactories.makeVenue(name: "Bar B"),      // drinks
            TestFactories.makeVenue(name: "Coffee Cafe") // coffee
        ]
        propagateToDiscover(from: mapVM, to: discoverVM)

        #expect(discoverVM.categoryCounts[.drinks] == 2)
        #expect(discoverVM.categoryCounts[.coffee] == 1)
    }

    // MARK: - No Duplicate Data

    @Test("Same venues propagated twice don't duplicate in Discover")
    func noDuplicationOnRepeat() {
        let (mapVM, discoverVM, _) = makeWiredPair()

        mapVM.venues = [
            TestFactories.makeVenue(name: "Bar", busyness: .busy)
        ]
        propagateToDiscover(from: mapVM, to: discoverVM)
        propagateToDiscover(from: mapVM, to: discoverVM)
        #expect(discoverVM.venues.count == 1)
    }
}
