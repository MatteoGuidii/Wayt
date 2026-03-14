import Testing
import MapKit
@testable import Venuu

@Suite("Venue")
@MainActor
struct VenueTests {

    // MARK: - ID Generation

    @Test("Same name and coordinates produce the same ID")
    func sameNameAndCoordinatesSameID() {
        let coord = CLLocationCoordinate2D(latitude: 43.65107, longitude: -79.34723)
        let v1 = TestFactories.makeVenue(name: "Ace Bar", type: .bar, coordinate: coord)
        let v2 = TestFactories.makeVenue(name: "Ace Bar", type: .bar, coordinate: coord)
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
        // Both coordinates round to the same 5-decimal value (43.65107, -79.34723)
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

    // MARK: - Equality

    @Test("Two venues with the same ID are equal")
    func sameIDMeansEqual() {
        let coord = CLLocationCoordinate2D(latitude: 43.65107, longitude: -79.34723)
        let v1 = TestFactories.makeVenue(name: "The Pub", coordinate: coord)
        let v2 = TestFactories.makeVenue(name: "The Pub", coordinate: coord)
        #expect(v1 == v2)
    }
}
