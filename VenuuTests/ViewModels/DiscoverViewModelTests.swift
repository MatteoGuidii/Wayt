import Testing
import Foundation
import CoreLocation
@testable import Venuu

@Suite("DiscoverViewModel")
@MainActor
struct DiscoverViewModelTests {

    // MARK: - Initial State

    @Test("ViewModel starts with empty venues and no derived data")
    func initialState() {
        let vm = DiscoverViewModel()
        #expect(vm.venues.isEmpty)
        #expect(vm.filteredVenues.isEmpty)
        #expect(vm.popularVenues.isEmpty)
        #expect(vm.sweetSpotVenues.isEmpty)
    }

    // MARK: - updateVenues

    @Test("updateVenues populates venues and derived arrays")
    func updateVenuesPopulatesAll() {
        let vm = DiscoverViewModel()
        let venues = [
            TestFactories.makeVenue(name: "Quiet Bar", busyness: .quiet),
            TestFactories.makeVenue(name: "Busy Bar", busyness: .busy),
            TestFactories.makeVenue(name: "Packed Club", busyness: .packed)
        ]
        vm.updateVenues(venues, userLocation: nil)
        #expect(vm.venues.count == 3)
        #expect(!vm.filteredVenues.isEmpty)
    }

    @Test("updateVenues sorts by distance when userLocation is provided")
    func updateVenuesSortsByDistance() {
        let vm = DiscoverViewModel()
        let userLocation = CLLocation(latitude: 43.65, longitude: -79.38)

        let farCoord = CLLocationCoordinate2D(latitude: 43.70, longitude: -79.40)
        let nearCoord = CLLocationCoordinate2D(latitude: 43.651, longitude: -79.381)

        let venues = [
            TestFactories.makeVenue(name: "Far Venue", coordinate: farCoord),
            TestFactories.makeVenue(name: "Near Venue", coordinate: nearCoord)
        ]
        vm.updateVenues(venues, userLocation: userLocation)
        #expect(vm.venues[0].name == "Near Venue")
        #expect(vm.venues[1].name == "Far Venue")
    }

    @Test("updateVenues without userLocation preserves original order")
    func updateVenuesNoLocationKeepsOrder() {
        let vm = DiscoverViewModel()
        let venues = [
            TestFactories.makeVenue(name: "Alpha"),
            TestFactories.makeVenue(name: "Beta"),
            TestFactories.makeVenue(name: "Gamma")
        ]
        vm.updateVenues(venues, userLocation: nil)
        #expect(vm.venues[0].name == "Alpha")
        #expect(vm.venues[1].name == "Beta")
        #expect(vm.venues[2].name == "Gamma")
    }

    @Test("updateVenues with empty array clears all derived state")
    func updateVenuesEmptyClears() {
        let vm = DiscoverViewModel()
        vm.updateVenues([
            TestFactories.makeVenue(name: "Bar", busyness: .busy)
        ], userLocation: nil)
        #expect(!vm.venues.isEmpty)

        vm.updateVenues([], userLocation: nil)
        #expect(vm.venues.isEmpty)
        #expect(vm.filteredVenues.isEmpty)
        #expect(vm.popularVenues.isEmpty)
        #expect(vm.sweetSpotVenues.isEmpty)
    }

    @Test("updateVenues replaces previous data completely")
    func updateVenuesReplaces() {
        let vm = DiscoverViewModel()
        vm.updateVenues([
            TestFactories.makeVenue(name: "Old Bar", busyness: .busy)
        ], userLocation: nil)
        #expect(vm.venues.count == 1)

        vm.updateVenues([
            TestFactories.makeVenue(name: "New A", busyness: .quiet),
            TestFactories.makeVenue(name: "New B", busyness: .packed)
        ], userLocation: nil)
        #expect(vm.venues.count == 2)
        #expect(vm.venues.allSatisfy { $0.name.hasPrefix("New") })
    }

    // MARK: - popularVenues (On Fire: busyness >= 4)

    @Test("popularVenues only includes venues with busyness >= 4")
    func popularVenuesThresholdIsFour() {
        let vm = DiscoverViewModel()
        vm.updateVenues([
            TestFactories.makeVenue(name: "Empty",    busyness: .empty),     // 1
            TestFactories.makeVenue(name: "Quiet",    busyness: .quiet),     // 2
            TestFactories.makeVenue(name: "Moderate", busyness: .moderate),  // 3
            TestFactories.makeVenue(name: "Busy",     busyness: .busy),      // 4 — included
            TestFactories.makeVenue(name: "Packed",   busyness: .packed)     // 5 — included
        ], userLocation: nil)
        #expect(vm.popularVenues.count == 2)
        #expect(vm.popularVenues.allSatisfy { ($0.busyness?.rawValue ?? 0) >= 4 })
    }

    @Test("popularVenues sorted by busyness descending")
    func popularVenuesSortedDescending() {
        let vm = DiscoverViewModel()
        vm.updateVenues([
            TestFactories.makeVenue(name: "Busy",   busyness: .busy),    // 4
            TestFactories.makeVenue(name: "Packed", busyness: .packed)   // 5
        ], userLocation: nil)
        #expect(vm.popularVenues[0].busyness == .packed)
        #expect(vm.popularVenues[1].busyness == .busy)
    }

    @Test("popularVenues capped at 10")
    func popularVenuesCappedAt10() {
        let vm = DiscoverViewModel()
        var venues: [Venue] = []
        for i in 0..<15 {
            venues.append(TestFactories.makeVenue(
                name: "Busy Spot \(i)",
                busyness: .busy,
                coordinate: CLLocationCoordinate2D(latitude: 43.65 + Double(i) * 0.001, longitude: -79.38)
            ))
        }
        vm.updateVenues(venues, userLocation: nil)
        #expect(vm.popularVenues.count == 10)
    }

    @Test("popularVenues excludes nil busyness")
    func popularVenuesExcludesNil() {
        let vm = DiscoverViewModel()
        vm.updateVenues([
            TestFactories.makeVenue(name: "No Data", busyness: nil),
            TestFactories.makeVenue(name: "Busy",    busyness: .busy)
        ], userLocation: nil)
        #expect(vm.popularVenues.count == 1)
    }

    // MARK: - sweetSpotVenues (Go Now: busyness 1–3)

    @Test("sweetSpotVenues includes busyness 1-3 only")
    func sweetSpotVenuesRange() {
        let vm = DiscoverViewModel()
        vm.updateVenues([
            TestFactories.makeVenue(name: "Empty",    busyness: .empty),     // 1 — included
            TestFactories.makeVenue(name: "Quiet",    busyness: .quiet),     // 2 — included
            TestFactories.makeVenue(name: "Moderate", busyness: .moderate),  // 3 — included
            TestFactories.makeVenue(name: "Busy",     busyness: .busy),      // 4 — excluded
            TestFactories.makeVenue(name: "Packed",   busyness: .packed)     // 5 — excluded
        ], userLocation: nil)
        #expect(vm.sweetSpotVenues.count == 3)
        #expect(vm.sweetSpotVenues.allSatisfy {
            let raw = $0.busyness?.rawValue ?? 0
            return raw >= 1 && raw <= 3
        })
    }

    @Test("sweetSpotVenues excludes nil busyness")
    func sweetSpotExcludesNil() {
        let vm = DiscoverViewModel()
        vm.updateVenues([
            TestFactories.makeVenue(name: "No Data", busyness: nil)
        ], userLocation: nil)
        #expect(vm.sweetSpotVenues.isEmpty)
    }

    @Test("sweetSpotVenues capped at 8")
    func sweetSpotCappedAt8() {
        let vm = DiscoverViewModel()
        var venues: [Venue] = []
        for i in 0..<12 {
            venues.append(TestFactories.makeVenue(
                name: "Chill Spot \(i)",
                busyness: .quiet,
                coordinate: CLLocationCoordinate2D(latitude: 43.65 + Double(i) * 0.001, longitude: -79.38)
            ))
        }
        vm.updateVenues(venues, userLocation: nil)
        #expect(vm.sweetSpotVenues.count == 8)
    }

    // MARK: - Filtering via VenueFilterState

    @Test("Category filter narrows filteredVenues")
    func categoryFilterWorks() {
        let vm = DiscoverViewModel()
        let filterState = VenueFilterState()
        vm.filterState = filterState

        vm.updateVenues([
            TestFactories.makeVenue(name: "Cocktail Bar", busyness: .moderate),
            TestFactories.makeVenue(name: "Wine Bar",     busyness: .busy),
            TestFactories.makeVenue(name: "Pizza Place",  busyness: .quiet)
        ], userLocation: nil)

        filterState.selectCategory(.drinks)
        // Allow runloop tick for Combine observation
        vm.updateVenues(vm.venues, userLocation: nil)
        #expect(vm.filteredVenues.allSatisfy { $0.category == .drinks })
    }

    @Test("Busyness filter narrows filteredVenues")
    func busynessFilterWorks() {
        let vm = DiscoverViewModel()
        let filterState = VenueFilterState()
        vm.filterState = filterState

        vm.updateVenues([
            TestFactories.makeVenue(name: "Quiet Bar",  busyness: .quiet),
            TestFactories.makeVenue(name: "Busy Bar",   busyness: .busy),
            TestFactories.makeVenue(name: "Packed Bar",  busyness: .packed)
        ], userLocation: nil)

        filterState.selectBusynessLevel(.busy)
        vm.updateVenues(vm.venues, userLocation: nil)
        #expect(vm.filteredVenues.count == 1)
        #expect(vm.filteredVenues[0].busyness == .busy)
    }

    @Test("No filter shows all venues in filteredVenues")
    func noFilterShowsAll() {
        let vm = DiscoverViewModel()
        vm.updateVenues([
            TestFactories.makeVenue(name: "A", busyness: .quiet),
            TestFactories.makeVenue(name: "B", busyness: .busy),
            TestFactories.makeVenue(name: "C", busyness: .packed)
        ], userLocation: nil)
        #expect(vm.filteredVenues.count == 3)
    }

    @Test("Category filter also affects popularVenues and sweetSpotVenues")
    func categoryFilterAffectsDerivedArrays() {
        let vm = DiscoverViewModel()
        let filterState = VenueFilterState()
        vm.filterState = filterState

        vm.updateVenues([
            TestFactories.makeVenue(name: "Busy Bar",     busyness: .busy),    // drinks, popular
            TestFactories.makeVenue(name: "Busy Pizza",    busyness: .busy),    // food, popular
            TestFactories.makeVenue(name: "Quiet Cafe",    busyness: .quiet)    // coffee, sweet spot
        ], userLocation: nil)

        filterState.selectCategory(.drinks)
        vm.updateVenues(vm.venues, userLocation: nil)
        // Only the bar should be in popularVenues
        #expect(vm.popularVenues.allSatisfy { $0.category == .drinks })
        // No drinks venue is quiet, so sweetSpot should be empty
        #expect(vm.sweetSpotVenues.isEmpty)
    }

    // MARK: - vibePulse

    @Test("vibePulse counts venues per busyness level")
    func vibePulseCounts() {
        let vm = DiscoverViewModel()
        vm.updateVenues([
            TestFactories.makeVenue(name: "A", busyness: .quiet),
            TestFactories.makeVenue(name: "B", busyness: .quiet),
            TestFactories.makeVenue(name: "C", busyness: .busy)
        ], userLocation: nil)
        #expect(vm.vibePulse[2] == 2)  // quiet = 2
        #expect(vm.vibePulse[4] == 1)  // busy = 4
        #expect(vm.vibePulse[1] == 0)  // empty = 0
        #expect(vm.vibePulse[3] == 0)  // moderate = 0
        #expect(vm.vibePulse[5] == 0)  // packed = 0
    }

    @Test("vibePulse ignores nil busyness")
    func vibePulseIgnoresNil() {
        let vm = DiscoverViewModel()
        vm.updateVenues([
            TestFactories.makeVenue(name: "No Data", busyness: nil)
        ], userLocation: nil)
        let total = vm.vibePulse.values.reduce(0, +)
        #expect(total == 0)
    }

    @Test("vibePulse uses unfiltered venues array")
    func vibePulseUsesAllVenues() {
        let vm = DiscoverViewModel()
        let filterState = VenueFilterState()
        vm.filterState = filterState

        vm.updateVenues([
            TestFactories.makeVenue(name: "Quiet Bar",  busyness: .quiet),
            TestFactories.makeVenue(name: "Busy Pizza",  busyness: .busy)
        ], userLocation: nil)

        filterState.selectCategory(.drinks)
        vm.updateVenues(vm.venues, userLocation: nil)
        // vibePulse should still count ALL venues, not just filtered
        let total = vm.vibePulse.values.reduce(0, +)
        #expect(total == 2)
    }

    // MARK: - categoryCounts

    @Test("categoryCounts groups venues by category")
    func categoryCountsGroups() {
        let vm = DiscoverViewModel()
        vm.updateVenues([
            TestFactories.makeVenue(name: "Bar A"),
            TestFactories.makeVenue(name: "Bar B"),
            TestFactories.makeVenue(name: "Coffee Cafe")
        ], userLocation: nil)
        #expect(vm.categoryCounts[.drinks] == 2)
        #expect(vm.categoryCounts[.coffee] == 1)
    }

    // MARK: - areaMood

    @Test("areaMood returns average busyness level")
    func areaMoodAverages() {
        let vm = DiscoverViewModel()
        vm.updateVenues([
            TestFactories.makeVenue(name: "A", busyness: .quiet),    // 2
            TestFactories.makeVenue(name: "B", busyness: .busy)      // 4
        ], userLocation: nil)
        // Average = 3 → moderate
        #expect(vm.areaMood == .moderate)
    }

    @Test("areaMood is nil when no venues have busyness")
    func areaMoodNilWhenNoBusyness() {
        let vm = DiscoverViewModel()
        vm.updateVenues([
            TestFactories.makeVenue(name: "A", busyness: nil)
        ], userLocation: nil)
        #expect(vm.areaMood == nil)
    }

    @Test("areaMood is nil with empty venues")
    func areaMoodNilWhenEmpty() {
        let vm = DiscoverViewModel()
        #expect(vm.areaMood == nil)
    }

    // MARK: - Greeting

    @Test("greeting returns a non-empty string")
    func greetingNotEmpty() {
        let vm = DiscoverViewModel()
        #expect(!vm.greeting.isEmpty)
    }

    @Test("greetingSubtitle returns a non-empty string")
    func greetingSubtitleNotEmpty() {
        let vm = DiscoverViewModel()
        #expect(!vm.greetingSubtitle.isEmpty)
    }
}
