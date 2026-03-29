import SwiftUI

/// Bold card-style venue row — playful, glanceable, Waze-inspired.
struct VenueRow: View {

    let venue: Venue

    var body: some View {
        HStack(spacing: 12) {
            // Category icon (pin-shaped)
            ZStack {
                PinShape()
                    .fill(venue.category.color.opacity(0.12))
                    .frame(width: 44, height: 50)

                Image(systemName: venue.category.icon)
                    .font(WaytTheme.calloutBoldFont)
                    .foregroundStyle(venue.category.color)
                    .offset(y: -2)
            }

            // Venue info
            VStack(alignment: .leading, spacing: 4) {
                Text(venue.name)
                    .font(WaytTheme.cardTitleFont)
                    .lineLimit(1)

                Text(venue.primaryTypeDisplayName ?? venue.category.shortName)
                    .font(WaytTheme.captionLightFont)
                    .foregroundStyle(WaytTheme.secondaryText)
                    .lineLimit(1)

                // Hours row
                if let isOpen = venue.isOpen {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(isOpen ? .green : .red)
                            .frame(width: 7, height: 7)
                        Text(isOpen ? "Open" : "Closed")
                            .font(WaytTheme.captionFont)
                            .foregroundStyle(isOpen ? .green : .red)
                        if let hours = venue.hoursToday {
                            Text("· \(hours)")
                                .font(WaytTheme.captionLightFont)
                                .foregroundStyle(WaytTheme.secondaryText)
                                .lineLimit(1)
                        }
                    }
                }
            }

            Spacer()

            BusynessBadge(
                level: venue.busyness,
                confidence: venue.busynessConfidence,
                style: .compact,
                isOpen: venue.isOpen
            )
        }
        .padding(12)
        .background(WaytTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
        .busynessGlow(venue.isOpen == false ? nil : venue.busyness?.color, radius: 6, y: 3)
    }

}
