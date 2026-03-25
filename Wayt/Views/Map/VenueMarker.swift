import SwiftUI

/// Map annotation marker: category icon on a busyness-colored circle
/// with venue name label and optional wait-time badge.
/// Confidence is shown via ring treatment (dashed = estimated, thickness = data quality).
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
                        .font(WaytTheme.calloutBoldFont)
                        .foregroundStyle(.white)
                        .frame(width: markerSize, height: markerSize)
                        .background(markerBackground)
                        .clipShape(Circle())
                        .overlay(confidenceRing)

                    // Anchor triangle
                    Triangle()
                        .fill(markerBackground)
                        .frame(width: 10, height: 6)
                        .offset(y: -1)
                }

                // Saved bookmark badge (top-left of circle, hidden when wait time is shown)
                if isSaved && (venue.estimatedWaitMinutes ?? 0) <= 0 {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(3)
                        .background(WaytTheme.savedOrange, in: Circle())
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
                .font(WaytTheme.microFont)
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
        if venue.isOpen == false {
            return Color(.systemGray4)
        }
        if venue.busynessConfidence == .none {
            return Color(.systemGray4)
        }
        return venue.busyness?.color ?? Color(.systemGray4)
    }

    // MARK: - Confidence Ring

    /// Ring overlay that communicates data confidence:
    /// - Dashed ring for `.none` / `.estimated` (approximate/unknown data)
    /// - Solid ring with increasing thickness for higher confidence
    @ViewBuilder
    private var confidenceRing: some View {
        switch venue.busynessConfidence {
        case .none:
            Circle()
                .strokeBorder(
                    .white.opacity(0.7),
                    style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                )
        case .estimated:
            Circle()
                .strokeBorder(
                    .white.opacity(0.8),
                    style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                )
        case .low:
            Circle()
                .strokeBorder(.white.opacity(0.8), lineWidth: 1)
        case .medium:
            Circle()
                .strokeBorder(.white.opacity(0.85), lineWidth: 1.5)
        case .high:
            Circle()
                .strokeBorder(.white.opacity(0.95), lineWidth: 2)
        case .veryHigh:
            Circle()
                .strokeBorder(.white, lineWidth: 2.5)
                .shadow(color: markerBackground.opacity(0.4), radius: 4)
        }
    }

    // MARK: - Wait Badge

    private func waitBadge(minutes: Int) -> some View {
        Text("\(minutes)m")
            .font(WaytTheme.nanoFont)
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
