import Testing
import MapKit
@testable import Wayt

@Suite("Venue")
@MainActor
struct VenueTests {

    // MARK: - ID Generation

    @Test("Same name and coordinates produce the same ID")
    func sameNameAndCoordinatesSameID() {
        let coord = CLLocationCoordinate2D(latitude: 43.65107, longitude: -79.34723)
        let v1 = TestFactories.makeVenue(name: "Ace Bar", coordinate: coord)
        let v2 = TestFactories.makeVenue(name: "Ace Bar", coordinate: coord)
        #expect(v1.id == v2.id)
    }

    @Test("Different names at same coordinates produce different IDs")
    func differentNamesSameCoordinatesDifferentIDs() {
        let coord = CLLocationCoordinate2D(latitude: 43.65107, longitude: -79.34723)
        let v1 = TestFactories.makeVenue(name: "Ace Bar",  coordinate: coord)
        let v2 = TestFactories.makeVenue(name: "Blue Bar", coordinate: coord)
        #expect(v1.id != v2.id)
    }

    @Test("Same name at different coordinates produce different IDs")
    func sameNameDifferentCoordinatesDifferentIDs() {
        let coord1 = CLLocationCoordinate2D(latitude: 43.65107, longitude: -79.34723)
        let coord2 = CLLocationCoordinate2D(latitude: 43.70000, longitude: -79.40000)
        let v1 = TestFactories.makeVenue(name: "Ace Bar", coordinate: coord1)
        let v2 = TestFactories.makeVenue(name: "Ace Bar", coordinate: coord2)
        #expect(v1.id != v2.id)
    }

    @Test("ID uses lowercased name")
    func idUsesLowercasedName() {
        let coord = CLLocationCoordinate2D(latitude: 43.65107, longitude: -79.34723)
        let v1 = TestFactories.makeVenue(name: "ACE BAR", coordinate: coord)
        let v2 = TestFactories.makeVenue(name: "ace bar", coordinate: coord)
        #expect(v1.id == v2.id)
    }

    @Test("ID uses 5-decimal coordinate precision")
    func idUsesFiveDecimalPrecision() {
        let coord1 = CLLocationCoordinate2D(latitude: 43.651071, longitude: -79.347231)
        let coord2 = CLLocationCoordinate2D(latitude: 43.651074, longitude: -79.347234)
        let v1 = TestFactories.makeVenue(name: "Same Bar", coordinate: coord1)
        let v2 = TestFactories.makeVenue(name: "Same Bar", coordinate: coord2)
        #expect(v1.id == v2.id)
    }

    // MARK: - Default Busyness Values

    @Test("New venue has nil busyness")
    func defaultBusynessIsNil() {
        let venue = TestFactories.makeVenue()
        #expect(venue.busyness == nil)
    }

    @Test("New venue has .none confidence")
    func defaultConfidenceIsNone() {
        let venue = TestFactories.makeVenue()
        #expect(venue.busynessConfidence == .none)
    }

    @Test("New venue has zero reportCount")
    func defaultReportCountIsZero() {
        let venue = TestFactories.makeVenue()
        #expect(venue.reportCount == 0)
    }

    @Test("New venue has nil estimatedWaitMinutes")
    func defaultWaitMinutesIsNil() {
        let venue = TestFactories.makeVenue()
        #expect(venue.estimatedWaitMinutes == nil)
    }

    // MARK: - Mutability

    @Test("Busyness can be set after creation")
    func busynessIsMutable() {
        var venue = TestFactories.makeVenue()
        venue.busyness = .busy
        #expect(venue.busyness == .busy)
    }

    @Test("Confidence can be set after creation")
    func confidenceIsMutable() {
        var venue = TestFactories.makeVenue()
        venue.busynessConfidence = .high
        #expect(venue.busynessConfidence == .high)
    }

    @Test("reportCount can be set after creation")
    func reportCountIsMutable() {
        var venue = TestFactories.makeVenue()
        venue.reportCount = 7
        #expect(venue.reportCount == 7)
    }

    @Test("estimatedWaitMinutes can be set after creation")
    func waitMinutesIsMutable() {
        var venue = TestFactories.makeVenue()
        venue.estimatedWaitMinutes = 25
        #expect(venue.estimatedWaitMinutes == 25)
    }

    // MARK: - Equality (includes busyness state)

    @Test("Same ID and same busyness state are equal")
    func sameIDSameBusynessEqual() {
        let coord = CLLocationCoordinate2D(latitude: 43.65107, longitude: -79.34723)
        let v1 = TestFactories.makeVenue(name: "The Pub", busyness: .busy, coordinate: coord)
        let v2 = TestFactories.makeVenue(name: "The Pub", busyness: .busy, coordinate: coord)
        #expect(v1 == v2)
    }

    @Test("Same ID but different busyness are NOT equal")
    func sameIDDifferentBusynessNotEqual() {
        let coord = CLLocationCoordinate2D(latitude: 43.65107, longitude: -79.34723)
        let v1 = TestFactories.makeVenue(name: "The Pub", busyness: .quiet, coordinate: coord)
        let v2 = TestFactories.makeVenue(name: "The Pub", busyness: .packed, coordinate: coord)
        #expect(v1 != v2)
    }

    @Test("Same ID but different confidence are NOT equal")
    func sameIDDifferentConfidenceNotEqual() {
        let coord = CLLocationCoordinate2D(latitude: 43.65107, longitude: -79.34723)
        var v1 = TestFactories.makeVenue(name: "The Pub", coordinate: coord)
        var v2 = TestFactories.makeVenue(name: "The Pub", coordinate: coord)
        v1.busynessConfidence = .low
        v2.busynessConfidence = .high
        #expect(v1 != v2)
    }

    @Test("Same ID but different reportCount are NOT equal")
    func sameIDDifferentReportCountNotEqual() {
        let coord = CLLocationCoordinate2D(latitude: 43.65107, longitude: -79.34723)
        var v1 = TestFactories.makeVenue(name: "The Pub", coordinate: coord)
        var v2 = TestFactories.makeVenue(name: "The Pub", coordinate: coord)
        v1.reportCount = 1
        v2.reportCount = 5
        #expect(v1 != v2)
    }

    @Test("Same ID but different estimatedWaitMinutes are NOT equal")
    func sameIDDifferentWaitNotEqual() {
        let coord = CLLocationCoordinate2D(latitude: 43.65107, longitude: -79.34723)
        var v1 = TestFactories.makeVenue(name: "The Pub", coordinate: coord)
        var v2 = TestFactories.makeVenue(name: "The Pub", coordinate: coord)
        v1.estimatedWaitMinutes = 10
        v2.estimatedWaitMinutes = 30
        #expect(v1 != v2)
    }

    @Test("Two default venues with same ID are equal")
    func twoDefaultVenuesEqual() {
        let coord = CLLocationCoordinate2D(latitude: 43.65107, longitude: -79.34723)
        let v1 = TestFactories.makeVenue(name: "The Pub", coordinate: coord)
        let v2 = TestFactories.makeVenue(name: "The Pub", coordinate: coord)
        #expect(v1 == v2)
    }

    // MARK: - Hashable

    @Test("Hash is based on ID — same ID venues hash equally")
    func sameIDSameHash() {
        let coord = CLLocationCoordinate2D(latitude: 43.65107, longitude: -79.34723)
        let v1 = TestFactories.makeVenue(name: "The Pub", busyness: .quiet, coordinate: coord)
        let v2 = TestFactories.makeVenue(name: "The Pub", busyness: .packed, coordinate: coord)
        #expect(v1.hashValue == v2.hashValue)
    }

    @Test("Venues with same ID but different busyness can coexist in Set via equality")
    func setDeduplicationRespectsEquality() {
        let coord = CLLocationCoordinate2D(latitude: 43.65107, longitude: -79.34723)
        let v1 = TestFactories.makeVenue(name: "The Pub", busyness: .quiet, coordinate: coord)
        var v2 = TestFactories.makeVenue(name: "The Pub", busyness: .packed, coordinate: coord)

        // Same hash but different equality → Set may store both (hash collision bucket)
        // But in practice, Set uses both hash AND == for dedup.
        // Since v1 != v2 (different busyness), Set should keep both.
        var set = Set<Venue>()
        set.insert(v1)
        set.insert(v2)
        // Both should be in the set since they are not equal
        #expect(set.count == 2)

        // But if busyness matches, they are equal and should dedup
        v2.busyness = .quiet
        var set2 = Set<Venue>()
        set2.insert(v1)
        set2.insert(v2)
        #expect(set2.count == 1)
    }

    // MARK: - onChange Detection (the reason equality was updated)

    @Test("Array equality detects busyness changes for SwiftUI onChange")
    func arrayEqualityDetectsBusynessChange() {
        let coord = CLLocationCoordinate2D(latitude: 43.65107, longitude: -79.34723)
        let v1 = TestFactories.makeVenue(name: "Bar", busyness: .quiet, coordinate: coord)
        var v2 = TestFactories.makeVenue(name: "Bar", busyness: .quiet, coordinate: coord)

        let array1 = [v1]
        let array2 = [v2]
        #expect(array1 == array2, "Same busyness → arrays should be equal")

        v2.busyness = .packed
        let array3 = [v2]
        #expect(array1 != array3, "Different busyness → arrays should NOT be equal (triggers onChange)")
    }
}
