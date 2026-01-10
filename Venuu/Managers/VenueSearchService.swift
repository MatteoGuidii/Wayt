import Foundation
import MapKit

/// Service for searching food and dining venues using MapKit
struct VenueSearchService: Sendable {

    // MARK: - Configuration

    /// Grid overlap factor to catch venues at cell boundaries
    private let gridOverlapFactor: Double = 0.1 // 10% overlap

    // MARK: - Public API

    /// Get search queries for a given search text
    /// - Parameter searchText: User's search text (empty for discovery mode)
    /// - Returns: Array of search queries to execute
    public func getQueries(for searchText: String) -> [String] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmed.isEmpty {
            // User typed something specific - search for it directly
            return [trimmed]
        }

        // Discovery mode - use primary queries from configuration
        return VenueQueryConfiguration.primaryQueries
    }

    /// Get initial discovery queries
    public func getInitialQueries() -> [String] {
        return VenueQueryConfiguration.getInitialQueries()
    }

    /// Get secondary queries for expanded coverage
    public func getSecondaryQueries() -> [String] {
        return VenueQueryConfiguration.getSecondaryQueries()
    }

    /// Get cuisine-specific queries
    public func getCuisineQueries() -> [String] {
        return VenueQueryConfiguration.getCuisineQueries()
    }

    /// Performs a grid-based search to find more venues
    /// Divides the region into smaller cells and searches each independently
    /// Uses overlapping cells to catch venues at boundaries
    public func searchWithGrid(query: String, region: MKCoordinateRegion, gridSize: Int = AppConfiguration.Search.searchGridSize) async throws -> [Venue] {
        let gridCells = createGridCellsWithOverlap(region: region, gridSize: gridSize, overlapFactor: gridOverlapFactor)

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
        var seenVenueKeys = Set<String>()
        var uniqueVenues: [Venue] = []

        for venue in venueArrays {
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

    /// Search a single region
    public func search(query: String, region: MKCoordinateRegion) async throws -> [Venue] {
        return try await searchSingleCell(query: query, region: region)
    }

    // MARK: - Private

    private func searchSingleCell(query: String, region: MKCoordinateRegion) async throws -> [Venue] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = region
        request.resultTypes = .pointOfInterest

        // Include all venue-related categories from configuration
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: VenueQueryConfiguration.venueCategories)

        let search = MKLocalSearch(request: request)
        let response = try await search.start()

        // Filter out fast food and convert to Venue objects
        return response.mapItems.compactMap { mapItem in
            // Exclude fast food chains
            guard !VenueClassifier.isFastFood(mapItem) else {
                return nil
            }
            return Venue(mapItem: mapItem)
        }
    }

    /// Create grid cells with overlap to catch venues at boundaries
    /// - Parameters:
    ///   - region: The overall region to divide
    ///   - gridSize: Number of cells per dimension (2 = 2x2 = 4 cells)
    ///   - overlapFactor: How much cells should overlap (0.1 = 10%)
    /// - Returns: Array of overlapping grid cell regions
    private func createGridCellsWithOverlap(
        region: MKCoordinateRegion,
        gridSize: Int,
        overlapFactor: Double = 0.1
    ) -> [MKCoordinateRegion] {
        guard gridSize > 0 else { return [region] }

        let latDelta = region.span.latitudeDelta / Double(gridSize)
        let lngDelta = region.span.longitudeDelta / Double(gridSize)

        // Expand each cell by the overlap factor
        let expandedLatDelta = latDelta * (1 + overlapFactor)
        let expandedLngDelta = lngDelta * (1 + overlapFactor)

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

                // Use expanded span for overlap
                let cellSpan = MKCoordinateSpan(
                    latitudeDelta: expandedLatDelta,
                    longitudeDelta: expandedLngDelta
                )

                let cellRegion = MKCoordinateRegion(center: cellCenter, span: cellSpan)
                cells.append(cellRegion)
            }
        }

        return cells
    }

    // MARK: - Legacy Support

    /// Create grid cells without overlap (for backwards compatibility)
    private func createGridCells(region: MKCoordinateRegion, gridSize: Int) -> [MKCoordinateRegion] {
        return createGridCellsWithOverlap(region: region, gridSize: gridSize, overlapFactor: 0)
    }
}
