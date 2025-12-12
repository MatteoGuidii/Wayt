import SwiftUI
import MapKit

/// A pulsing, animated circle overlay that visualizes the search radius on the map
struct SearchRadiusOverlay: View {
    let center: CLLocationCoordinate2D
    let radius: CLLocationDistance

    @State private var isPulsing = false
    @State private var rotationAngle: Double = 0

    var body: some View {
        ZStack {
            // Outer pulsing ring
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.blue.opacity(0.3),
                            Color.purple.opacity(0.3),
                            Color.blue.opacity(0.3)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 3
                )
                .scaleEffect(isPulsing ? 1.05 : 1.0)
                .opacity(isPulsing ? 0.5 : 0.8)

            // Inner filled circle
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.blue.opacity(0.15),
                            Color.purple.opacity(0.1),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 200
                    )
                )
                .rotationEffect(.degrees(rotationAngle))

            // Dashed border
            Circle()
                .stroke(
                    style: StrokeStyle(
                        lineWidth: 2,
                        dash: [8, 6]
                    )
                )
                .foregroundStyle(Color.white.opacity(0.6))
                .scaleEffect(0.95)
        }
        .frame(width: radiusToPixels(), height: radiusToPixels())
        .onAppear {
            // Pulsing animation
            withAnimation(
                .easeInOut(duration: 2.5)
                .repeatForever(autoreverses: true)
            ) {
                isPulsing = true
            }

            // Slow rotation for visual interest
            withAnimation(
                .linear(duration: 20)
                .repeatForever(autoreverses: false)
            ) {
                rotationAngle = 360
            }
        }
    }

    /// Approximate conversion from meters to screen points
    /// This is a rough approximation for visualization purposes
    private func radiusToPixels() -> CGFloat {
        // Very rough: 1 degree latitude ≈ 111km
        // At typical zoom levels, we'll clamp this for visibility
        let degrees = radius / 111_000
        let pixels = degrees * 10000 // Adjust multiplier based on zoom
        return min(max(CGFloat(pixels), 100), 500) // Clamp between 100-500 pixels
    }
}
