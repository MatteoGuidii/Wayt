import Testing
import Foundation
import CoreLocation
@testable import Wayt

@Suite("SavedVenue")
struct SavedVenueTests {

    // MARK: - Identity

    @Test("id returns venueId")
    func idMatchesVenueId() {
        let saved = SavedVenue(
            venueId: "test-bar_43.65000_-79.38000",
            venueName: "Test Bar",
            categoryRaw: "drinks",
            lat: 43.65,
            lng: -79.38,
            address: "123 Main St",
            savedAt: "2025-01-15T10:30:00Z"
        )
        #expect(saved.id == saved.venueId)
    }

    // MARK: - Computed Category

    @Test("categoryRaw 'food' maps to .food")
    func categoryRawFood() {
        let saved = SavedVenue(
            venueId: "v1", venueName: "Pizza", categoryRaw: "food",
            lat: 0, lng: 0, address: nil, savedAt: ""
        )
        #expect(saved.category == .food)
    }

    @Test("categoryRaw 'drinks' maps to .drinks")
    func categoryRawDrinks() {
        let saved = SavedVenue(
            venueId: "v1", venueName: "Bar", categoryRaw: "drinks",
            lat: 0, lng: 0, address: nil, savedAt: ""
        )
        #expect(saved.category == .drinks)
    }

    @Test("categoryRaw 'nightlife' maps to .nightlife")
    func categoryRawNightlife() {
        let saved = SavedVenue(
            venueId: "v1", venueName: "Club", categoryRaw: "nightlife",
            lat: 0, lng: 0, address: nil, savedAt: ""
        )
        #expect(saved.category == .nightlife)
    }

    @Test("categoryRaw 'coffee' maps to .coffee")
    func categoryRawCoffee() {
        let saved = SavedVenue(
            venueId: "v1", venueName: "Cafe", categoryRaw: "coffee",
            lat: 0, lng: 0, address: nil, savedAt: ""
        )
        #expect(saved.category == .coffee)
    }

    @Test("Unknown categoryRaw defaults to .food")
    func unknownCategoryRawDefaultsToFood() {
        let saved = SavedVenue(
            venueId: "v1", venueName: "Unknown", categoryRaw: "invalid_category",
            lat: 0, lng: 0, address: nil, savedAt: ""
        )
        #expect(saved.category == .food)
    }

    @Test("Empty categoryRaw defaults to .food")
    func emptyCategoryRawDefaultsToFood() {
        let saved = SavedVenue(
            venueId: "v1", venueName: "Place", categoryRaw: "",
            lat: 0, lng: 0, address: nil, savedAt: ""
        )
        #expect(saved.category == .food)
    }

    // MARK: - Computed Coordinate

    @Test("coordinate returns correct CLLocationCoordinate2D")
    func coordinateIsCorrect() {
        let saved = SavedVenue(
            venueId: "v1", venueName: "Place", categoryRaw: "food",
            lat: 43.65107, lng: -79.34723, address: nil, savedAt: ""
        )
        #expect(saved.coordinate.latitude == 43.65107)
        #expect(saved.coordinate.longitude == -79.34723)
    }

    @Test("Negative coordinates work correctly")
    func negativeCoordinates() {
        let saved = SavedVenue(
            venueId: "v1", venueName: "Place", categoryRaw: "food",
            lat: -33.8688, lng: 151.2093, address: nil, savedAt: ""
        )
        #expect(saved.coordinate.latitude == -33.8688)
        #expect(saved.coordinate.longitude == 151.2093)
    }

    @Test("Zero coordinates work correctly")
    func zeroCoordinates() {
        let saved = SavedVenue(
            venueId: "v1", venueName: "Place", categoryRaw: "food",
            lat: 0, lng: 0, address: nil, savedAt: ""
        )
        #expect(saved.coordinate.latitude == 0)
        #expect(saved.coordinate.longitude == 0)
    }

    // MARK: - Codable

    @Test("SavedVenue round-trips through JSON")
    func codableRoundTrip() throws {
        let original = SavedVenue(
            venueId: "test-bar_43.65000_-79.38000",
            venueName: "Test Bar",
            categoryRaw: "drinks",
            lat: 43.65,
            lng: -79.38,
            address: "123 Main St",
            savedAt: "2025-01-15T10:30:00Z"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SavedVenue.self, from: data)
        #expect(decoded.venueId == original.venueId)
        #expect(decoded.venueName == original.venueName)
        #expect(decoded.categoryRaw == original.categoryRaw)
        #expect(decoded.lat == original.lat)
        #expect(decoded.lng == original.lng)
        #expect(decoded.address == original.address)
        #expect(decoded.savedAt == original.savedAt)
    }

    @Test("SavedVenue decodes with nil address")
    func codableNilAddress() throws {
        let json = """
        {
            "venueId": "v1",
            "venueName": "Place",
            "categoryRaw": "food",
            "lat": 0,
            "lng": 0,
            "savedAt": "2025-01-01"
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(SavedVenue.self, from: json)
        #expect(decoded.address == nil)
    }

    @Test("SavedVenue decodes with address present")
    func codableWithAddress() throws {
        let json = """
        {
            "venueId": "v1",
            "venueName": "Place",
            "categoryRaw": "food",
            "lat": 0,
            "lng": 0,
            "address": "456 Oak Ave",
            "savedAt": "2025-01-01"
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(SavedVenue.self, from: json)
        #expect(decoded.address == "456 Oak Ave")
    }

    // MARK: - Edge Cases

    @Test("Venue name with special characters preserves correctly")
    func specialCharactersInName() throws {
        let original = SavedVenue(
            venueId: "v1", venueName: "Café Résumé & Bar's",
            categoryRaw: "coffee", lat: 0, lng: 0, address: nil, savedAt: ""
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SavedVenue.self, from: data)
        #expect(decoded.venueName == "Café Résumé & Bar's")
    }

    @Test("Very long venue name encodes correctly")
    func longVenueName() throws {
        let longName = String(repeating: "A", count: 500)
        let original = SavedVenue(
            venueId: "v1", venueName: longName,
            categoryRaw: "food", lat: 0, lng: 0, address: nil, savedAt: ""
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SavedVenue.self, from: data)
        #expect(decoded.venueName == longName)
    }
}
