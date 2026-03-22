import CoreLocation
import MapKit

/// Represents either a single venue or a cluster of nearby venues.
enum VenueMapItem: Identifiable {
    case single(Venue)
    case cluster(VenueCluster)

    var id: String {
        switch self {
        case .single(let venue): return venue.id
        case .cluster(let cluster): return cluster.id
        }
    }

    var coordinate: CLLocationCoordinate2D {
        switch self {
        case .single(let venue): return venue.coordinate
        case .cluster(let cluster): return cluster.coordinate
        }
    }
}

/// A group of nearby venues collapsed into a single map annotation.
struct VenueCluster: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let venues: [Venue]

    var count: Int { venues.count }

    /// Average busyness level across all venues in the cluster.
    /// Returns nil only when no venue has busyness data at all.
    var averageBusyness: BusynessLevel? {
        let values = venues.compactMap { $0.busyness?.rawValue }
        guard !values.isEmpty else { return nil }
        let avg = Double(values.reduce(0, +)) / Double(values.count)
        return BusynessLevel(closestTo: avg)
    }
}

/// Fast grid-based venue clustering. O(n) time complexity.
///
/// Divides the visible region into a grid. Venues in the same cell
/// are grouped into a cluster. Cell size scales with zoom level so
/// clusters merge as the user zooms out and split as they zoom in.
enum VenueClusterer {

    /// Minimum venues in a cell to form a cluster (otherwise show individually).
    private static let minClusterSize = 2

    /// Grid density — how many cells per screen axis.
    /// Higher = smaller cells = fewer clusters = more individual pins.
    private static let gridDensityFactor: Double = 8

    /// Cluster venues based on the current map region (zoom level).
    /// Returns a mix of single venues and clusters.
    static func cluster(
        venues: [Venue],
        in region: MKCoordinateRegion
    ) -> [VenueMapItem] {
        guard !venues.isEmpty else { return [] }

        // Cell size in degrees, proportional to visible span
        let cellLat = region.span.latitudeDelta / gridDensityFactor
        let cellLng = region.span.longitudeDelta / gridDensityFactor

        guard cellLat > 0, cellLng > 0 else {
            return venues.map { .single($0) }
        }

        // Grid-hash each venue into a cell
        var grid: [String: [Venue]] = [:]
        for venue in venues {
            let row = Int(floor(venue.coordinate.latitude / cellLat))
            let col = Int(floor(venue.coordinate.longitude / cellLng))
            let key = "\(row)_\(col)"
            grid[key, default: []].append(venue)
        }

        var items: [VenueMapItem] = []
        items.reserveCapacity(grid.count)

        for (key, cellVenues) in grid {
            if cellVenues.count < minClusterSize {
                // Not enough to cluster — show individually
                for venue in cellVenues {
                    items.append(.single(venue))
                }
            } else {
                // Compute centroid of the cluster
                var totalLat = 0.0
                var totalLng = 0.0
                for venue in cellVenues {
                    totalLat += venue.coordinate.latitude
                    totalLng += venue.coordinate.longitude
                }
                let count = Double(cellVenues.count)
                let centroid = CLLocationCoordinate2D(
                    latitude: totalLat / count,
                    longitude: totalLng / count
                )

                let cluster = VenueCluster(
                    id: "cluster_\(key)",
                    coordinate: centroid,
                    venues: cellVenues
                )
                items.append(.cluster(cluster))
            }
        }

        return items
    }

    /// Whether the current zoom level should use clustering.
    /// At very close zoom (span < threshold), show all individual markers.
    static func shouldCluster(region: MKCoordinateRegion) -> Bool {
        // ~500m span or less → no clustering
        region.span.latitudeDelta > 0.005
    }
}
