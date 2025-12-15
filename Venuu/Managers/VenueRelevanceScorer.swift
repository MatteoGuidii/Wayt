import Foundation
import MapKit

/// Multi-signal scoring system to determine nightlife relevance of venues,
/// particularly for restaurants that may serve as nightlife destinations
struct VenueRelevanceScorer {

    // MARK: - Nightlife Keywords (High Priority) - Multilingual

    private static let nightlifeKeywords: Set<String> = [
        // English - Hybrid concepts
        "wine bar", "cocktail bar", "cocktail lounge", "rooftop bar", "rooftop lounge",
        "speakeasy", "gastropub", "gastro pub", "tapas bar", "oyster bar",
        "craft beer", "taproom", "beer garden", "late night", "late-night",
        "small plates", "sharing plates", "tasting menu", "chef's table",
        "bar & grill", "bar and grill", "bar & kitchen", "bar and kitchen",
        "steakhouse", "steak house", "seafood bar", "champagne bar", "prosecco bar",
        "piano bar", "jazz bar", "live music", "nightclub", "night club", "disco", "dance club",

        // French
        "bar à vin", "bar à cocktail", "bar à vins", "bar à tapas",
        "brasserie", "bistro", "discothèque", "boîte de nuit",
        "cave à vin", "bar à champagne", "bar lounge",

        // Spanish
        "bar de vino", "bar de vinos", "bar de tapas", "bar de copas",
        "cervecería", "cerveceria", "taberna", "tasca", "bodega",
        "mezcalería", "tequilería", "chiringuito", "gastrobar",

        // Italian
        "enoteca", "osteria", "trattoria", "ristopub", "wine bar",
        "aperitivo bar", "cocktail bar", "american bar",

        // German
        "biergarten", "weinstube", "weinbar", "kneipe", "gasthaus",
        "brauhaus", "bierhalle", "cocktailbar",

        // Portuguese
        "cervejaria", "bar de vinhos", "tasca", "adega",

        // Japanese (Romanized)
        "izakaya", "居酒屋", "sake bar", "ramen bar", "yakitori bar",
        "karaoke bar", "standing bar", "shot bar",

        // Asian cuisines (English/Romanized)
        "korean bbq", "kbbq", "hot pot", "sushi bar", "dim sum bar",
        "shabu shabu", "yakiniku", "teppanyaki bar",

        // Middle Eastern
        "shisha lounge", "hookah lounge", "hookah bar", "narguile bar",

        // Dutch
        "wijnbar", "cocktailbar", "bruin café", "café",

        // Generic international
        "lounge", "pub", "tavern", "cantina", "bar", "rooftop"
    ]

    // MARK: - Upscale/Social Indicators (Medium Priority) - Global

    private static let upscaleIndicators: Set<String> = [
        // Cuisine types - Global
        "italian", "french", "mediterranean", "japanese", "spanish",
        "modern american", "new american", "fusion", "contemporary",
        "peruvian", "argentinian", "brazilian", "mexican", "thai",
        "vietnamese", "korean", "chinese", "indian", "lebanese",
        "turkish", "greek", "moroccan", "scandinavian", "nordic",

        // Dining styles
        "fine dining", "farm to table", "farm-to-table",
        "artisanal", "handcrafted", "locally sourced", "seasonal",
        "chef-driven", "michelin", "tasting menu",

        // Format indicators (multilingual)
        "the ", "le ", "la ", "il ", "el ", "chez ", "bar ",
        "al ", "da ", "di ", "del ", "los ", "las ",

        // Venue descriptors - International
        "grill", "tavern", "inn", "house", "kitchen", "dining room",
        "taqueria", "trattoria", "osteria", "enoteca", "ristorante",
        "brasserie", "bistrot", "auberge", "restaurant",
        "asador", "parrilla", "churrascaria", "steakhouse"
    ]

    // MARK: - Exclusion Keywords (Reject) - Global Chains

    private static let excludeKeywords: Set<String> = [
        // Global fast food chains
        "mcdonald", "burger king", "kfc", "subway", "domino's",
        "pizza hut", "taco bell", "wendy's", "papa john",

        // US chains
        "chipotle", "panera", "qdoba", "five guys", "shake shack",
        "chick-fil-a", "popeyes", "arby's", "sonic", "jack in the box",
        "carl's jr", "hardee's", "white castle", "whataburger", "in-n-out",
        "little caesars", "applebee's", "chili's", "olive garden", "red lobster",
        "outback steakhouse", "texas roadhouse", "longhorn steakhouse",
        "denny's", "ihop", "waffle house", "cracker barrel",
        "golden corral", "hometown buffet",

        // European chains
        "pret a manger", "pret", "costa coffee", "costa", "caffè nero",
        "greggs", "leon", "eat.", "wetherspoon", "spoons",
        "nando's", "nandos", "wagamama", "pizza express", "ask italian",
        "yo! sushi", "zizzi", "prezzo", "frankie & benny",

        // Asian chains
        "yoshinoya", "sukiya", "matsuya", "coco ichibanya",
        "jollibee", "mang inasal", "chowking", "max's",
        "味千拉面", "吉野家", "松屋",

        // Coffee chains (global)
        "starbucks", "dunkin", "tim hortons", "peet's coffee",
        "costa coffee", "caffè nero", "second cup",

        // Quick service indicators
        "drive-thru", "drive thru", "drive through", "takeout only",
        "delivery only", "fast food", "quick service", "fast-food",
        "buffet", "all you can eat",

        // Generic casual indicators
        "food court", "mall food", "airport", "station",
        "cafeteria", "canteen", "café",
        "bakery", "donut", "bagel", "sandwich shop", "sandwicherie",
        "coffee shop", "coffee house", "kafe", "koffie"
    ]

    // MARK: - Scoring Algorithm

    /// Calculate nightlife relevance score (0-100) for a venue
    /// - Parameters:
    ///   - mapItem: The MapKit item to score
    ///   - nearbyNightlifeCount: Number of confirmed nightlife venues within 200m (optional)
    /// - Returns: Confidence score from 0 (not relevant) to 100 (highly relevant)
    static func calculateScore(
        for mapItem: MKMapItem,
        nearbyNightlifeCount: Int = 0
    ) -> Int {
        let name = mapItem.name?.lowercased() ?? ""
        let category = mapItem.pointOfInterestCategory
        var score = 0

        // STEP 1: Immediate rejection for excluded keywords
        for keyword in excludeKeywords {
            if name.contains(keyword) {
                return 0 // Reject fast food and casual chains
            }
        }

        // STEP 2: Category-based baseline scoring
        score += categoryScore(for: category, name: name)

        // STEP 3: Name analysis for nightlife keywords (highest value)
        if containsAny(name, keywords: nightlifeKeywords) {
            score += 40
        }

        // STEP 4: Upscale/social indicators (medium value)
        if containsAny(name, keywords: upscaleIndicators) {
            score += 20
        }

        // STEP 5: Proximity boost (contextual signal)
        // More nearby nightlife venues = higher confidence this is a nightlife spot
        let proximityBonus = min(nearbyNightlifeCount * 5, 20)
        score += proximityBonus

        // STEP 6: Hybrid category detection (strong signal)
        if hasHybridCategory(mapItem) {
            score += 30
        }

        // Cap at 100
        return min(score, 100)
    }

    // MARK: - Category Scoring

    private static func categoryScore(for category: MKPointOfInterestCategory?, name: String) -> Int {
        guard let category = category else { return 0 }

        switch category {
        // Explicit nightlife categories - high baseline
        case .nightlife:
            return 50

        case .brewery, .distillery, .winery:
            return 45

        case .musicVenue, .theater:
            return 40

        // Restaurant category - needs additional signals
        case .restaurant:
            // If restaurant name has bar-related words, boost baseline
            if name.contains("bar") || name.contains("pub") ||
               name.contains("tavern") || name.contains("lounge") {
                return 35
            }
            // Generic restaurant starts lower, needs other signals
            return 25

        default:
            return 0
        }
    }

    // MARK: - Hybrid Category Detection

    /// Check if the venue has multiple relevant categories (e.g., Restaurant + Bar)
    private static func hasHybridCategory(_ mapItem: MKMapItem) -> Bool {
        let category = mapItem.pointOfInterestCategory
        let name = mapItem.name?.lowercased() ?? ""

        // If it's a restaurant with bar-related category indicators
        if category == .restaurant {
            // MapKit doesn't expose all categories, so we infer from name
            let barIndicators = ["bar", "pub", "tavern", "lounge", "brewery", "winery"]
            return barIndicators.contains { name.contains($0) }
        }

        // If it's nightlife with food indicators
        if category == .nightlife {
            let foodIndicators = ["restaurant", "kitchen", "grill", "bistro", "brasserie"]
            return foodIndicators.contains { name.contains($0) }
        }

        return false
    }

    // MARK: - Helper Methods

    private static func containsAny(_ text: String, keywords: Set<String>) -> Bool {
        keywords.contains { text.contains($0) }
    }
}
