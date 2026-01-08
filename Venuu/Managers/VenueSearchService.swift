import Foundation
import MapKit

struct VenueSearchService: Sendable {

    // MARK: - Discovery Strategy
    // Grid-based search: Divides the search area into smaller grid cells and searches each independently
    // This overcomes MapKit's per-query result limit (~10-15 venues) and ensures comprehensive coverage
    // in dense urban areas where a single search would miss many venues.
    
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
        "club",          // Night clubs, social clubs
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

    /// Performs a grid-based search to overcome MapKit's per-query result limits
    /// Divides the region into smaller grid cells and searches each independently
    public func searchWithGrid(query: String, region: MKCoordinateRegion, gridSize: Int = AppConfiguration.Search.searchGridSize) async throws -> [Venue] {
        let gridCells = createGridCells(region: region, gridSize: gridSize)

        // Search each grid cell concurrently
        let venueArrays = await withTaskGroup(of: [Venue].self) { group in
            for cell in gridCells {
                group.addTask {
                    do {
                        return try await self.searchSingleCell(query: query, region: cell)
                    } catch {
                        return []
                    }
                }
            }

            var allVenues: [Venue] = []
            for await venues in group {
                allVenues.append(contentsOf: venues)
            }
            return allVenues
        }

        // Deduplicate venues that might appear in multiple grid cells
        // Use a Set with a unique key based on name + approximate location
        var seenVenueKeys = Set<String>()
        var uniqueVenues: [Venue] = []

        for venue in venueArrays {
            // Create a unique key with rounded coordinates (to 5 decimal places ~ 1 meter precision)
            let lat = String(format: "%.5f", venue.coordinate.latitude)
            let lng = String(format: "%.5f", venue.coordinate.longitude)
            let key = "\(venue.name)_\(lat)_\(lng)"

            if !seenVenueKeys.contains(key) {
                seenVenueKeys.insert(key)
                uniqueVenues.append(venue)
            }
        }

        return uniqueVenues
    }

    /// Searches a single grid cell
    private func searchSingleCell(query: String, region: MKCoordinateRegion) async throws -> [Venue] {
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

    /// Creates a grid of smaller regions from the main search region
    private func createGridCells(region: MKCoordinateRegion, gridSize: Int) -> [MKCoordinateRegion] {
        guard gridSize > 0 else { return [region] }

        let latDelta = region.span.latitudeDelta / Double(gridSize)
        let lngDelta = region.span.longitudeDelta / Double(gridSize)

        // Calculate the starting corner (top-left)
        let startLat = region.center.latitude + (region.span.latitudeDelta / 2.0)
        let startLng = region.center.longitude - (region.span.longitudeDelta / 2.0)

        var cells: [MKCoordinateRegion] = []

        for row in 0..<gridSize {
            for col in 0..<gridSize {
                let cellCenterLat = startLat - (latDelta * Double(row)) - (latDelta / 2.0)
                let cellCenterLng = startLng + (lngDelta * Double(col)) + (lngDelta / 2.0)

                let cellCenter = CLLocationCoordinate2D(
                    latitude: cellCenterLat,
                    longitude: cellCenterLng
                )

                let cellSpan = MKCoordinateSpan(
                    latitudeDelta: latDelta,
                    longitudeDelta: lngDelta
                )

                let cellRegion = MKCoordinateRegion(center: cellCenter, span: cellSpan)
                cells.append(cellRegion)
            }
        }

        return cells
    }

    /// Legacy search method for backward compatibility (searches a single region)
    public func search(query: String, region: MKCoordinateRegion) async throws -> [Venue] {
        return try await searchSingleCell(query: query, region: region)
    }
}
