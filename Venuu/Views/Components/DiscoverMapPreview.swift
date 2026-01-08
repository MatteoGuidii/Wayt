import SwiftUI
import MapKit

struct DiscoverMapPreview: View {
    @Binding var cameraPosition: MapCameraPosition
    let userLocation: CLLocationCoordinate2D?
    @EnvironmentObject var venueDiscoveryManager: VenueDiscoveryManager
    @Binding var selectedVenue: Venue?

    @State private var currentMapSpan: MKCoordinateSpan?
    @State private var cachedClusters: [VenueCluster] = []
    @State private var lastClusterThreshold: CLLocationDistance = 0

    // Dynamic clustering based on zoom level
    private var venueClusters: [VenueCluster] {
        guard !venueDiscoveryManager.venues.isEmpty else { return [] }

        // Calculate threshold based on span
        let span = currentMapSpan?.latitudeDelta ?? 0.05
        let thresholdMeters = span * 111_000 * 0.12

        // Only recalculate clusters if threshold changed significantly
        let thresholdChangeRatio = abs(thresholdMeters - lastClusterThreshold) / max(lastClusterThreshold, 1)
        let shouldRecalculate = cachedClusters.isEmpty || thresholdChangeRatio > 0.2

        if shouldRecalculate {
            let newClusters: [VenueCluster]

            if thresholdMeters < 50 {
                newClusters = venueDiscoveryManager.venues.map { VenueCluster(venues: [$0]) }
            } else {
                newClusters = venueDiscoveryManager.venues.clustered(threshold: thresholdMeters)
            }

            DispatchQueue.main.async {
                cachedClusters = newClusters
                lastClusterThreshold = thresholdMeters
            }

            return newClusters
        }

        return cachedClusters
    }

    var body: some View {
        Map(position: $cameraPosition) {
            if let userLocation = userLocation {
                Annotation("You", coordinate: userLocation) {
                    ZStack {
                        Circle()
                            .fill(.white)
                            .frame(width: 24, height: 24)
                        Circle()
                            .fill(.blue)
                            .frame(width: 18, height: 18)
                    }
                    .shadow(radius: 2)
                }
            }

            // Use clustering for better display of dense venue areas
            let clustersToShow = venueClusters.isEmpty ? venueDiscoveryManager.venues.map { VenueCluster(venues: [$0]) } : venueClusters

            ForEach(clustersToShow) { cluster in
                if cluster.venues.count > 1 {
                    // Show cluster marker
                    Annotation("", coordinate: cluster.coordinate) {
                        ClusterMarker(venues: cluster.venues, userLocation: userLocation)
                    }
                } else {
                    // Show individual venue
                    ForEach(cluster.venues) { venue in
                        Annotation(venue.name, coordinate: venue.coordinate) {
                            Button {
                                selectedVenue = venue
                            } label: {
                                Image(systemName: venue.systemImage)
                                    .padding(6)
                                    .background(venue.themeColor)
                                    .foregroundStyle(.white)
                                    .clipShape(Circle())
                                    .shadow(radius: 4)
                            }
                        }
                    }
                }
            }
        }
        .onMapCameraChange(frequency: .continuous) { context in
            currentMapSpan = context.region.span
        }
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 20)
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
        .onChange(of: venueDiscoveryManager.venues) { oldVenues, newVenues in
            // Invalidate cluster cache when venues change
            if oldVenues.count != newVenues.count || oldVenues.map({ $0.id }) != newVenues.map({ $0.id }) {
                cachedClusters = []
            }
        }
    }
}
