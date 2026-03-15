import Testing
import SwiftUI
import MapKit
@testable import Venuu

@Suite("VenueCategory")
struct VenueCategoryTests {

    // MARK: - Case Count

    @Test("All 4 venue categories are defined")
    func allCasesCount() {
        #expect(VenueCategory.allCases.count == 4)
    }

    // MARK: - Display Properties

    @Test("All categories have non-empty displayName")
    func allCategoriesHaveNonEmptyDisplayName() {
        for cat in VenueCategory.allCases {
            #expect(!cat.displayName.isEmpty, "displayName for \(cat) is empty")
        }
    }

    @Test("All categories have non-empty icon")
    func allCategoriesHaveNonEmptyIcon() {
        for cat in VenueCategory.allCases {
            #expect(!cat.icon.isEmpty, "icon for \(cat) is empty")
        }
    }

    // MARK: - POI Category Mapping

    @Test("Nightlife POI maps to .nightlife")
    func nightlifePOIMapsCorrectly() {
        #expect(VenueCategory.from(poiCategory: .nightlife) == .nightlife)
    }

    @Test("Cafe POI maps to .coffee")
    func cafePOIMapsCorrectly() {
        #expect(VenueCategory.from(poiCategory: .cafe) == .coffee)
    }

    @Test("Bakery POI maps to .coffee")
    func bakeryPOIMapsCorrectly() {
        #expect(VenueCategory.from(poiCategory: .bakery) == .coffee)
    }

    @Test("Brewery POI maps to .drinks")
    func breweryPOIMapsCorrectly() {
        #expect(VenueCategory.from(poiCategory: .brewery) == .drinks)
    }

    @Test("Winery POI maps to .drinks")
    func wineryPOIMapsCorrectly() {
        #expect(VenueCategory.from(poiCategory: .winery) == .drinks)
    }

    @Test("Restaurant POI maps to .food")
    func restaurantPOIMapsCorrectly() {
        #expect(VenueCategory.from(poiCategory: .restaurant) == .food)
    }

    @Test("nil POI defaults to .food")
    func nilPOIDefaultsToFood() {
        #expect(VenueCategory.from(poiCategory: nil) == .food)
    }

    // MARK: - Name-Based Fallback

    @Test("Name containing 'club' maps to .nightlife")
    func clubNameMapsToNightlife() {
        #expect(VenueCategory.from(name: "The Jazz Club") == .nightlife)
    }

    @Test("Name containing 'bar' maps to .drinks")
    func barNameMapsToDrinks() {
        #expect(VenueCategory.from(name: "Cocktail Bar") == .drinks)
    }

    @Test("Name containing 'cafe' maps to .coffee")
    func cafeNameMapsToCoffee() {
        #expect(VenueCategory.from(name: "Sunny Cafe") == .coffee)
    }

    @Test("Name containing 'coffee' maps to .coffee")
    func coffeeNameMapsToCoffee() {
        #expect(VenueCategory.from(name: "Blue Bottle Coffee") == .coffee)
    }

    @Test("Generic name defaults to .food")
    func genericNameDefaultsToFood() {
        #expect(VenueCategory.from(name: "The Golden Spoon") == .food)
    }

    // MARK: - Uniqueness

    @Test("All categories have unique icons")
    func allCategoriesHaveUniqueIcons() {
        let icons = VenueCategory.allCases.map { $0.icon }
        #expect(Set(icons).count == VenueCategory.allCases.count)
    }

    // MARK: - Raw Values

    @Test("Raw values match enum case names")
    func rawValuesMatchCaseNames() {
        #expect(VenueCategory.food.rawValue == "food")
        #expect(VenueCategory.drinks.rawValue == "drinks")
        #expect(VenueCategory.nightlife.rawValue == "nightlife")
        #expect(VenueCategory.coffee.rawValue == "coffee")
    }
}
