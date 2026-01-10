import Foundation
import MapKit
import CoreLocation

/// Actor providing tile-based spatial caching for venues
/// Enables O(1) region lookups and supports cache-first display patterns
actor SpatialVenueCache {

    // MARK: - Types

    /// Tile key for spatial indexing
    /// Uses fixed-size tiles (~1.1km at equator with 0.01 degree size)
    struct TileKey: Hashable, Sendable {
        let latIndex: Int
        let lngIndex: Int

        init(coordinate: CLLocationCoordinate2D, tileSize: Double = 0.01) {
            latIndex = Int(floor(coordinate.latitude / tileSize))
            lngIndex = Int(floor(coordinate.longitude / tileSize))
        }

        init(latIndex: Int, lngIndex: Int) {
            self.latIndex = latIndex
            self.lngIndex = lngIndex
        }
    }

    /// Metadata for a cached region search
    struct CachedRegion: Sendable {
        let region: MKCoordinateRegion
        let timestamp: Date
        let queryTerms: Set<String>
        let venueCount: Int
    }

    // MARK: - State

    /// Tile-based spatial index: maps tiles to venue IDs
    private var tileIndex: [TileKey: Set<UUID>] = [:]

    /// All cached venues by ID
    private var venueStore: [UUID: Venue] = [:]

    /// Metadata about cached regions
    private var regionCache: [CachedRegion] = []

    /// Access timestamps for LRU eviction
    private var accessTimestamps: [UUID: Date] = [:]

    // MARK: - Configuration

    private let maxVenues = 500
    private let maxRegions = 20
    private let cacheExpirationSeconds: TimeInterval = 300 // 5 minutes
    private let tileSize: Double = 0.01 // ~1.1km at equator

    // MARK: - Public API

    /// Query venues from cache for a given region
    /// - Parameter region: The map region to query
    /// - Returns: Cached venues if available, nil if cache miss
    func getVenues(in region: MKCoordinateRegion) -> [Venue]? {
        // Check if we have coverage for this region
        guard hasValidCoverage(for: region) else {
            return nil
        }

        // Get all tiles that overlap with the region
        let tiles = tilesForRegion(region)

        // Collect venue IDs from all relevant tiles
        var venueIDs = Set<UUID>()
        for tile in tiles {
            if let ids = tileIndex[tile] {
                venueIDs.formUnion(ids)
            }
        }

        // Update access timestamps and filter to venues within region
        let now = Date()
        var venues: [Venue] = []
        for id in venueIDs {
            if let venue = venueStore[id], isCoordinate(venue.coordinate, in: region) {
                accessTimestamps[id] = now
                venues.append(venue)
            }
        }

        return venues.isEmpty ? nil : venues
    }

    /// Store venues with region metadata
    /// - Parameters:
    ///   - venues: Venues to cache
    ///   - region: The region these venues were discovered in
    ///   - queryTerms: The queries used to find these venues
    func storeVenues(_ venues: [Venue], for region: MKCoordinateRegion, queryTerms: Set<String> = []) {
        let now = Date()

        // Add venues to store and index
        for venue in venues {
            venueStore[venue.id] = venue
            accessTimestamps[venue.id] = now

            // Index by tile
            let tile = TileKey(coordinate: venue.coordinate, tileSize: tileSize)
            tileIndex[tile, default: []].insert(venue.id)
        }

        // Store region metadata
        let cached = CachedRegion(
            region: region,
            timestamp: now,
            queryTerms: queryTerms,
            venueCount: venues.count
        )
        regionCache.append(cached)

        // Enforce limits
        enforceVenueLimit()
        enforceRegionLimit()
    }

    /// Merge new venues with existing venues, deduplicating by location
    /// - Parameters:
    ///   - newVenues: Fresh venues from network
    ///   - existingVenues: Previously cached venues
    /// - Returns: Merged and deduplicated venue list
    func mergeVenues(_ newVenues: [Venue], with existingVenues: [Venue]) -> [Venue] {
        var seen = Set<String>()
        var merged: [Venue] = []

        // Prefer new venues (fresher data)
        for venue in newVenues {
            let key = venueKey(for: venue)
            if !seen.contains(key) {
                seen.insert(key)
                merged.append(venue)
            }
        }

        // Add existing venues not in new set
        for venue in existingVenues {
            let key = venueKey(for: venue)
            if !seen.contains(key) {
                seen.insert(key)
                merged.append(venue)
            }
        }

        return merged
    }

    /// Check if cached data for a region is still fresh
    /// - Parameter region: Region to check
    /// - Returns: True if we have fresh data covering this region
    func isCacheFresh(for region: MKCoordinateRegion) -> Bool {
        return hasValidCoverage(for: region)
    }

    /// Get tiles that need to be fetched for prefetching
    /// - Parameter center: Current map center
    /// - Returns: Array of tile keys that don't have data
    func getMissingAdjacentTiles(around center: CLLocationCoordinate2D) -> [TileKey] {
        let centerTile = TileKey(coordinate: center, tileSize: tileSize)
        var missing: [TileKey] = []

        // Check 3x3 grid around center
        for dLat in -1...1 {
            for dLng in -1...1 {
                let tile = TileKey(latIndex: centerTile.latIndex + dLat, lngIndex: centerTile.lngIndex + dLng)
                if tileIndex[tile] == nil {
                    missing.append(tile)
                }
            }
        }

        return missing
    }

    /// Convert a tile key to a searchable region
    /// - Parameter tile: The tile to convert
    /// - Returns: MKCoordinateRegion covering the tile
    func regionForTile(_ tile: TileKey) -> MKCoordinateRegion {
        let centerLat = (Double(tile.latIndex) + 0.5) * tileSize
        let centerLng = (Double(tile.lngIndex) + 0.5) * tileSize
        let center = CLLocationCoordinate2D(latitude: centerLat, longitude: centerLng)
        let span = MKCoordinateSpan(latitudeDelta: tileSize, longitudeDelta: tileSize)
        return MKCoordinateRegion(center: center, span: span)
    }

    /// Invalidate stale cache entries
    func invalidateStale() {
        let now = Date()

        // Remove stale regions
        regionCache.removeAll { region in
            now.timeIntervalSince(region.timestamp) > cacheExpirationSeconds
        }

        // Note: We don't remove venues from stale regions immediately
        // They'll be evicted via LRU when we hit the limit
    }

    /// Clear all cached data
    func clear() {
        tileIndex.removeAll()
        venueStore.removeAll()
        regionCache.removeAll()
        accessTimestamps.removeAll()
    }

    /// Get current cache statistics
    func getStats() -> (venueCount: Int, tileCount: Int, regionCount: Int) {
        return (venueStore.count, tileIndex.count, regionCache.count)
    }

    // MARK: - Private Helpers

    private func hasValidCoverage(for region: MKCoordinateRegion) -> Bool {
        let now = Date()

        // Check if any cached region overlaps and is fresh
        for cached in regionCache {
            if now.timeIntervalSince(cached.timestamp) < cacheExpirationSeconds {
                if regionsOverlap(cached.region, region) {
                    return true
                }
            }
        }

        return false
    }

    private func tilesForRegion(_ region: MKCoordinateRegion) -> [TileKey] {
        let minLat = region.center.latitude - region.span.latitudeDelta / 2
        let maxLat = region.center.latitude + region.span.latitudeDelta / 2
        let minLng = region.center.longitude - region.span.longitudeDelta / 2
        let maxLng = region.center.longitude + region.span.longitudeDelta / 2

        let minLatIndex = Int(floor(minLat / tileSize))
        let maxLatIndex = Int(floor(maxLat / tileSize))
        let minLngIndex = Int(floor(minLng / tileSize))
        let maxLngIndex = Int(floor(maxLng / tileSize))

        var tiles: [TileKey] = []
        for latIdx in minLatIndex...maxLatIndex {
            for lngIdx in minLngIndex...maxLngIndex {
                tiles.append(TileKey(latIndex: latIdx, lngIndex: lngIdx))
            }
        }

        return tiles
    }

    private func regionsOverlap(_ r1: MKCoordinateRegion, _ r2: MKCoordinateRegion) -> Bool {
        let r1MinLat = r1.center.latitude - r1.span.latitudeDelta / 2
        let r1MaxLat = r1.center.latitude + r1.span.latitudeDelta / 2
        let r1MinLng = r1.center.longitude - r1.span.longitudeDelta / 2
        let r1MaxLng = r1.center.longitude + r1.span.longitudeDelta / 2

        let r2MinLat = r2.center.latitude - r2.span.latitudeDelta / 2
        let r2MaxLat = r2.center.latitude + r2.span.latitudeDelta / 2
        let r2MinLng = r2.center.longitude - r2.span.longitudeDelta / 2
        let r2MaxLng = r2.center.longitude + r2.span.longitudeDelta / 2

        let latOverlap = r1MinLat <= r2MaxLat && r1MaxLat >= r2MinLat
        let lngOverlap = r1MinLng <= r2MaxLng && r1MaxLng >= r2MinLng

        return latOverlap && lngOverlap
    }

    private func isCoordinate(_ coord: CLLocationCoordinate2D, in region: MKCoordinateRegion) -> Bool {
        let minLat = region.center.latitude - region.span.latitudeDelta / 2
        let maxLat = region.center.latitude + region.span.latitudeDelta / 2
        let minLng = region.center.longitude - region.span.longitudeDelta / 2
        let maxLng = region.center.longitude + region.span.longitudeDelta / 2

        return coord.latitude >= minLat && coord.latitude <= maxLat &&
               coord.longitude >= minLng && coord.longitude <= maxLng
    }

    private func enforceVenueLimit() {
        guard venueStore.count > maxVenues else { return }

        // LRU eviction: remove least recently accessed venues
        let sortedByAccess = accessTimestamps.sorted { $0.value < $1.value }
        let toRemove = venueStore.count - maxVenues

        for (id, _) in sortedByAccess.prefix(toRemove) {
            if let venue = venueStore.removeValue(forKey: id) {
                // Remove from tile index
                let tile = TileKey(coordinate: venue.coordinate, tileSize: tileSize)
                tileIndex[tile]?.remove(id)
                if tileIndex[tile]?.isEmpty == true {
                    tileIndex.removeValue(forKey: tile)
                }
            }
            accessTimestamps.removeValue(forKey: id)
        }
    }

    private func enforceRegionLimit() {
        guard regionCache.count > maxRegions else { return }

        // Remove oldest regions
        regionCache.sort { $0.timestamp < $1.timestamp }
        regionCache = Array(regionCache.suffix(maxRegions))
    }

    private func venueKey(for venue: Venue) -> String {
        let lat = String(format: "%.5f", venue.coordinate.latitude)
        let lng = String(format: "%.5f", venue.coordinate.longitude)
        return "\(venue.name)_\(lat)_\(lng)"
    }
}
