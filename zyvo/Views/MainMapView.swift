import Combine
import MapKit
import SwiftUI

struct MainMapView: View {
    let username: String
    let onSignOut: () -> Void

    @StateObject private var locationManager = LocationManager()
    @State private var cameraPosition: MapCameraPosition = .userLocation(
        fallback: .region(LocationManager.fallbackRegion)
    )
    @State private var shouldFollowUser = true

    var body: some View {
        ZStack(alignment: .top) {
            Map(position: $cameraPosition, interactionModes: .all) {
                UserAnnotation()
            }
            .ignoresSafeArea()
            .mapStyle(.standard(elevation: .realistic))
            .onMapCameraChange(frequency: .continuous) { context in
                let region = context.region
                locationManager.syncRegionWithCamera(region)
            }
            .highPriorityGesture(DragGesture(minimumDistance: 0).onChanged { _ in
                shouldFollowUser = false
            })
            .simultaneousGesture(MagnificationGesture().onChanged { _ in
                shouldFollowUser = false
            })

            VStack {
                header
                Spacer()
            }
        }
        .overlay(alignment: .bottomLeading) {
            statusCard
                .padding()
        }
        .overlay(alignment: .bottomTrailing) {
            controls
                .padding()
        }
        .task {
            locationManager.start()
            locationManager.recenterOnUser()
        }
        .onReceive(locationManager.$region) { newRegion in
            guard shouldFollowUser else { return }
            withAnimation(.easeInOut(duration: 0.35)) {
                cameraPosition = .region(newRegion)
            }
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
            Label(locationAccuracyDescription, systemImage: "scope")
                .font(.footnote.weight(.medium))

            if let message = locationManager.statusMessage {
                Text(message)
                    .font(.caption)
            } else {
                Text("Pan the map freely or use the crosshair to jump back to your precise position.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
            ControlButton(systemName: "plus.magnifyingglass") {
                zoom(by: 0.7)
            }
            ControlButton(systemName: "minus.magnifyingglass") {
                zoom(by: 1.3)
            }
        }
    }

    func recenter() {
        shouldFollowUser = true
        withAnimation(.easeInOut(duration: 0.35)) {
            cameraPosition = .userLocation(fallback: .region(locationManager.region))
        }
        locationManager.recenterOnUser()
    }

    func zoom(by factor: Double) {
        shouldFollowUser = false
        let newRegion = locationManager.adjustZoom(by: factor)
        cameraPosition = .region(newRegion)
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
        .environmentObject(AuthManager())
}
