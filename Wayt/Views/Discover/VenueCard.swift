import SwiftUI

/// Bold venue card for horizontal carousels — playful, Waze-inspired.
struct VenueCard: View {

    let venue: Venue

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Category icon + badge
            HStack(spacing: 8) {
                ZStack {
                    PinShape()
                        .fill(venue.category.color.opacity(0.15))
                        .frame(width: 36, height: 42)
                    Image(systemName: venue.category.icon)
                        .font(WaytTheme.cardTitleFont)
                        .foregroundStyle(venue.category.color)
                        .offset(y: -2)
                }

                Spacer()

                if let busyness = venue.busyness {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(busyness.color)
                            .frame(width: 7, height: 7)
                        Text(busyness.label)
                            .font(WaytTheme.microFont)
                            .foregroundStyle(busyness.color)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(busyness.color.opacity(0.12))
                    .clipShape(Capsule())
                }
            }

            Text(venue.name)
                .font(WaytTheme.subheadFont)
                .lineLimit(2)

            if let isOpen = venue.isOpen {
                HStack(spacing: 4) {
                    Circle()
                        .fill(isOpen ? .green : .red)
                        .frame(width: 6, height: 6)
                    Text(isOpen ? "Open" : "Closed")
                        .font(WaytTheme.badgeFont)
                        .foregroundStyle(isOpen ? .green : .red)
                    if let hours = venue.hoursToday {
                        Text("· \(hours)")
                            .font(WaytTheme.badgeFont)
                            .foregroundStyle(WaytTheme.secondaryText)
                    }
                }
                .lineLimit(1)
            }

            if let wait = venue.estimatedWaitMinutes, wait > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "clock.fill")
                        .font(WaytTheme.microFont)
                    Text("~\(wait) min wait")
                        .font(WaytTheme.badgeFont)
                }
                .foregroundStyle(WaytTheme.secondaryText)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(width: 170, height: 140, alignment: .topLeading)
        .background(
            ZStack {
                WaytTheme.cardBackground
                LinearGradient(
                    colors: [
                        (venue.busyness?.color ?? .clear).opacity(0.04),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .busynessGlow(venue.busyness?.color)
    }
}
