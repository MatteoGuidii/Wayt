import SwiftUI

/// Map annotation marker: category icon on a busyness-colored circle
/// with venue name label and optional wait-time badge.
struct VenueMarkerView: View {

    let venue: Venue
    let isSelected: Bool
    var isSaved: Bool = false

    private let markerSize: CGFloat = 40

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                // Main pin circle + anchor
                VStack(spacing: 0) {
                    Image(systemName: venue.category.icon)
                        .font(VenuuTheme.calloutBoldFont)
                        .foregroundStyle(.white)
                        .frame(width: markerSize, height: markerSize)
                        .background(markerBackground)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    borderColor,
                                    lineWidth: isSelected ? 2.5 : 1.5
                                )
                        )

                    // Anchor triangle
                    Triangle()
                        .fill(markerBackground)
                        .frame(width: 10, height: 6)
                        .offset(y: -1)
                }

                // Saved bookmark badge (top-left of circle)
                if isSaved {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(3)
                        .background(.orange, in: Circle())
                        .overlay(Circle().strokeBorder(.white, lineWidth: 1))
                        .offset(x: -6, y: -4)
                }

                // Wait-time badge (top-right of circle)
                if let wait = venue.estimatedWaitMinutes, wait > 0 {
                    waitBadge(minutes: wait)
                        .offset(x: 6, y: -4)
                }
            }

            // Venue name label
            Text(venue.name)
                .font(VenuuTheme.microFont)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(maxWidth: 72)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color(.systemBackground).opacity(0.85))
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .padding(.top, 2)
        }
        .shadow(
            color: .black.opacity(isSelected ? 0.25 : 0.15),
            radius: isSelected ? 6 : 3,
            y: 2
        )
        .scaleEffect(isSelected ? 1.12 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isSelected)
    }

    // MARK: - Marker background color

    private var markerBackground: Color {
        if venue.busyness == nil && venue.busynessConfidence == .none {
            return Color(.systemGray4)
        }
        return venue.busyness?.color ?? Color(.systemGray4)
    }

    // MARK: - Border color

    private var borderColor: Color {
        if venue.busyness == nil && venue.busynessConfidence == .none {
            return .white.opacity(0.7)
        }
        return .white.opacity(isSelected ? 0.95 : 0.7)
    }

    // MARK: - Wait Badge

    private func waitBadge(minutes: Int) -> some View {
        Text("\(minutes)m")
            .font(VenuuTheme.nanoFont)
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(markerBackground, in: Capsule())
            .overlay(Capsule().strokeBorder(.white, lineWidth: 1))
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
