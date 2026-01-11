import SwiftUI
import MapKit

/// A cluster marker that groups nearby venues together
struct ClusterMarker: View {
    let venues: [Venue]
    let userLocation: CLLocationCoordinate2D?

    var dominantTypes: [VenueType] {
        // Use a stable type calculation to prevent flickering
        // Sort venues by ID first for deterministic ordering
        let sortedVenues = venues.sorted { $0.id.uuidString < $1.id.uuidString }
        let types = sortedVenues.map { $0.type }
        let grouped = Dictionary(grouping: types) { $0 }

        // Sort by frequency, then alphabetically for stability
        return grouped.sorted { first, second in
            if first.value.count != second.value.count {
                return first.value.count > second.value.count
            }
            return first.key.rawValue < second.key.rawValue
        }.map { $0.key }
    }

    var dominantColor: Color {
        return dominantTypes.first?.color ?? .blue
    }

    var body: some View {
        Circle()
            .fill(dominantColor)
            .frame(width: 50, height: 50)
            .overlay(
                Circle()
                    .stroke(Color.white, lineWidth: 3)
            )
            .overlay(
                Text("\(venues.count)")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: Color.black.opacity(0.2), radius: 1, x: 0, y: 1)
            )
            .shadow(color: Color.black.opacity(0.2), radius: 5, x: 0, y: 2)
    }
}

/// Helper to group nearby venues into clusters
struct VenueCluster: Identifiable {
    let venues: [Venue]

    // Stable ID based on the venues in this cluster
    var id: String {
        // Sort venue IDs for consistent ordering, then hash them
        let sortedIDs = venues.map { $0.id.uuidString }.sorted()
        return sortedIDs.joined(separator: "-")
    }

    var coordinate: CLLocationCoordinate2D {
        let avgLat = venues.map { $0.coordinate.latitude }.reduce(0, +) / Double(venues.count)
        let avgLng = venues.map { $0.coordinate.longitude }.reduce(0, +) / Double(venues.count)
        return CLLocationCoordinate2D(latitude: avgLat, longitude: avgLng)
    }
}

extension Array where Element == Venue {
    /// Clusters venues that are within the specified distance (in meters)
    func clustered(threshold: CLLocationDistance = 100) -> [VenueCluster] {
        // Sort venues by ID first to ensure deterministic clustering
        // This prevents clusters from wobbling when venue array order changes
        var remaining = self.sorted { $0.id.uuidString < $1.id.uuidString }
        var clusters: [VenueCluster] = []

        while !remaining.isEmpty {
            let current = remaining.removeFirst()
            var clusterVenues = [current]

            // Find all venues within threshold distance
            remaining = remaining.filter { venue in
                let distance = current.coordinate.distance(to: venue.coordinate)
                if distance <= threshold {
                    clusterVenues.append(venue)
                    return false // Remove from remaining
                }
                return true // Keep in remaining
            }

            clusters.append(VenueCluster(venues: clusterVenues))
        }

        return clusters
    }
}
