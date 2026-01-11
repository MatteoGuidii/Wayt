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
    @State private var currentMapSpan: MKCoordinateSpan?
    @State private var currentMapCenter: CLLocationCoordinate2D?
    @State private var isProgrammaticZoom = false

    // Cached clusters to prevent wobbling when recalculating
    @State private var cachedClusters: [VenueCluster] = []
    @State private var lastClusterThreshold: CLLocationDistance = 0

    // Visual-based clustering calculator
    private let clusterCalculator = VisualClusterCalculator()

    // Map scope to bind controls to this specific map
    @Namespace private var mapScope

    /// Determines if the "Search This Area" button should be shown
    /// Shows when user has panned significantly away from the last searched location
    private var shouldShowSearchAreaButton: Bool {
        guard !shouldFollowUser,
              !venueDiscoveryManager.isSearching,
              let mapCenter = currentMapCenter,
              let userCoord = currentCoordinate,
              currentMapSpan != nil else {
            return false
        }

        // Show button if map center is > 500m from user location
        let distance = mapCenter.distance(to: userCoord)
        return distance > 500
    }

    /// The current visible region for "Search This Area"
    private var visibleRegion: MKCoordinateRegion? {
        guard let center = currentMapCenter, let span = currentMapSpan else {
            return nil
        }
        return MKCoordinateRegion(center: center, span: span)
    }

    // Dynamic clustering based on visual overlap
    // Uses VisualClusterCalculator to determine when markers would actually overlap on screen
    private var venueClusters: [VenueCluster] {
        guard !venueDiscoveryManager.venues.isEmpty else { return [] }

        // If cache is valid, return it
        if !cachedClusters.isEmpty {
            return cachedClusters
        }

        // Calculate threshold based on visual overlap
        let span = currentMapSpan?.latitudeDelta ?? 0.05
        let thresholdMeters = clusterCalculator.calculateClusteringThreshold(latitudeDelta: span)

        // If threshold is below minimum, disable clustering for better UX
        if thresholdMeters < AppConfiguration.Map.minimumClusteringThreshold {
            return venueDiscoveryManager.venues.map { VenueCluster(venues: [$0]) }
        } else {
            return venueDiscoveryManager.venues.clustered(threshold: thresholdMeters)
        }
    }

    private func updateClustersIfNeeded() {
        guard !venueDiscoveryManager.venues.isEmpty else {
            cachedClusters = []
            return
        }

        let span = currentMapSpan?.latitudeDelta ?? 0.05
        let thresholdMeters = clusterCalculator.calculateClusteringThreshold(latitudeDelta: span)

        // Only recalculate if threshold changed significantly
        let thresholdChangeRatio = abs(thresholdMeters - lastClusterThreshold) / max(lastClusterThreshold, 1)
        guard cachedClusters.isEmpty || thresholdChangeRatio > AppConfiguration.Map.clusterRecalculationThreshold else {
            return
        }

        // Update cached clusters
        if thresholdMeters < AppConfiguration.Map.minimumClusteringThreshold {
            cachedClusters = venueDiscoveryManager.venues.map { VenueCluster(venues: [$0]) }
        } else {
            cachedClusters = venueDiscoveryManager.venues.clustered(threshold: thresholdMeters)
        }

        lastClusterThreshold = thresholdMeters
    }

    /// Determines marker display mode based on current zoom level
    private var markerDisplayMode: MarkerDisplayMode {
        let span = currentMapSpan?.latitudeDelta ?? 0.05
        if span > AppConfiguration.Map.dotOnlyZoomThreshold {
            return .dot
        } else if span > AppConfiguration.Map.iconOnlyZoomThreshold {
            return .icon
        } else {
            return .full
        }
    }

    var body: some View {
        let hasPendingImages = venueDiscoveryManager.venues.contains { $0.image == nil }

        return ZStack(alignment: .top) {
            mapView
            overlayContent(hasPendingImages: hasPendingImages)
        }
        .mapScope(mapScope)
        .sheet(item: $venueDiscoveryManager.selectedVenue) { venue in
            VenueDetailView(venue: venueDiscoveryManager.venues.first(where: { $0.id == venue.id }) ?? venue)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .onChange(of: venueDiscoveryManager.selectedVenue) { _, newValue in
            // Clear highlight when sheet is dismissed
            if newValue == nil {
                venueDiscoveryManager.highlightedVenueId = nil
            }
        }
        .task { locationManager.start() }
        .onAppear {
            locationManager.setHeadingUpdatesEnabled(true)
            locationManager.setHighAccuracyTrackingEnabled(true)
        }
        .onDisappear {
            locationManager.setHeadingUpdatesEnabled(false)
            locationManager.setHighAccuracyTrackingEnabled(false)
        }
        .onReceive(locationManager.$region) { newRegion in
            // Validate coordinates to prevent 0,0 clearing the map
            guard CLLocationCoordinate2DIsValid(newRegion.center),
                  newRegion.center.latitude != 0,
                  newRegion.center.longitude != 0 else {
                return
            }

            // Store the current coordinate
            currentCoordinate = newRegion.center

            // Trigger venue search when user location changes
            let location = CLLocation(latitude: newRegion.center.latitude, longitude: newRegion.center.longitude)
            venueDiscoveryManager.updateUserLocation(location)

            // Always update camera on the first location fix if valid
            if !hasInitialLocation {
                hasInitialLocation = true
                updateCameraPosition(
                    coordinate: newRegion.center,
                    heading: locationManager.heading
                )
                return
            }

            // After initial location, only update camera if following user
            guard shouldFollowUser else { return }

            updateCameraPosition(
                coordinate: newRegion.center,
                heading: 0 // North-up orientation
            )
        }
        .onChange(of: venueDiscoveryManager.venues) { oldVenues, newVenues in
            // Invalidate cluster cache when venues change
            if oldVenues.count != newVenues.count || oldVenues.map({ $0.id }) != newVenues.map({ $0.id }) {
                cachedClusters = []
                updateClustersIfNeeded()
            }
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
                    distance: AppConfiguration.Map.defaultCameraDistance,
                    heading: heading,
                    pitch: resolvedPitch
                )
            )
        }
    }
}

private extension MainMapView {
    /// Clusters to show on map (with fallback)
    private var clustersToShow: [VenueCluster] {
        venueClusters.isEmpty ? venueDiscoveryManager.venues.map { VenueCluster(venues: [$0]) } : venueClusters
    }

    /// Main map view with annotations
    var mapView: some View {
        Map(position: $cameraPosition, interactionModes: .all, scope: mapScope) {
            UserAnnotation()

            // Venue clusters and markers
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
                    // Show individual venue markers with adaptive display
                    ForEach(cluster.venues) { venue in
                        Annotation(venue.name, coordinate: venue.coordinate) {
                            AdaptiveVenueMarker(
                                venue: venue,
                                displayMode: markerDisplayMode,
                                userLocation: currentCoordinate,
                                isSelected: venueDiscoveryManager.highlightedVenueId == venue.id
                            )
                            .onTapGesture {
                                // 1. IMMEDIATE: Visual highlight
                                venueDiscoveryManager.highlightedVenueId = venue.id

                                // 2. IMMEDIATE: Haptic feedback
                                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                                impactFeedback.impactOccurred()

                                // 3. PARALLEL: Camera animation + sheet presentation
                                animateCameraToVenue(venue)
                                venueDiscoveryManager.selectedVenue = venue
                            }
                        }
                    }
                }
            }
        }
        .mapControls { }
        .ignoresSafeArea(edges: [.top])
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 8)
        }
        .mapStyle(MapStyle.standard(elevation: .realistic))
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
        .onMapCameraChange(frequency: MapCameraUpdateFrequency.continuous) { context in
            currentPitch = context.camera.pitch
            currentHeading = context.camera.heading

            // Track the current map span and center for dynamic clustering and search area
            let region = context.region
            currentMapSpan = region.span
            currentMapCenter = region.center

            // Update clusters when zoom level changes
            updateClustersIfNeeded()
        }
    }

    /// Overlay content including loading indicators and controls
    func overlayContent(hasPendingImages: Bool) -> some View {
        VStack(spacing: 10) {
            // Progressive loading indicator with enhanced design
            if case .loadingFromCache = venueDiscoveryManager.loadingState {
                loadingIndicator(text: "Loading...", progress: nil)
                    .transition(AnyTransition.move(edge: .top).combined(with: .opacity))
            } else if case .loadingPrimary(let progress) = venueDiscoveryManager.loadingState {
                loadingIndicator(text: "Discovering venues...", progress: progress)
                    .transition(AnyTransition.move(edge: .top).combined(with: .opacity))
            } else if case .loadingSecondary(let progress) = venueDiscoveryManager.loadingState {
                loadingIndicator(text: "Finding more venues...", progress: progress)
                    .transition(AnyTransition.move(edge: .top).combined(with: .opacity))
            }

            // Error indicator
            if let errorMessage = venueDiscoveryManager.searchError {
                errorIndicator(message: errorMessage)
            }

            if hasPendingImages {
                pendingImagesIndicator
            }

            // "Search This Area" button
            if shouldShowSearchAreaButton {
                searchAreaButton
            }

            Spacer()

            // Map controls
            HStack {
                Spacer()
                bottomControls
            }
        }
        .animation(.easeInOut(duration: 0.35), value: venueDiscoveryManager.loadingState)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: shouldShowSearchAreaButton)
    }

    /// Error indicator view
    func errorIndicator(message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline.weight(.medium))
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
                        colors: [.orange.opacity(0.3), .orange.opacity(0.1)],
                        startPoint: UnitPoint.top,
                        endPoint: UnitPoint.bottom
                    ),
                    lineWidth: 1.5
                )
        )
        .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 5)
        .padding(.top, 12)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    /// Pending images indicator
    var pendingImagesIndicator: some View {
        Text("Photos loading... Tap markers to explore venues")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.vertical, 4)
            .padding(.horizontal, 10)
            .background(
                Capsule()
                    .fill(.thinMaterial)
            )
    }

    /// Search this area button
    var searchAreaButton: some View {
        Button {
            guard let region = visibleRegion else { return }
            venueDiscoveryManager.searchRegion(region)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.subheadline.weight(.semibold))
                Text("Search This Area")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.vertical, 12)
            .padding(.horizontal, 20)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.blue, .blue.opacity(0.8)],
                            startPoint: UnitPoint.top,
                            endPoint: UnitPoint.bottom
                        )
                    )
            )
            .contentShape(Capsule())
            .shadow(color: .blue.opacity(0.4), radius: 10, x: 0, y: 5)
        }
        .buttonStyle(.plain)
        .transition(AnyTransition.scale.combined(with: .opacity))
    }

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
                        startPoint: UnitPoint.topLeading,
                        endPoint: UnitPoint.bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
        .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 6)
        .padding(.bottom, 20)
        .padding(.trailing, 18)
    }
    
    func recenter() {
        shouldFollowUser = true
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
                withAnimation(.easeInOut(duration: 0.5)) {
                    cameraPosition = .camera(
                        MapCamera(
                            centerCoordinate: center,
                            distance: AppConfiguration.Map.defaultCameraDistance,
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
        let paddedRect = zoomRect.insetBy(dx: -zoomRect.width * (AppConfiguration.Map.clusterZoomPaddingScale - 1) / 2,
                                          dy: -zoomRect.height * (AppConfiguration.Map.clusterZoomPaddingScale - 1) / 2)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeInOut(duration: 0.5)) {
                // Use .rect to let MapKit figure out the best altitude
                cameraPosition = .rect(paddedRect)
            }
            resetZoomStateAfterDelay()
        }
    }

    private func resetZoomStateAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isProgrammaticZoom = false
        }
    }
     // Note: Clustering will automatically re-enable when user zooms out
        // (see onMapCameraChange handler)
    

    /// Animates camera smoothly to a selected venue
    func animateCameraToVenue(_ venue: Venue) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            cameraPosition = .camera(
                MapCamera(
                    centerCoordinate: venue.coordinate,
                    distance: AppConfiguration.Map.selectedVenueCameraDistance,
                    heading: 0,
                    pitch: currentPitch
                )
            )
            shouldFollowUser = false
        }
    }

    /// Creates a loading indicator with optional progress
    @ViewBuilder
    func loadingIndicator(text: String, progress: Double?) -> some View {
        HStack(spacing: 10) {
            if let progress = progress {
                // Show progress ring
                ZStack {
                    Circle()
                        .stroke(Color.blue.opacity(0.2), lineWidth: 2)
                        .frame(width: 16, height: 16)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Color.blue, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 16, height: 16)
                        .rotationEffect(.degrees(-90))
                }
            } else {
                ProgressView()
                    .controlSize(.small)
                    .tint(.blue)
            }
            Text(text)
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
                        startPoint: UnitPoint.top,
                        endPoint: UnitPoint.bottom
                    ),
                    lineWidth: 1.5
                )
        )
        .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 5)
        .padding(.top, 12)
    }
}

#Preview {
    MainMapView(username: "matteo@example.com", onSignOut: {})
        .environmentObject(LocationManager())
        .environmentObject(VenueDiscoveryManager())
}
