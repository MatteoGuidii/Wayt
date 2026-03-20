import Testing
import Foundation
import CoreLocation
@testable import Venuu

@Suite("VenueDetailViewModel")
@MainActor
struct VenueDetailViewModelTests {

    // MARK: - Initial State

    @Test("Estimate uses venue's existing busyness when set")
    func estimateUsesExistingBusyness() {
        var venue = TestFactories.makeVenue(busyness: .busy)
        venue.busynessConfidence = .high
        venue.reportCount = 5
        let vm = VenueDetailViewModel(venue: venue)
        #expect(vm.estimate.level == .busy)
        #expect(vm.estimate.confidence == .high)
        #expect(vm.estimate.reportCount == 5)
    }

    @Test("Estimate falls back to offline default when venue has no busyness")
    func estimateFallsBackToOfflineDefaultWhenNoBusyness() {
        let venue = TestFactories.makeVenue(busyness: nil)
        let vm = VenueDetailViewModel(venue: venue)
        #expect(vm.estimate.confidence == .none)
        #expect(vm.estimate.level == .moderate)
    }

    @Test("reportSubmitted starts as false")
    func reportSubmittedStartsFalse() {
        let vm = VenueDetailViewModel(venue: TestFactories.makeVenue())
        #expect(vm.reportSubmitted == false)
    }

    @Test("showReportSheet starts as false")
    func showReportSheetStartsFalse() {
        let vm = VenueDetailViewModel(venue: TestFactories.makeVenue())
        #expect(vm.showReportSheet == false)
    }

    @Test("isLoadingReports starts as false")
    func isLoadingReportsStartsFalse() {
        let vm = VenueDetailViewModel(venue: TestFactories.makeVenue())
        #expect(vm.isLoadingReports == false)
    }

    @Test("recentReports starts empty")
    func recentReportsStartsEmpty() {
        let vm = VenueDetailViewModel(venue: TestFactories.makeVenue())
        #expect(vm.recentReports.isEmpty)
    }

    @Test("Estimate wait minutes reflects venue's estimatedWaitMinutes")
    func estimateReflectsVenueWaitMinutes() {
        var venue = TestFactories.makeVenue(busyness: .busy)
        venue.estimatedWaitMinutes = 20
        let vm = VenueDetailViewModel(venue: venue)
        #expect(vm.estimate.waitMinutes == 20)
    }

    // MARK: - submitReport Optimistic Update

    @Test("submitReport sets reportSubmitted to true immediately")
    func submitReportSetsReportSubmitted() async {
        let vm = VenueDetailViewModel(venue: TestFactories.makeVenue())
        await vm.submitReport(level: .busy, waitMinutes: nil)
        #expect(vm.reportSubmitted == true)
    }

    @Test("submitReport updates estimate level optimistically")
    func submitReportUpdatesEstimateLevel() async {
        let vm = VenueDetailViewModel(venue: TestFactories.makeVenue())
        await vm.submitReport(level: .packed, waitMinutes: nil)
        #expect(vm.estimate.level == .packed)
    }

    @Test("submitReport increments reportCount by one")
    func submitReportIncrementsReportCount() async {
        var venue = TestFactories.makeVenue(busyness: .moderate)
        venue.reportCount = 2
        venue.busynessConfidence = .low
        let vm = VenueDetailViewModel(venue: venue)
        let initialCount = vm.estimate.reportCount
        await vm.submitReport(level: .busy, waitMinutes: nil)
        #expect(vm.estimate.reportCount == initialCount + 1)
    }

    @Test("submitReport updates waitMinutes optimistically when provided")
    func submitReportUpdatesWaitMinutes() async {
        let vm = VenueDetailViewModel(venue: TestFactories.makeVenue())
        await vm.submitReport(level: .busy, waitMinutes: 15)
        #expect(vm.estimate.waitMinutes == 15)
    }

    @Test("submitReport reaches high confidence at threshold report count")
    func submitReportHighConfidenceAtThreshold() async {
        var venue = TestFactories.makeVenue(busyness: .busy)
        venue.reportCount = AppConstants.highConfidenceReportCount - 1
        venue.busynessConfidence = .low
        let vm = VenueDetailViewModel(venue: venue)
        await vm.submitReport(level: .busy, waitMinutes: nil)
        #expect(vm.estimate.confidence == .high)
    }

    // MARK: - showReportSheet Toggle

    @Test("showReportSheet can be toggled to true")
    func showReportSheetToggleTrue() {
        let vm = VenueDetailViewModel(venue: TestFactories.makeVenue())
        vm.showReportSheet = true
        #expect(vm.showReportSheet == true)
    }

    @Test("showReportSheet can be toggled back to false")
    func showReportSheetToggleFalse() {
        let vm = VenueDetailViewModel(venue: TestFactories.makeVenue())
        vm.showReportSheet = true
        vm.showReportSheet = false
        #expect(vm.showReportSheet == false)
    }

    // MARK: - Proximity Check

    @Test("updateProximity sets true when within report radius")
    func proximityWithinRange() {
        let coord = CLLocationCoordinate2D(latitude: 43.65107, longitude: -79.34723)
        let venue = TestFactories.makeVenue(name: "Nearby Bar", coordinate: coord)
        let vm = VenueDetailViewModel(venue: venue)

        // User 50m away (well within 200m radius)
        let userLocation = CLLocation(latitude: 43.6515, longitude: -79.3472)
        vm.updateProximity(userLocation: userLocation)
        #expect(vm.isWithinReportRange == true)
    }

    @Test("updateProximity sets false when outside report radius")
    func proximityOutOfRange() {
        let coord = CLLocationCoordinate2D(latitude: 43.65107, longitude: -79.34723)
        let venue = TestFactories.makeVenue(name: "Far Bar", coordinate: coord)
        let vm = VenueDetailViewModel(venue: venue)

        // User ~5km away
        let userLocation = CLLocation(latitude: 43.70, longitude: -79.40)
        vm.updateProximity(userLocation: userLocation)
        #expect(vm.isWithinReportRange == false)
    }

    @Test("updateProximity sets false when location is nil")
    func proximityNilLocation() {
        let vm = VenueDetailViewModel(venue: TestFactories.makeVenue())
        vm.isWithinReportRange = true
        vm.updateProximity(userLocation: nil)
        #expect(vm.isWithinReportRange == false)
    }

    @Test("updateProximity boundary: user approximately at report radius edge")
    func proximityAtBoundary() {
        let coord = CLLocationCoordinate2D(latitude: 43.65107, longitude: -79.34723)
        let venue = TestFactories.makeVenue(name: "Edge Bar", coordinate: coord)
        let vm = VenueDetailViewModel(venue: venue)

        // ~200m north (approx 0.0018 degrees latitude)
        let userLocation = CLLocation(latitude: 43.65107 + 0.0018, longitude: -79.34723)
        let venueLocation = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        let distance = venueLocation.distance(from: userLocation)

        vm.updateProximity(userLocation: userLocation)

        // Verify the distance is near the boundary (within 10m tolerance)
        #expect(abs(distance - AppConstants.reportProximityRadius) <= 10)
        // Result should match distance comparison
        #expect(vm.isWithinReportRange == (distance <= AppConstants.reportProximityRadius))
    }

    // MARK: - Distance Calculation

    @Test("distanceToVenue returns nil when location is nil")
    func distanceToVenueNil() {
        let vm = VenueDetailViewModel(venue: TestFactories.makeVenue())
        let distance = vm.distanceToVenue(from: nil)
        #expect(distance == nil)
    }

    @Test("distanceToVenue returns positive value for valid location")
    func distanceToVenuePositive() {
        let coord = CLLocationCoordinate2D(latitude: 43.65107, longitude: -79.34723)
        let venue = TestFactories.makeVenue(name: "Bar", coordinate: coord)
        let vm = VenueDetailViewModel(venue: venue)

        let userLocation = CLLocation(latitude: 43.66, longitude: -79.35)
        let distance = vm.distanceToVenue(from: userLocation)
        #expect(distance != nil)
        #expect(distance! > 0)
    }

    @Test("distanceToVenue returns zero when at same location")
    func distanceToVenueZero() {
        let coord = CLLocationCoordinate2D(latitude: 43.65107, longitude: -79.34723)
        let venue = TestFactories.makeVenue(name: "Bar", coordinate: coord)
        let vm = VenueDetailViewModel(venue: venue)

        let userLocation = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        let distance = vm.distanceToVenue(from: userLocation)
        #expect(distance != nil)
        #expect(distance! < 1) // should be essentially zero
    }

    // MARK: - submitReport Edge Cases

    @Test("submitReport preserves existing wait when new waitMinutes is nil")
    func submitReportPreservesExistingWait() async {
        var venue = TestFactories.makeVenue(busyness: .moderate)
        venue.estimatedWaitMinutes = 25
        let vm = VenueDetailViewModel(venue: venue)
        await vm.submitReport(level: .busy, waitMinutes: nil)
        #expect(vm.estimate.waitMinutes == 25)
    }

    @Test("submitReport replaces wait when new waitMinutes provided")
    func submitReportReplacesWait() async {
        var venue = TestFactories.makeVenue(busyness: .moderate)
        venue.estimatedWaitMinutes = 25
        let vm = VenueDetailViewModel(venue: venue)
        await vm.submitReport(level: .busy, waitMinutes: 10)
        #expect(vm.estimate.waitMinutes == 10)
    }

    @Test("submitReport with zero wait minutes")
    func submitReportZeroWait() async {
        let vm = VenueDetailViewModel(venue: TestFactories.makeVenue())
        await vm.submitReport(level: .empty, waitMinutes: 0)
        #expect(vm.estimate.waitMinutes == 0)
        #expect(vm.estimate.level == .empty)
    }

    @Test("Multiple reports increment count correctly")
    func multipleReportsIncrementCount() async {
        let vm = VenueDetailViewModel(venue: TestFactories.makeVenue())
        let initial = vm.estimate.reportCount
        await vm.submitReport(level: .busy, waitMinutes: nil)
        await vm.submitReport(level: .packed, waitMinutes: nil)
        #expect(vm.estimate.reportCount == initial + 2)
    }

    @Test("submitReport stays low confidence below threshold")
    func submitReportLowConfidenceBelowThreshold() async {
        var venue = TestFactories.makeVenue(busyness: .quiet)
        venue.reportCount = 0
        venue.busynessConfidence = .none
        let vm = VenueDetailViewModel(venue: venue)
        await vm.submitReport(level: .busy, waitMinutes: nil)
        #expect(vm.estimate.confidence == .low)
    }

    // MARK: - isWithinReportRange Initial State

    @Test("isWithinReportRange starts false")
    func isWithinReportRangeStartsFalse() {
        let vm = VenueDetailViewModel(venue: TestFactories.makeVenue())
        #expect(vm.isWithinReportRange == false)
    }

    // MARK: - Venue Reference

    @Test("venue property matches initialization venue")
    func venuePropertyMatches() {
        let venue = TestFactories.makeVenue(name: "My Bar")
        let vm = VenueDetailViewModel(venue: venue)
        #expect(vm.venue.id == venue.id)
        #expect(vm.venue.name == "My Bar")
    }

    // MARK: - All Busyness Levels

    @Test("Estimate correctly initializes for each busyness level")
    func estimateForEachLevel() {
        for level in BusynessLevel.allCases {
            let venue = TestFactories.makeVenue(busyness: level)
            let vm = VenueDetailViewModel(venue: venue)
            #expect(vm.estimate.level == level)
        }
    }
}
