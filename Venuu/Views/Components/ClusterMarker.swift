import SwiftUI
import MapKit

/// A cluster marker that groups nearby venues together
struct ClusterMarker: View {
    let venues: [Venue]
    let userLocation: CLLocationCoordinate2D?

    @State private var isPulsing = false

    var dominantColor: Color {
        // Use a stable color calculation to prevent flickering
        // Sort venues by ID first for deterministic ordering
        let sortedVenues = venues.sorted { $0.id.uuidString < $1.id.uuidString }
        let types = sortedVenues.map { $0.type }
        let grouped = Dictionary(grouping: types) { $0 }

        // Find the most common type, using sorted keys for tie-breaking
        let mostCommon = grouped.sorted { first, second in
            if first.value.count != second.value.count {
                return first.value.count > second.value.count
            }
            // Tie-breaker: use alphabetical order of rawValue for stability
            return first.key.rawValue < second.key.rawValue
        }.first

        return mostCommon?.key.color ?? .blue
    }

    var body: some View {
        ZStack {
            // Subtle outer glow for depth
            Circle()
                .fill(dominantColor.opacity(0.15))
                .frame(width: 68, height: 68)
                .blur(radius: 4)
                .scaleEffect(isPulsing ? 1.1 : 1.0)
                .opacity(isPulsing ? 0.6 : 0.8)

            // Main sphere
            Circle()
                .fill(dominantColor)
                .frame(width: 60, height: 60)
                .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
                .shadow(color: dominantColor.opacity(0.3), radius: 8, x: 0, y: 4)

            // Subtle highlight for dimension
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.25),
                            Color.white.opacity(0.05),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
                .frame(width: 60, height: 60)

            // Count display
            Text("\(venues.count)")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: Color.black.opacity(0.2), radius: 1, x: 0, y: 1)
        }
        .onAppear {
            withAnimation(
                .easeInOut(duration: 2.0)
                .repeatForever(autoreverses: true)
            ) {
                isPulsing = true
            }
        }
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
        var remaining = self
        var clusters: [VenueCluster] = []

        while !remaining.isEmpty {
            let current = remaining.removeFirst()
            var clusterVenues = [current]

            // Find all venues within threshold distance
            remaining = remaining.filter { venue in
                let currentLoc = CLLocation(latitude: current.coordinate.latitude, longitude: current.coordinate.longitude)
                let venueLoc = CLLocation(latitude: venue.coordinate.latitude, longitude: venue.coordinate.longitude)
                let distance = currentLoc.distance(from: venueLoc)

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
