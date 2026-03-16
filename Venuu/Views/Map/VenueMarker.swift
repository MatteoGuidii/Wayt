import SwiftUI

/// Map annotation marker: minimal capsule with busyness dot + category icon.
struct VenueMarkerView: View {

    let venue: Venue
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Capsule chip
            HStack(spacing: 6) {
                // Busyness dot
                Circle()
                    .fill(busynessColor)
                    .frame(width: 8, height: 8)

                // Category icon
                Image(systemName: venue.category.icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial)
            .background(isSelected ? busynessColor.opacity(0.08) : Color.clear)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(
                        isSelected ? busynessColor.opacity(0.5) : Color.black.opacity(0.06),
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
            )
            .shadow(
                color: isSelected ? busynessColor.opacity(0.25) : .black.opacity(0.12),
                radius: isSelected ? 8 : 4,
                y: isSelected ? 3 : 2
            )

            // Tiny anchor triangle
            Triangle()
                .fill(.ultraThinMaterial)
                .frame(width: 8, height: 5)
                .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
        }
        .scaleEffect(isSelected ? 1.1 : 1.0)
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
