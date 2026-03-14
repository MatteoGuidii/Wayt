import SwiftUI

/// Card showing venue info with busyness indicator.
struct VenueCard: View {

    let venue: Venue

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Top: icon + busyness badge
            HStack {
                ZStack {
                    Circle()
                        .fill(venue.category.color.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: venue.category.icon)
                        .font(.system(size: 16))
                        .foregroundStyle(venue.category.color)
                }

                Spacer()

                BusynessBadge(
                    level: venue.busyness,
                    confidence: venue.busynessConfidence,
                    style: .compact
                )
            }

            // Name
            Text(venue.name)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            // Type + address
            VStack(alignment: .leading, spacing: 2) {
                Text(venue.category.displayName)
                    .font(VenuuTheme.captionFont)
                    .foregroundStyle(.secondary)

                if let address = venue.address {
                    Text(address)
                        .font(VenuuTheme.badgeFont)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            // Wait time if available
            if let wait = venue.estimatedWaitMinutes, wait > 0 {
                Label("~\(wait) min wait", systemImage: "clock")
                    .font(VenuuTheme.badgeFont)
                    .foregroundStyle(.orange)
            }
        }
        .padding(14)
        .frame(width: 170, alignment: .leading)
        .venuuCard()
    }
}
