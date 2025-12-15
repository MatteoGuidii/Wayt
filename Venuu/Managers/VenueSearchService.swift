import Foundation
import MapKit

struct VenueSearchService: Sendable {
    
    // MARK: - Discovery Strategy
    // Instead of hardcoded queries, we use MapKit's category system to discover ALL venues
    // in relevant categories, then let the VenueRelevanceScorer filter by quality.
    // This ensures we don't miss legitimate businesses due to naming conventions.
    
    /// Core nightlife categories that should always be searched
    private let coreCategories: [MKPointOfInterestCategory] = [
        .nightlife,
        .brewery,
        .distillery,
        .winery,
        .theater,
        .musicVenue
    ]
    
    /// Broad search terms that work with category filters to discover venues
    /// These are intentionally generic to cast a wide net
    private let broadDiscoveryTerms = [
        "bar",           // Catches all bar types
        "restaurant",    // Catches hybrid restaurant/bars
        "pub",           // Traditional pubs
        "club",          // Night clubs, social clubs
        "lounge",        // Lounges of all types
        "brewery",       // Craft breweries, taprooms
        "nightlife"      // General nightlife venues
    ]
    
    // Vibe-based search mappings for user queries
    private let vibeMappings: [String: [String]] = [
        "dance": ["club", "nightclub", "dance"],
        "party": ["club", "nightlife", "bar"],
        "chill": ["lounge", "wine bar", "jazz"],
        "date": ["cocktail", "wine bar", "rooftop"],
        "live": ["live music", "jazz", "concert"],
        "beer": ["pub", "brewery", "beer garden"],
        "fancy": ["cocktail", "rooftop", "hotel bar"],
        "casual": ["pub", "sports bar", "dive bar"]
    ]

    public func getQueries(for searchText: String) -> [String] {
        let lowerText = searchText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If user typed something specific, search for it directly
        if !lowerText.isEmpty {
            // Check if the search text matches a known "vibe"
            for (vibe, queries) in vibeMappings {
                if lowerText.contains(vibe) {
                    return queries
                }
            }
            // User typed a specific venue name or search term - use it directly
            return [searchText]
        }
        
        // For general discovery (no search text), use broad category-based terms
        // This discovers ALL venues in the area, relying on category filters
        // and relevance scoring to determine what's shown
        return broadDiscoveryTerms
    }

    public func search(query: String, region: MKCoordinateRegion) async throws -> [Venue] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = region
        request.resultTypes = .pointOfInterest
        
        // Category filter: Include all potentially nightlife-relevant categories
        // We cast a WIDE net here - filtering happens in VenueRelevanceScorer
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [
            .nightlife,      // Explicit nightlife venues
            .restaurant,     // Many bars are categorized as restaurants
            .brewery,        // Craft breweries, taprooms
            .distillery,     // Distilleries with tasting rooms
            .winery,         // Wine bars, tasting rooms
            .theater,        // Performance venues
            .musicVenue,     // Concert halls, music clubs
            .cafe            // Some late-night cafes/coffee bars serve alcohol
        ])
        
        let search = MKLocalSearch(request: request)
        let response = try await search.start()
        
        return response.mapItems.map { Venue(mapItem: $0) }
    }
}
