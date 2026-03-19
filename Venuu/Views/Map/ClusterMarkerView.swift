import SwiftUI

/// Map annotation for a cluster of venues — shows venue count
/// colored by average busyness, matching individual marker convention.
struct ClusterMarkerView: View {

    let cluster: VenueCluster

    private let size: CGFloat = 44

    private var markerColor: Color {
        cluster.averageBusyness?.color ?? Color(.systemGray4)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(markerColor.gradient)
                    .frame(width: size, height: size)
                    .overlay(
                        Circle()
                            .strokeBorder(.white, lineWidth: 2)
                    )

                Text("\(cluster.count)")
                    .font(VenuuTheme.bodyBoldFont)
                    .foregroundStyle(.white)
            }

            // Anchor triangle
            Triangle()
                .fill(markerColor)
                .frame(width: 10, height: 6)
                .offset(y: -1)
        }
        .shadow(color: .black.opacity(0.15), radius: 3, y: 2)
    }
}

// MARK: - Anchor Triangle

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX - rect.width / 2, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX + rect.width / 2, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
