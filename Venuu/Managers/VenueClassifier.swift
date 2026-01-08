import Foundation
import MapKit

/// Simple venue type classifier for UI display purposes
struct VenueClassifier {

    // MARK: - Fast Food Exclusion List (Worldwide)

    /// Global fast food chains and quick service restaurants to exclude
    static let fastFoodExclusions: Set<String> = [
        // Global fast food chains
        "mcdonald", "burger king", "kfc", "subway", "domino's", "dominos",
        "pizza hut", "taco bell", "wendy's", "wendys", "papa john", "papa johns",

        // US chains
        "chipotle", "panera", "qdoba", "five guys", "shake shack",
        "chick-fil-a", "chickfila", "chick fil a", "popeyes", "popeye's",
        "arby's", "arbys", "sonic drive", "jack in the box",
        "carl's jr", "carls jr", "hardee's", "hardees", "white castle",
        "whataburger", "in-n-out", "in n out", "innout",
        "little caesars", "little caesar", "wingstop", "buffalo wild wings",
        "jersey mike", "jimmy john", "firehouse subs", "jason's deli",
        "panda express", "pei wei", "waba grill", "del taco",
        "el pollo loco", "raising cane", "zaxby", "bojangles",
        "culver's", "culvers", "steak n shake", "steak 'n shake",
        "checkers", "rally's", "rallys", "krystal",
        "church's chicken", "churchs chicken", "long john silver",
        "captain d's", "captain ds",

        // Casual dining chains (borderline fast food)
        "applebee's", "applebees", "chili's", "chilis",
        "olive garden", "red lobster", "outback steakhouse",
        "texas roadhouse", "longhorn steakhouse", "cracker barrel",
        "denny's", "dennys", "ihop", "waffle house",
        "golden corral", "hometown buffet", "cici's pizza", "cicis",
        "fazoli's", "fazolis",

        // European chains
        "pret a manger", "pret", "greggs", "leon",
        "wetherspoon", "spoons", "nando's", "nandos",
        "pizza express", "ask italian", "yo! sushi", "yo sushi",
        "zizzi", "prezzo", "frankie & benny", "frankie and benny",
        "bella italia", "cafe rouge",

        // UK specific
        "costa coffee", "costa", "caffe nero", "caffè nero",
        "eat.", "wasabi", "itsu",

        // Asian chains
        "yoshinoya", "sukiya", "matsuya", "coco ichibanya",
        "jollibee", "mang inasal", "chowking", "max's",
        "lotteria", "mos burger", "freshness burger",

        // Coffee chains (global)
        "starbucks", "dunkin", "dunkin'", "tim hortons", "tim horton's",
        "peet's coffee", "peets coffee", "caribou coffee",
        "second cup", "gloria jean", "coffee bean & tea",

        // Quick service indicators
        "drive-thru", "drive thru", "drive through",
        "fast food", "fast-food", "quick service",

        // Generic exclusions
        "food court", "mall food", "airport", "station",
        "cafeteria", "canteen", "vending",

        // Bakery/Donut chains
        "dunkin donuts", "krispy kreme", "tim hortons",
        "cinnabon", "auntie anne", "wetzel's pretzel",

        // Ice cream chains
        "baskin robbins", "baskin-robbins", "dairy queen", "coldstone",
        "cold stone", "marble slab", "rita's italian ice"
    ]

    // MARK: - Public API

    /// Check if a venue should be excluded (is fast food)
    /// - Parameter mapItem: The MapKit item to check
    /// - Returns: true if the venue is fast food and should be excluded
    static func isFastFood(_ mapItem: MKMapItem) -> Bool {
        let name = mapItem.name?.lowercased() ?? ""

        for exclusion in fastFoodExclusions {
            if name.contains(exclusion) {
                return true
            }
        }

        return false
    }

    /// Classify a venue's type for UI display
    /// - Parameter mapItem: The MapKit item to classify
    /// - Returns: Venue type for UI display
    static func classify(mapItem: MKMapItem) -> VenueType {
        let category = mapItem.pointOfInterestCategory
        let name = mapItem.name?.lowercased() ?? ""

        // Check MapKit category first
        switch category {
        case .nightlife:
            if name.contains("club") || name.contains("disco") {
                return .club
            }
            if name.contains("pub") || name.contains("tavern") {
                return .pub
            }
            if name.contains("lounge") {
                return .lounge
            }
            return .bar

        case .brewery, .distillery, .winery:
            return .bar

        case .cafe:
            return .cafe

        case .bakery:
            return .bakery

        case .restaurant:
            // Check for bar/pub indicators in restaurant names
            if name.contains("bar") || name.contains("pub") ||
               name.contains("tavern") || name.contains("lounge") ||
               name.contains("cocktail") || name.contains("wine bar") {
                return .bar
            }
            return .restaurant

        default:
            break
        }

        // Fallback: check name keywords
        if name.contains("cafe") || name.contains("café") || name.contains("coffee") {
            return .cafe
        }
        if name.contains("bakery") || name.contains("pastry") || name.contains("patisserie") {
            return .bakery
        }
        if name.contains("bar") || name.contains("pub") || name.contains("tavern") {
            return .bar
        }
        if name.contains("club") || name.contains("disco") {
            return .club
        }

        // Default to restaurant for food venues
        return .restaurant
    }
}
