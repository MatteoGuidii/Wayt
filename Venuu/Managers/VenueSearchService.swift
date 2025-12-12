import Foundation
import MapKit

class VenueSearchService {
    
    // Mapping "vibes" or keywords to MKLocalSearch queries
    private let vibeMappings: [String: [String]] = [
        "dance": ["Night Club", "Dance Club", "Disco"],
        "party": ["Night Club", "Beach Club", "Day Club"],
        "chill": ["Lounge", "Speakeasy", "Wine Bar", "Hookah Lounge", "Jazz Club"],
        "date": ["Cocktail Bar", "Wine Bar", "Speakeasy", "Rooftop Bar"],
        "live": ["Live Music", "Jazz Club", "Concert Hall", "Piano Bar"],
        "beer": ["Pub", "Brewery", "Beer Garden", "Gastropub", "Irish Pub"],
        "fancy": ["Cocktail Bar", "Rooftop Bar", "Hotel Bar", "Champagne Bar"],
        "good mood": ["Cocktail Bar", "Tiki Bar", "Beach Bar", "Rooftop Bar"],
        "hidden": ["Speakeasy", "Hidden Bar"],
        "roof": ["Rooftop Bar", "Rooftop Lounge"]
    ]
    
    // Default discovery queries (Expanded for better coverage)
    // We split these into batches or rely on the main discovery manager to handle them
    private let discoveryQueries = [
        "Cocktail Bar", 
        "Night Club", 
        "Speakeasy", 
        "Rooftop Bar", 
        "Live Music", 
        "Jazz Club", 
        "Gastropub",
        "Wine Bar"
    ]

    public func getQueries(for searchText: String) -> [String] {
        let lowerText = searchText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        if lowerText.isEmpty {
            return discoveryQueries
        }
        
        // Check if the search text matches a known "vibe"
        for (vibe, queries) in vibeMappings {
            if lowerText.contains(vibe) {
                return queries
            }
        }
        
        // If no vibe match, return the raw search text as a single query
        // This allows searching for specific places like "McDonalds" or "The Box"
        return [searchText]
    }

    public func search(query: String, region: MKCoordinateRegion) async throws -> [Venue] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = region
        request.resultTypes = .pointOfInterest
        
        // Filter for relevant categories
        // We include restaurant because many bars are categorized as restaurants,
        // but we will filter them out later if they don't look like bars.
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [
            .nightlife,
            .restaurant,
            .brewery,
            .distillery,
            .winery,
            .theater,
            .musicVenue
        ])
        
        let search = MKLocalSearch(request: request)
        let response = try await search.start()
        
        return response.mapItems.map { Venue(mapItem: $0) }
    }
}
