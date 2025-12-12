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
    @State private var currentMapSpan: MKCoordinateSpan?
    @State private var isProgrammaticZoom = false

    // Map scope to bind controls to this specific map
    @Namespace private var mapScope

    // Dynamic clustering based on zoom level
    // As we zoom in (span gets smaller), the threshold for clustering (in meters) should decrease
    // to allow items to separate.
    private var venueClusters: [VenueCluster] {
        guard !venueDiscoveryManager.venues.isEmpty else { return [] }
        
        // Calculate threshold based on span
        // 1 degree latitude ~ 111,000 meters
        // We want to cluster if items are within ~10% of the visible map height
        let span = currentMapSpan?.latitudeDelta ?? 0.05
        let thresholdMeters = span * 111_000 * 0.12 // 12% factor
        
        // If threshold matches roughly the "zoomed in" state (e.g. < 50m), just uncluster everything for performance/UX
        if thresholdMeters < 50 {
             return venueDiscoveryManager.venues.map { VenueCluster(venues: [$0]) }
        }
        
        return venueDiscoveryManager.venues.clustered(threshold: thresholdMeters)
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            Map(position: $cameraPosition, interactionModes: .all, scope: mapScope) {
                UserAnnotation()

                // Venue clusters and markers
                // Fallback: if clustering fails or is empty, show all venues directly
                let clustersToShow = venueClusters.isEmpty ? venueDiscoveryManager.venues.map { VenueCluster(venues: [$0]) } : venueClusters

                ForEach(clustersToShow) { cluster in
                    if cluster.venues.count > 1 {
                        // Show cluster marker
                        Annotation("", coordinate: cluster.coordinate) {
                            ClusterMarker(venues: cluster.venues, userLocation: currentCoordinate)
                                .onTapGesture {
                                    // Zoom into cluster
                                    zoomToCluster(cluster)
                                }
                                .zIndex(1) // Ensure clusters are above individual markers
                        }
                    } else {
                        // Show individual venue markers
                        ForEach(cluster.venues) { venue in
                            Annotation(venue.name, coordinate: venue.coordinate) {
                                VenueMarker(
                                    venue: venue,
                                    userLocation: currentCoordinate,
                                    showTitle: (currentMapSpan?.latitudeDelta ?? 0) < 0.02, // Hide title when zoomed out
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

                // Track the current map span for dynamic clustering
                let region = context.region
                currentMapSpan = region.span
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
            
            // Always update on the first location fix if valid
            if !hasInitialLocation {
                if CLLocationCoordinate2DIsValid(newRegion.center) &&
                   newRegion.center.latitude != 0 &&
                   newRegion.center.longitude != 0 {
                    
                    hasInitialLocation = true
                    updateCameraPosition(
                        coordinate: newRegion.center,
                        heading: locationManager.heading
                    )
                }
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
            
            // Validate coordinates to prevent 0,0 clearing the map
            guard CLLocationCoordinate2DIsValid(region.center),
                  region.center.latitude != 0,
                  region.center.longitude != 0 else {
                return
            }
            
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
        // Mark as programmatic zoom
        isProgrammaticZoom = true
        shouldFollowUser = false
        
        // 1. Calculate the bounding MapRect
        let coordinates = cluster.venues.map { $0.coordinate }
        
        guard !coordinates.isEmpty else { return }
        
        // Create the union of all points
        var zoomRect = MKMapRect.null
        for coordinate in coordinates {
            let point = MKMapPoint(coordinate)
            // Use a tiny point rect for union
            let pointRect = MKMapRect(origin: point, size: MKMapSize(width: 1, height: 1))
            zoomRect = zoomRect.union(pointRect)
        }
        
        // 2. Check if points are effectively at the same location (singular rect)
        // If width and height are negligible, we can't "fit" a rect, we must just zoom to the coordinate.
        if zoomRect.width < 10 && zoomRect.height < 10 {
           // Case A: All items at same location. Zoom in very close.
            let center = cluster.coordinate // or zoomRect.center coordinate
             DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeInOut(duration: 1.0)) {
                    cameraPosition = .camera(
                        MapCamera(
                            centerCoordinate: center,
                            distance: 500, // Close enough to clearly see them (and hopefully separate if jitter is applied elsewhere)
                            heading: currentHeading,
                            pitch: currentPitch
                        )
                    )
                }
                resetZoomStateAfterDelay()
            }
            return
        }
        
        // 3. Normal Case: Fit the rect with padding
        // Scale the rect slightly so pins aren't on the edge.
        // A standard padding UIEdgeInsets is usually safer, but .rect(zoomRect) with automatic padding is often enough.
        // However, we can also manually inflate the rect if we want more control.
        let paddingScale: Double = 1.4 // 40% padding around the points
        let paddedRect = zoomRect.insetBy(dx: -zoomRect.width * (paddingScale - 1) / 2,
                                          dy: -zoomRect.height * (paddingScale - 1) / 2)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeInOut(duration: 1.0)) {
                // Use .rect to let MapKit figure out the best altitude
                cameraPosition = .rect(paddedRect)
            }
            resetZoomStateAfterDelay()
        }
    }
    
    private func resetZoomStateAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            isProgrammaticZoom = false
        }
    }
     // Note: Clustering will automatically re-enable when user zooms out
        // (see onMapCameraChange handler)
    

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
