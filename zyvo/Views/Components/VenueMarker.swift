import SwiftUI
import MapKit

struct VenueMarker: View {
    let venue: Venue
    let userLocation: CLLocationCoordinate2D?
    let onLongPress: () -> Void

    @State private var isAnimating = false
    @State private var isPressed = false
    @State private var bounceScale: CGFloat = 1.0

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
        .scaleEffect((isNearby ? 1.15 : 1.0) * bounceScale * (isPressed ? 0.9 : 1.0))
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: isNearby)
        .animation(.spring(response: 0.3, dampingFraction: 0.5), value: isPressed)
        .onLongPressGesture(minimumDuration: 0.5) {
            // Trigger bounce animation
            withAnimation(.spring(response: 0.3, dampingFraction: 0.4)) {
                bounceScale = 1.2
            }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.4).delay(0.1)) {
                bounceScale = 1.0
            }
            onLongPress()
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                        isPressed = false
                    }
                }
        )
    }
}
