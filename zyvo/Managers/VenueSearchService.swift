import Foundation
import MapKit

class VenueSearchService {
    
    // Mapping "vibes" or keywords to MKLocalSearch queries
    private let vibeMappings: [String: [String]] = [
        "dance": ["Night Club", "Dance Hall", "Disco"],
        "party": ["Night Club", "Bar", "Lounge"],
        "chill": ["Lounge", "Speakeasy", "Wine Bar", "Jazz Club"],
        "date": ["Cocktail Bar", "Wine Bar", "Fine Dining", "Speakeasy"],
        "live": ["Live Music", "Jazz Club", "Concert Hall"],
        "beer": ["Pub", "Brewery", "Beer Garden", "Gastropub"],
        "fancy": ["Cocktail Bar", "Rooftop Bar", "Lounge"],
        "good mood": ["Cocktail Bar", "Tapas", "Bistro", "Rooftop Bar"]
    ]
    
    // Default discovery queries (Reduced to prevent rate limiting)
    private let discoveryQueries = [
        "Bar", "Night Club", "Live Music", "Lounge"
    ]
    
    func getQueries(for searchText: String) -> [String] {
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
    
    func search(query: String, region: MKCoordinateRegion) async throws -> [Venue] {
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
