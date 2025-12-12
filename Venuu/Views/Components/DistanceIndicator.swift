import SwiftUI
import MapKit

/// A visual line indicator showing distance from user to a venue
struct DistanceIndicator: View {
    let from: CLLocationCoordinate2D
    let to: CLLocationCoordinate2D
    let color: Color

    @State private var animationProgress: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                // This is a simplified representation - in reality, map coordinates
                // would need proper projection, but for visual effect this works
                path.move(to: CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2))
                path.addLine(to: CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2 + 50))
            }
            .trim(from: 0, to: animationProgress)
            .stroke(
                LinearGradient(
                    colors: [color.opacity(0.7), color.opacity(0.2)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                style: StrokeStyle(lineWidth: 2, dash: [5, 3])
            )
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                animationProgress = 1.0
            }
        }
    }
}
