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
            // Enhanced Premium Glow Effect
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            venue.themeColor.opacity(0.6),
                            venue.themeColor.opacity(0.3),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 35
                    )
                )
                .frame(width: 70, height: 70)
                .blur(radius: 12)
                .scaleEffect(isNearby && isAnimating ? 1.3 : 1.0)
                .opacity(isNearby ? 1.0 : 0.0)

            // Enhanced Proximity Pulse Ring
            if isNearby {
                Circle()
                    .stroke(venue.themeColor.opacity(0.7), lineWidth: 2)
                    .frame(width: 90, height: 90)
                    .scaleEffect(isAnimating ? 1.15 : 0.85)
                    .opacity(isAnimating ? 0.0 : 0.6)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: false)) {
                            isAnimating = true
                        }
                    }
            }

            // Main Marker Content with enhanced depth
            VStack(spacing: 0) {
                if let image = venue.image {
                    // Enhanced image marker with better border
                    ZStack {
                        // Outer glow ring for depth
                        Circle()
                            .fill(venue.themeColor.opacity(0.3))
                            .frame(width: 62, height: 62)
                            .blur(radius: 4)

                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 56, height: 56)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .strokeBorder(
                                        LinearGradient(
                                            colors: [.white.opacity(0.9), .white.opacity(0.3)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 3
                                    )
                            )
                            .shadow(color: .black.opacity(0.4), radius: 10, x: 0, y: 6)
                    }
                } else {
                    ZStack {
                        // Outer glow ring for depth
                        Circle()
                            .fill(venue.themeColor.opacity(0.25))
                            .frame(width: 64, height: 64)
                            .blur(radius: 6)

                        // Enhanced gradient background
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        venue.themeColor.opacity(0.95),
                                        venue.themeColor,
                                        venue.themeColor.opacity(0.8)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 56, height: 56)
                            .shadow(color: venue.themeColor.opacity(0.6), radius: 10, x: 0, y: 6)

                        // Enhanced glassy highlight
                        Circle()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [.white.opacity(0.7), .white.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                            .frame(width: 56, height: 56)

                        Image(systemName: venue.systemImage)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 2)
                    }
                }

                // Enhanced triangle pointer with better visibility
                ZStack {
                    // Shadow for pointer
                    Image(systemName: "triangle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.black.opacity(0.2))
                        .rotationEffect(.degrees(180))
                        .offset(y: -4)
                        .blur(radius: 2)

                    // Main pointer with gradient
                    Image(systemName: "triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [venue.themeColor, venue.themeColor.opacity(0.8)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .rotationEffect(.degrees(180))
                        .offset(y: -5)
                }
            }
        }
        .scaleEffect((isNearby ? 1.15 : 1.0) * bounceScale * (isPressed ? 0.92 : 1.0))
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
