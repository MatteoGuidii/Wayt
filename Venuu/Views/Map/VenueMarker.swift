import SwiftUI

/// Map annotation marker: venue icon with busyness-colored ring.
struct VenueMarkerView: View {

    let venue: Venue
    let isSelected: Bool

    var body: some View {
        ZStack {
            // Busyness ring
            Circle()
                .fill(ringColor.opacity(0.20))
                .frame(width: markerSize, height: markerSize)

            Circle()
                .strokeBorder(ringColor, lineWidth: isSelected ? 3 : 2)
                .frame(width: markerSize, height: markerSize)

            // Venue type icon
            Image(systemName: venue.type.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(venue.type.color)
        }
        .scaleEffect(isSelected ? 1.2 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
        .shadow(color: ringColor.opacity(0.3), radius: isSelected ? 6 : 3, y: 2)
    }

    private var ringColor: Color {
        venue.busyness?.color ?? .gray
    }

    private var markerSize: CGFloat {
        VenuuTheme.markerSize
    }
}
