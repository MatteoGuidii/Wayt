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
    
    @StateObject private var venueDiscoveryManager = VenueDiscoveryManager()
    @State private var selectedVenue: Venue?

    // Map scope to bind controls to this specific map
    @Namespace private var mapScope
    
    var body: some View {
        ZStack(alignment: .top) {
            Map(position: $cameraPosition, interactionModes: .all, scope: mapScope) {
                UserAnnotation()
                
                ForEach(venueDiscoveryManager.venues) { venue in
                    Annotation(venue.name, coordinate: venue.coordinate) {
                        VenueMarker(venue: venue, userLocation: currentCoordinate)
                            .onTapGesture {
                                selectedVenue = venue
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
                DragGesture(minimumDistance: 5).onChanged { _ in shouldFollowUser = false }
            )
            .simultaneousGesture(
                MagnificationGesture().onChanged { _ in shouldFollowUser = false }
            )
            .simultaneousGesture(
                RotationGesture().onChanged { _ in shouldFollowUser = false }
            )
            .onMapCameraChange(frequency: .continuous) { context in
                currentPitch = context.camera.pitch
            }
            
            VStack {
                if venueDiscoveryManager.isSearching {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Searching area...")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(.ultraThinMaterial, in: Capsule())
                    .shadow(radius: 4)
                    .padding(.top, 60)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                Spacer()
                bottomControls
            }
            .animation(.easeInOut, value: venueDiscoveryManager.isSearching)
        }
        .mapScope(mapScope)
        .sheet(item: $selectedVenue) { venue in
            VenueDetailView(venue: venue)
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
    /// Pill-shaped map controls pinned to the bottom trailing corner
    var bottomControls: some View {
        HStack {
            Spacer()
            VStack(spacing: 12) {
                ControlButton(systemName: "location.circle.fill", action: recenter)

                MapPitchToggle(scope: mapScope)
                    // .mapControlVisibility(.visible) // Force always visible

                MapCompass(scope: mapScope)
                     .mapControlVisibility(.visible) // Force always visible
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .shadow(radius: 8)
        }
        .padding(.bottom, 16)
        .padding(.trailing, 16)
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
                duration: 2.5
            )
        } else {
            withAnimation(.easeInOut(duration: 2.5)) {
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
}

private struct ControlButton: View {
    let systemName: String
    let action: () -> Void
    
    init(systemName: String, action: @escaping () -> Void) {
        self.systemName = systemName
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.black.opacity(0.65), in: Circle())
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
    }
}

struct VenueMarker: View {
    let venue: Venue
    let userLocation: CLLocationCoordinate2D?
    
    @State private var isAnimating = false
    
    var isNearby: Bool {
        guard let userLocation = userLocation else { return false }
        let venueLoc = CLLocation(latitude: venue.coordinate.latitude, longitude: venue.coordinate.longitude)
        let userLoc = CLLocation(latitude: userLocation.latitude, longitude: userLocation.longitude)
        return venueLoc.distance(from: userLoc) < 150
    }
    
    var body: some View {
        ZStack {
            // Premium Glow Effect
            // A soft, colored light behind the marker
            Circle()
                .fill(venue.themeColor.opacity(0.5))
                .frame(width: 60, height: 60)
                .blur(radius: 10)
                .scaleEffect(isNearby && isAnimating ? 1.2 : 1.0) // Breathing glow
                .opacity(isNearby ? 1.0 : 0.0) // Only glow when nearby
            
            // Proximity Pulse Ring (The "Call")
            if isNearby {
                Circle()
                    .stroke(venue.themeColor.opacity(0.6), lineWidth: 1)
                    .frame(width: 80, height: 80)
                    .scaleEffect(isAnimating ? 1.1 : 0.9)
                    .opacity(isAnimating ? 0.0 : 0.5)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: false)) {
                            isAnimating = true
                        }
                    }
            }
            
            // Main Marker Content
            VStack(spacing: 0) {
                if let image = venue.image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 52, height: 52)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [.white.opacity(0.8), .white.opacity(0.2)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 2
                                )
                        )
                        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 5)
                } else {
                    ZStack {
                        // Gradient Background
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [venue.themeColor.opacity(0.9), venue.themeColor],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 52, height: 52)
                            .shadow(color: venue.themeColor.opacity(0.5), radius: 8, x: 0, y: 5)
                        
                        // Glassy Highlight
                        Circle()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [.white.opacity(0.6), .clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                            .frame(width: 52, height: 52)
                        
                        Image(systemName: venue.systemImage)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                    }
                }
                
                // Little triangle pointer
                Image(systemName: "triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(venue.themeColor)
                    .rotationEffect(.degrees(180))
                    .offset(y: -6)
                    .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
            }
        }
        .scaleEffect(isNearby ? 1.1 : 1.0) // Slightly larger when nearby
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: isNearby)
    }
}

#Preview {
    MainMapView(username: "matteo@example.com", onSignOut: {})
        .environmentObject(LocationManager())
}
