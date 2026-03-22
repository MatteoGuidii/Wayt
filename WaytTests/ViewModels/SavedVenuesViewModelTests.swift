import Testing
import Foundation
@testable import Wayt

@Suite("SavedVenuesViewModel", .serialized)
@MainActor
struct SavedVenuesViewModelTests {

    private func cleanUp() {
        let service = SavedVenuesService()
        service.clearCache()
    }

    // MARK: - Initial State

    @Test("Initial savedVenues array is empty")
    func initialSavedVenuesEmpty() {
        cleanUp()
        let vm = SavedVenuesViewModel()
        #expect(vm.savedVenues.isEmpty)
        cleanUp()
    }

    @Test("isLoading starts false")
    func isLoadingStartsFalse() {
        cleanUp()
        let vm = SavedVenuesViewModel()
        #expect(vm.isLoading == false)
        cleanUp()
    }

    // MARK: - isSaved (in-memory)

    @Test("isSaved returns true after manual insert")
    func isSavedReturnsTrue() {
        cleanUp()
        let vm = SavedVenuesViewModel()
        vm.savedVenueIDs.insert("my-venue")
        #expect(vm.isSaved("my-venue") == true)
        cleanUp()
    }

    @Test("isSaved returns false for unsaved venue")
    func isSavedReturnsFalse() {
        cleanUp()
        let vm = SavedVenuesViewModel()
        #expect(vm.isSaved("nonexistent") == false)
        cleanUp()
    }

    @Test("isSaved is case-sensitive")
    func isSavedCaseSensitive() {
        cleanUp()
        let vm = SavedVenuesViewModel()
        vm.savedVenueIDs.insert("My-Venue")
        #expect(vm.isSaved("My-Venue") == true)
        #expect(vm.isSaved("my-venue") == false)
        cleanUp()
    }

    // MARK: - Reset

    @Test("reset clears all saved venue data")
    func resetClearsAll() {
        cleanUp()
        let vm = SavedVenuesViewModel()
        vm.savedVenueIDs = ["venue-1", "venue-2"]
        vm.reset()
        #expect(vm.savedVenueIDs.isEmpty)
        #expect(vm.savedVenues.isEmpty)
        cleanUp()
    }

    @Test("reset clears cache so new instance starts empty")
    func resetClearsCache() {
        cleanUp()
        let vm = SavedVenuesViewModel()
        vm.savedVenueIDs.insert("venue-1")
        // Persist it via the service
        let service = SavedVenuesService()
        service.persistIDs(vm.savedVenueIDs)
        vm.reset()

        let vm2 = SavedVenuesViewModel()
        #expect(vm2.savedVenueIDs.isEmpty)
        cleanUp()
    }

    @Test("reset is idempotent")
    func resetIdempotent() {
        cleanUp()
        let vm = SavedVenuesViewModel()
        vm.reset()
        vm.reset()
        #expect(vm.savedVenueIDs.isEmpty)
        #expect(vm.savedVenues.isEmpty)
        cleanUp()
    }

    // MARK: - Optimistic Updates

    @Test("savedVenueIDs insert reflects immediately")
    func optimisticInsert() {
        cleanUp()
        let vm = SavedVenuesViewModel()
        vm.savedVenueIDs.insert("new-venue")
        #expect(vm.isSaved("new-venue") == true)
        cleanUp()
    }

    @Test("savedVenueIDs removal reflects immediately")
    func optimisticRemoval() {
        cleanUp()
        let vm = SavedVenuesViewModel()
        vm.savedVenueIDs.insert("venue-to-remove")
        vm.savedVenueIDs.remove("venue-to-remove")
        #expect(vm.isSaved("venue-to-remove") == false)
        cleanUp()
    }

    // MARK: - Multiple Venues

    @Test("Multiple venues can be tracked simultaneously")
    func multipleVenues() {
        cleanUp()
        let vm = SavedVenuesViewModel()
        vm.savedVenueIDs = ["v1", "v2", "v3"]
        #expect(vm.isSaved("v1") == true)
        #expect(vm.isSaved("v2") == true)
        #expect(vm.isSaved("v3") == true)
        #expect(vm.isSaved("v4") == false)
        cleanUp()
    }

    @Test("Removing one venue doesn't affect others")
    func removeOneDoesNotAffectOthers() {
        cleanUp()
        let vm = SavedVenuesViewModel()
        vm.savedVenueIDs = ["v1", "v2", "v3"]
        vm.savedVenueIDs.remove("v2")
        #expect(vm.isSaved("v1") == true)
        #expect(vm.isSaved("v2") == false)
        #expect(vm.isSaved("v3") == true)
        cleanUp()
    }
}
