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
            // Outer glow ring
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            dominantColor.opacity(0.4),
                            dominantColor.opacity(0.1),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 50
                    )
                )
                .frame(width: 100, height: 100)
                .scaleEffect(isPulsing ? 1.2 : 1.0)
                .opacity(isPulsing ? 0.3 : 0.6)

            // Main cluster circle
            ZStack {
                // Gradient background
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [dominantColor.opacity(0.9), dominantColor],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 64, height: 64)

                // Inner ring
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.5), .white.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
                    .frame(width: 64, height: 64)

                // Count
                VStack(spacing: 2) {
                    Text("\(venues.count)")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("venues")
                        .font(.system(size: 9, weight: .medium))
                        .textCase(.uppercase)
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
            }
            .shadow(color: dominantColor.opacity(0.5), radius: 12, x: 0, y: 6)

            // Small type indicators around the circle
            if venues.count <= 5 {
                ForEach(Array(venues.prefix(5).enumerated()), id: \.element.id) { index, venue in
                    Image(systemName: venue.systemImage)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(venue.themeColor, in: Circle())
                        .shadow(radius: 2)
                        .offset(
                            x: cos(angle(for: index)) * 40,
                            y: sin(angle(for: index)) * 40
                        )
                }
            }
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

    private func angle(for index: Int) -> Double {
        let count = min(venues.count, 5)
        let angleStep = 2 * .pi / Double(count)
        return angleStep * Double(index) - .pi / 2 // Start from top
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
