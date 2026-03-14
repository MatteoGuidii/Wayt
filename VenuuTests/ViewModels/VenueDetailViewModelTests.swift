import Testing
import Foundation
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

    @Test("Estimate falls back to heuristic when venue has no busyness")
    func estimateFallsBackToHeuristicWhenNoBusyness() {
        let venue = TestFactories.makeVenue(busyness: nil)
        let vm = VenueDetailViewModel(venue: venue)
        #expect(vm.estimate.confidence == .estimated)
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
}
