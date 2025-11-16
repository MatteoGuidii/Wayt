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

    var body: some View {
        ZStack(alignment: .top) {
            Map(position: $cameraPosition, interactionModes: .all) {
                UserAnnotation()
            }
            .ignoresSafeArea(edges: .top)
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 8) 
            }
            .mapStyle(.standard(elevation: .realistic))
            .simultaneousGesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { _ in
                        shouldFollowUser = false
                    }
            )
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { _ in
                        shouldFollowUser = false
                    }
            )

            VStack {
                header
                Spacer()
            }
        }
        .overlay(alignment: .bottomTrailing) {
            controls
                .padding()
        }
        .task {
            locationManager.start()
        }
        .onReceive(locationManager.$region) { newRegion in
            // Store the current coordinate
            currentCoordinate = newRegion.center
            
            // Always update on the first location fix
            if !hasInitialLocation && CLLocationCoordinate2DIsValid(newRegion.center) && 
               (newRegion.center.latitude != 0 || newRegion.center.longitude != 0) {
                hasInitialLocation = true
                updateCameraPosition(coordinate: newRegion.center, heading: locationManager.heading)
                return
            }
            
            // After initial location, only update if following user
            guard shouldFollowUser else { return }
            updateCameraPosition(coordinate: newRegion.center, heading: locationManager.heading)
        }
        .onReceive(locationManager.$heading) { newHeading in
            // Update map rotation when heading changes, but only if following user
            guard shouldFollowUser,
                  let coordinate = currentCoordinate,
                  CLLocationCoordinate2DIsValid(coordinate) else { return }
            
            updateCameraPosition(coordinate: coordinate, heading: newHeading)
        }
    }
    
    private func updateCameraPosition(coordinate: CLLocationCoordinate2D, heading: CLLocationDirection) {
        withAnimation(.easeInOut(duration: 0.35)) {
            cameraPosition = .camera(
                MapCamera(
                    centerCoordinate: coordinate,
                    distance: 500, // Distance from ground in meters (zoom level)
                    heading: heading, // Rotation of the map based on user's direction
                    pitch: 60 // Tilt angle (0 = top-down, 90 = street view)
                )
            )
        }
    }
}

private extension MainMapView {
    var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Signed in as")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(username)
                    .font(.headline)
            }

            Spacer()

            Button(action: onSignOut) {
                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    .font(.subheadline.weight(.semibold))
            }
            .tint(.black)
            .labelStyle(.titleAndIcon)
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal)
        .padding(.top)
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

    var controls: some View {
        VStack(spacing: 12) {
            ControlButton(systemName: "location.circle.fill", action: recenter)
        }
    }

    func recenter() {
        shouldFollowUser = true
        if let coordinate = currentCoordinate {
            updateCameraPosition(coordinate: coordinate, heading: locationManager.heading)
        } else {
            withAnimation(.easeInOut(duration: 0.35)) {
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

#Preview {
    MainMapView(username: "matteo@example.com", onSignOut: {})
        .environmentObject(LocationManager())
}
