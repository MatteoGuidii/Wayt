import SwiftUI

/// Map annotation marker: category icon on a busyness-colored circle.
struct VenueMarkerView: View {

    let venue: Venue
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Icon circle — background color = busyness level
            Image(systemName: venue.category.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(busynessColor)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .strokeBorder(
                            .white.opacity(isSelected ? 0.9 : 0.5),
                            lineWidth: isSelected ? 2 : 1
                        )
                )
                .shadow(
                    color: isSelected ? busynessColor.opacity(0.4) : .black.opacity(0.15),
                    radius: isSelected ? 8 : 4,
                    y: isSelected ? 3 : 2
                )

            // Tiny anchor triangle
            Triangle()
                .fill(busynessColor)
                .frame(width: 8, height: 5)
                .offset(y: -1)
        }
        .scaleEffect(isSelected ? 1.15 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isSelected)
    }

    private var busynessColor: Color {
        venue.busyness?.color ?? .gray
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
