import Testing
import SwiftUI
import MapKit
@testable import Wayt

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

    // MARK: - Name-Based Fallback: Nightlife Keywords

    @Test("Name containing 'disco' maps to .nightlife")
    func discoNameMapsToNightlife() {
        #expect(VenueCategory.from(name: "Disco Inferno") == .nightlife)
    }

    @Test("Name containing 'lounge' maps to .nightlife")
    func loungeNameMapsToNightlife() {
        #expect(VenueCategory.from(name: "The Velvet Lounge") == .nightlife)
    }

    @Test("Name containing 'karaoke' maps to .nightlife")
    func karaokeNameMapsToNightlife() {
        #expect(VenueCategory.from(name: "Karaoke Night") == .nightlife)
    }

    @Test("Name containing 'hookah' maps to .nightlife")
    func hookahNameMapsToNightlife() {
        #expect(VenueCategory.from(name: "Hookah Palace") == .nightlife)
    }

    // MARK: - Name-Based Fallback: Drinks Keywords

    @Test("Name containing 'pub' maps to .drinks")
    func pubNameMapsToDrinks() {
        #expect(VenueCategory.from(name: "The Irish Pub") == .drinks)
    }

    @Test("Name containing 'brew' maps to .drinks")
    func brewNameMapsToDrinks() {
        #expect(VenueCategory.from(name: "BrewDog") == .drinks)
    }

    @Test("Name containing 'cocktail' maps to .drinks")
    func cocktailNameMapsToDrinks() {
        #expect(VenueCategory.from(name: "Cocktail Emporium") == .drinks)
    }

    @Test("Name containing 'tapas' maps to .drinks")
    func tapasNameMapsToDrinks() {
        #expect(VenueCategory.from(name: "Tapas & Wine") == .drinks)
    }

    @Test("Name containing 'wine bar' maps to .drinks")
    func wineBarNameMapsToDrinks() {
        #expect(VenueCategory.from(name: "Wine Bar XYZ") == .drinks)
    }

    @Test("Name containing 'beer garden' maps to .drinks")
    func beerGardenNameMapsToDrinks() {
        #expect(VenueCategory.from(name: "The Beer Garden") == .drinks)
    }

    // MARK: - Name-Based Fallback: Coffee Keywords

    @Test("Name containing 'café' (accented) maps to .coffee")
    func cafeAccentedMapsToCoffee() {
        #expect(VenueCategory.from(name: "Le Café") == .coffee)
    }

    @Test("Name containing 'bakery' maps to .coffee")
    func bakeryNameMapsToCoffee() {
        #expect(VenueCategory.from(name: "Sunrise Bakery") == .coffee)
    }

    @Test("Name containing 'tea' maps to .coffee")
    func teaNameMapsToCoffee() {
        #expect(VenueCategory.from(name: "Tea House") == .coffee)
    }

    @Test("Name containing 'dessert' maps to .coffee")
    func dessertNameMapsToCoffee() {
        #expect(VenueCategory.from(name: "Sweet Dessert Shop") == .coffee)
    }

    @Test("Name containing 'juice' maps to .coffee")
    func juiceNameMapsToCoffee() {
        #expect(VenueCategory.from(name: "Fresh Juice Co") == .coffee)
    }

    @Test("Name containing 'ice cream' maps to .coffee")
    func iceCreamNameMapsToCoffee() {
        #expect(VenueCategory.from(name: "Ice Cream Paradise") == .coffee)
    }

    @Test("Name containing 'pastry' maps to .coffee")
    func pastryNameMapsToCoffee() {
        #expect(VenueCategory.from(name: "Pastry Shop") == .coffee)
    }

    // MARK: - Name-Based Fallback: Priority / Ambiguity

    @Test("'Club Bar' matches nightlife (club checked before bar)")
    func clubBarPrioritizesNightlife() {
        #expect(VenueCategory.from(name: "Club Bar") == .nightlife)
    }

    @Test("'Bar Café' matches drinks (bar checked before café)")
    func barCafePrioritizesDrinks() {
        #expect(VenueCategory.from(name: "Bar Café") == .drinks)
    }

    @Test("Case insensitive matching works")
    func caseInsensitiveMatching() {
        #expect(VenueCategory.from(name: "THE COCKTAIL BAR") == .drinks)
        #expect(VenueCategory.from(name: "COFFEE SHOP") == .coffee)
        #expect(VenueCategory.from(name: "NIGHT CLUB") == .nightlife)
    }

    @Test("Empty name defaults to .food")
    func emptyNameDefaultsToFood() {
        #expect(VenueCategory.from(name: "") == .food)
    }

    // MARK: - shortName

    @Test("All categories have non-empty shortName")
    func allCategoriesHaveNonEmptyShortName() {
        for cat in VenueCategory.allCases {
            #expect(!cat.shortName.isEmpty, "shortName for \(cat) is empty")
        }
    }

    // MARK: - Codable

    @Test("VenueCategory round-trips through JSON")
    func codableRoundTrip() throws {
        for cat in VenueCategory.allCases {
            let data = try JSONEncoder().encode(cat)
            let decoded = try JSONDecoder().decode(VenueCategory.self, from: data)
            #expect(decoded == cat)
        }
    }

    @Test("Invalid raw value fails to decode")
    func invalidRawValueFails() {
        let json = "\"pizza\"".data(using: .utf8)!
        let decoded = try? JSONDecoder().decode(VenueCategory.self, from: json)
        #expect(decoded == nil)
    }
}
