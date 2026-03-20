import Testing
import Foundation
@testable import Venuu

@Suite("SavedVenuesService Cache", .serialized)
struct SavedVenuesServiceCacheTests {

    private let testKey = "savedVenueIDs"

    private func cleanUp() {
        UserDefaults.standard.removeObject(forKey: testKey)
        UserDefaults.standard.synchronize()
    }

    // MARK: - loadCachedIDs

    @Test("loadCachedIDs returns empty set when no cache exists")
    func loadCachedIDsEmpty() {
        cleanUp()
        let service = SavedVenuesService()
        service.clearCache()
        let ids = service.loadCachedIDs()
        #expect(ids.isEmpty)
        cleanUp()
    }

    @Test("loadCachedIDs returns previously persisted IDs")
    func loadCachedIDsReturnsPersisted() {
        cleanUp()
        let service = SavedVenuesService()
        let originalIDs: Set<String> = ["svc-venue-1", "svc-venue-2", "svc-venue-3"]
        service.persistIDs(originalIDs)

        let loaded = service.loadCachedIDs()
        #expect(loaded == originalIDs)
        cleanUp()
    }

    // MARK: - persistIDs

    @Test("persistIDs stores IDs that survive reload")
    func persistIDsSurvivesReload() {
        cleanUp()
        let service = SavedVenuesService()
        service.persistIDs(["svc-a", "svc-b", "svc-c"])

        let service2 = SavedVenuesService()
        let loaded = service2.loadCachedIDs()
        #expect(loaded == ["svc-a", "svc-b", "svc-c"])
        cleanUp()
    }

    @Test("persistIDs with empty set clears previous data")
    func persistIDsEmptySet() {
        cleanUp()
        let service = SavedVenuesService()
        service.persistIDs(["svc-x", "svc-y"])
        service.persistIDs([])

        let loaded = service.loadCachedIDs()
        #expect(loaded.isEmpty)
        cleanUp()
    }

    @Test("persistIDs overwrites previous IDs completely")
    func persistIDsOverwrites() {
        cleanUp()
        let service = SavedVenuesService()
        service.persistIDs(["svc-old-1", "svc-old-2"])
        service.persistIDs(["svc-new-1"])

        let loaded = service.loadCachedIDs()
        #expect(loaded == ["svc-new-1"])
        #expect(!loaded.contains("svc-old-1"))
        cleanUp()
    }

    @Test("persistIDs handles large set of IDs")
    func persistIDsLargeSet() {
        cleanUp()
        let service = SavedVenuesService()
        let largeSet = Set((0..<100).map { "svc-venue-\($0)" })
        service.persistIDs(largeSet)

        let loaded = service.loadCachedIDs()
        #expect(loaded.count == 100)
        #expect(loaded == largeSet)
        cleanUp()
    }

    @Test("persistIDs handles IDs with special characters")
    func persistIDsSpecialChars() {
        cleanUp()
        let service = SavedVenuesService()
        let ids: Set<String> = ["café résumé_43.65000_-79.38000", "bar & grill_0.00000_0.00000"]
        service.persistIDs(ids)

        let loaded = service.loadCachedIDs()
        #expect(loaded == ids)
        cleanUp()
    }

    // MARK: - clearCache

    @Test("clearCache removes all cached IDs")
    func clearCacheRemovesAll() {
        cleanUp()
        let service = SavedVenuesService()
        service.persistIDs(["svc-a", "svc-b", "svc-c"])
        service.clearCache()

        let loaded = service.loadCachedIDs()
        #expect(loaded.isEmpty)
        cleanUp()
    }

    @Test("clearCache is safe when no cache exists")
    func clearCacheWhenEmpty() {
        cleanUp()
        let service = SavedVenuesService()
        service.clearCache()
        let loaded = service.loadCachedIDs()
        #expect(loaded.isEmpty)
        cleanUp()
    }

    @Test("clearCache followed by persist works correctly")
    func clearThenPersist() {
        cleanUp()
        let service = SavedVenuesService()
        service.persistIDs(["svc-a", "svc-b"])
        service.clearCache()
        service.persistIDs(["svc-c"])

        let loaded = service.loadCachedIDs()
        #expect(loaded.contains("svc-c"))
        #expect(!loaded.contains("svc-a"))
        #expect(!loaded.contains("svc-b"))
        cleanUp()
    }

    // MARK: - Corrupted Data

    @Test("loadCachedIDs returns empty on corrupted data")
    func loadCachedIDsCorruptedData() {
        cleanUp()
        UserDefaults.standard.set("not valid json".data(using: .utf8), forKey: testKey)

        let service = SavedVenuesService()
        let loaded = service.loadCachedIDs()
        #expect(loaded.isEmpty)
        cleanUp()
    }

    @Test("loadCachedIDs returns empty when wrong type stored")
    func loadCachedIDsWrongType() {
        cleanUp()
        // Integer stored instead of Data
        UserDefaults.standard.set(42, forKey: testKey)

        let service = SavedVenuesService()
        let loaded = service.loadCachedIDs()
        // Should gracefully handle: data(forKey:) returns nil for non-Data types
        #expect(loaded.isEmpty)
        cleanUp()
    }
}
