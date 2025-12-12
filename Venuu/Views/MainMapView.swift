import Combine
import MapKit
import SwiftUI

struct MainMapView: View {
    let username: String
    let onSignOut: () -> Void
    
    @EnvironmentObject private var locationManager: LocationManager
    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var shouldFollowUser = true
    @State private var hasInitialLocation = false
    @State private var currentCoordinate: CLLocationCoordinate2D?
    @State private var currentPitch: CGFloat = 0
    @State private var currentHeading: CLLocationDirection = 0
    
    @EnvironmentObject var venueDiscoveryManager: VenueDiscoveryManager
    @State private var selectedVenue: Venue?
    @State private var peekVenue: Venue?
    @State private var showClusters = true
    @State private var clusterThreshold: CLLocationDistance = 150
    @State private var disableClusteringTemporarily = false
    @State private var currentMapSpan: MKCoordinateSpan?
    @State private var isProgrammaticZoom = false

    // Map scope to bind controls to this specific map
    @Namespace private var mapScope

    // Computed property for venue clusters
    private var venueClusters: [VenueCluster] {
        guard !venueDiscoveryManager.venues.isEmpty else { return [] }
        // If clustering is temporarily disabled, show all venues individually
        if disableClusteringTemporarily {
            return venueDiscoveryManager.venues.map { VenueCluster(venues: [$0]) }
        }
        return showClusters ? venueDiscoveryManager.venues.clustered(threshold: clusterThreshold) : venueDiscoveryManager.venues.map { VenueCluster(venues: [$0]) }
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            Map(position: $cameraPosition, interactionModes: .all, scope: mapScope) {
                UserAnnotation()

                // Venue clusters and markers
                // Fallback: if clustering fails or is empty, show all venues directly
                let clustersToShow = venueClusters.isEmpty ? venueDiscoveryManager.venues.map { VenueCluster(venues: [$0]) } : venueClusters

                ForEach(clustersToShow) { cluster in
                    if cluster.venues.count > 1 && showClusters && !disableClusteringTemporarily {
                        // Show cluster marker
                        Annotation("", coordinate: cluster.coordinate) {
                            ClusterMarker(venues: cluster.venues, userLocation: currentCoordinate)
                                .onTapGesture {
                                    // Zoom into cluster
                                    zoomToCluster(cluster)
                                }
                        }
                    } else {
                        // Show individual venue markers
                        ForEach(cluster.venues) { venue in
                            Annotation(venue.name, coordinate: venue.coordinate) {
                                VenueMarker(
                                    venue: venue,
                                    userLocation: currentCoordinate,
                                    onLongPress: {
                                        peekVenue = venue
                                    }
                                )
                                .onTapGesture {
                                    selectedVenue = venue
                                    // Smooth camera animation to venue
                                    animateCameraToVenue(venue)
                                }
                            }
                        }
                    }
                }
            }
            .mapControls { }
            .ignoresSafeArea(edges: .top)
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 8)
            }
            .mapStyle(.standard(elevation: .realistic))
            .simultaneousGesture(
                DragGesture(minimumDistance: 5).onChanged { _ in
                    shouldFollowUser = false
                    isProgrammaticZoom = false
                }
            )
            .simultaneousGesture(
                MagnificationGesture().onChanged { _ in
                    shouldFollowUser = false
                    isProgrammaticZoom = false
                }
            )
            .simultaneousGesture(
                RotationGesture().onChanged { _ in
                    shouldFollowUser = false
                    isProgrammaticZoom = false
                }
            )
            .onMapCameraChange(frequency: .continuous) { context in
                currentPitch = context.camera.pitch
                currentHeading = context.camera.heading

                // Track the current map span
                let region = context.region
                currentMapSpan = region.span

                // Re-enable clustering when zoomed out enough (only for user-initiated zooms)
                // If latitude span is > 0.05 degrees (~5.5km), re-enable clustering
                // Don't re-enable during programmatic zooms to prevent clustering during cluster tap zoom
                if disableClusteringTemporarily && !isProgrammaticZoom && region.span.latitudeDelta > 0.05 {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        disableClusteringTemporarily = false
                    }
                }
            }
            
            VStack(spacing: 0) {
                // Searching indicator with enhanced design
                if venueDiscoveryManager.isSearching {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.blue)
                        Text("Searching area...")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [.white.opacity(0.3), .white.opacity(0.1)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1.5
                            )
                    )
                    .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 5)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                Spacer()

                // Map controls
                HStack {
                    Spacer()
                    bottomControls
                }
            }
            .animation(.easeInOut(duration: 0.35), value: venueDiscoveryManager.isSearching)

            // Quick peek card overlay
            if let peekVenue = peekVenue {
                ZStack {
                    // Dimmed background
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                self.peekVenue = nil
                            }
                        }

                    VenueQuickPeekCard(
                        venue: peekVenue,
                        userLocation: currentCoordinate,
                        onDismiss: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                self.peekVenue = nil
                            }
                        }
                    )
                }
                .transition(.opacity)
            }
        }
        .mapScope(mapScope)
        .sheet(item: $selectedVenue) { venue in
            VenueDetailView(venue: venueDiscoveryManager.venues.first(where: { $0.id == venue.id }) ?? venue)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .task { locationManager.start() }
        .onReceive(locationManager.$region) { newRegion in
            // Store the current coordinate
            currentCoordinate = newRegion.center
            
            // Always update on the first location fix
            if !hasInitialLocation && CLLocationCoordinate2DIsValid(newRegion.center) && (newRegion.center.latitude != 0 || newRegion.center.longitude != 0) {
                hasInitialLocation = true
                updateCameraPosition(
                    coordinate: newRegion.center,
                    heading: locationManager.heading
                )
                return
            }

            // After initial location, only update if following user
            guard shouldFollowUser else { return }

            updateCameraPosition(
                coordinate: newRegion.center,
                heading: 0 // North-up orientation
            )
        }
        .onReceive(locationManager.$region) { region in
            // Trigger venue search when user location changes
            // We use the region center as a proxy for user location when tracking
            // Ideally, LocationManager should expose the raw CLLocation for better accuracy
            let location = CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)
            venueDiscoveryManager.updateUserLocation(location)
        }
    }
    
    private func updateCameraPosition(
        coordinate: CLLocationCoordinate2D,
        heading: CLLocationDirection,
        pitch: CGFloat? = nil,
        duration: Double = 0.35
    ) {
        let resolvedPitch = pitch ?? currentPitch
        currentPitch = resolvedPitch

        withAnimation(.easeInOut(duration: duration)) {
            cameraPosition = .camera(
                MapCamera(
                    centerCoordinate: coordinate,
                    distance: 500, // meters
                    heading: heading,
                    pitch: resolvedPitch
                )
            )
        }
    }
}

private extension MainMapView {
    /// Enhanced map controls with glass pill background
    var bottomControls: some View {
        VStack(spacing: 12) {
            // Recenter button
            Button(action: recenter) {
                Image(systemName: "location.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.blue)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)

            // Map pitch toggle
            MapPitchToggle(scope: mapScope)

            // Map compass
            MapCompass(scope: mapScope)
                .mapControlVisibility(.visible)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 10)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
        )
        .overlay(
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.3), .white.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
        .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 6)
        .padding(.bottom, 20)
        .padding(.trailing, 18)
    }
    
    var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let message = locationManager.statusMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.orange)
            } else {
                Label("Tracking your location", systemImage: "location.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.blue)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 8)
    }
    
    func recenter() {
        if let coordinate = currentCoordinate {
            updateCameraPosition(
                coordinate: coordinate,
                heading: locationManager.heading,
                duration: 1.5
            )
        } else {
            withAnimation(.easeInOut(duration: 1.5)) {
                cameraPosition = .userLocation(fallback: .automatic)
            }
        }
        locationManager.recenterOnUser()
    }
    
    var locationAccuracyDescription: String {
        switch locationManager.accuracyAuthorization {
        case .fullAccuracy:
            return "Full-precision location enabled"
        case .reducedAccuracy:
            return "Reduced accuracy – enable Precise Location for best results"
        @unknown default:
            return "Location accuracy unavailable"
        }
    }

    /// Zooms into a cluster of venues with a smooth animation
    func zoomToCluster(_ cluster: VenueCluster) {
        // Mark as programmatic zoom to prevent auto re-clustering
        isProgrammaticZoom = true

        // Stop following user immediately
        shouldFollowUser = false

        // Disable clustering to show individual venues
        // Use animation to ensure smooth transition
        withAnimation(.easeInOut(duration: 0.2)) {
            disableClusteringTemporarily = true
        }

        // Calculate bounding box for all venues in cluster
        let coordinates = cluster.venues.map { $0.coordinate }
        let minLat = coordinates.map { $0.latitude }.min() ?? cluster.coordinate.latitude
        let maxLat = coordinates.map { $0.latitude }.max() ?? cluster.coordinate.latitude
        let minLon = coordinates.map { $0.longitude }.min() ?? cluster.coordinate.longitude
        let maxLon = coordinates.map { $0.longitude }.max() ?? cluster.coordinate.longitude

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )

        // Calculate appropriate camera distance based on cluster size
        let latDelta = max((maxLat - minLat) * 2.5, 0.01)
        let lonDelta = max((maxLon - minLon) * 2.5, 0.01)
        // Convert span to approximate distance in meters
        // Using the larger of the two deltas to ensure all venues are visible
        let distance = max(latDelta, lonDelta) * 111_000 / 2.0 // Rough conversion: 1 degree ≈ 111km

        // Delay camera zoom to ensure view updates with individual markers first
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeInOut(duration: 0.8)) {
                // Use .camera() instead of .region() to preserve heading and pitch
                cameraPosition = .camera(
                    MapCamera(
                        centerCoordinate: center,
                        distance: distance,
                        heading: currentHeading, // Preserve current map rotation
                        pitch: currentPitch      // Preserve current pitch
                    )
                )
            }

            // Clear programmatic zoom flag after animation completes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                isProgrammaticZoom = false
            }
        }

        // Note: Clustering will automatically re-enable when user zooms out
        // (see onMapCameraChange handler)
    }

    /// Animates camera smoothly to a selected venue
    func animateCameraToVenue(_ venue: Venue) {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            cameraPosition = .camera(
                MapCamera(
                    centerCoordinate: venue.coordinate,
                    distance: 300, // Closer zoom for selected venue
                    heading: 0,
                    pitch: currentPitch
                )
            )
            shouldFollowUser = false
        }
    }
}

#Preview {
    MainMapView(username: "matteo@example.com", onSignOut: {})
        .environmentObject(LocationManager())
}
