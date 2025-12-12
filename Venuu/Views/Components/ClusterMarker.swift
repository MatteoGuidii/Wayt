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
            // Enhanced outer glow ring with more depth
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            dominantColor.opacity(0.5),
                            dominantColor.opacity(0.2),
                            dominantColor.opacity(0.05),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 60
                    )
                )
                .frame(width: 120, height: 120)
                .scaleEffect(isPulsing ? 1.3 : 1.0)
                .opacity(isPulsing ? 0.4 : 0.7)

            // Secondary pulse layer for more dynamic effect
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            dominantColor.opacity(0.3),
                            .clear
                        ],
                        center: .center,
                        startRadius: 20,
                        endRadius: 50
                    )
                )
                .frame(width: 100, height: 100)
                .scaleEffect(isPulsing ? 1.0 : 1.15)
                .opacity(isPulsing ? 0.5 : 0.2)

            // Main cluster circle with enhanced depth
            ZStack {
                // Outer shadow ring for depth
                Circle()
                    .fill(dominantColor.opacity(0.3))
                    .frame(width: 76, height: 76)
                    .blur(radius: 8)

                // Enhanced gradient background with 3-color gradient
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                dominantColor.opacity(0.95),
                                dominantColor,
                                dominantColor.opacity(0.85)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 68, height: 68)

                // Enhanced glassy highlight
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.6), .white.opacity(0.2), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 3
                    )
                    .frame(width: 68, height: 68)

                // Enhanced count display
                VStack(spacing: 1) {
                    Text("\(venues.count)")
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                    Text("venues")
                        .font(.system(size: 9, weight: .semibold))
                        .textCase(.uppercase)
                        .tracking(0.5)
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 3, x: 0, y: 2)
            }
            .shadow(color: dominantColor.opacity(0.6), radius: 16, x: 0, y: 8)


        }
        .onAppear {
            withAnimation(
                .easeInOut(duration: 2.5)
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
