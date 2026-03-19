import SwiftUI

/// Bold venue card for horizontal carousels — playful, Waze-inspired.
struct VenueCard: View {

    let venue: Venue

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top color strip — busyness accent
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(venue.busyness?.color ?? Color.gray.opacity(0.3))
                    .frame(height: 5)
            }
            .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 10) {
                // Category icon + badge
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(venue.category.color.opacity(0.15))
                            .frame(width: 36, height: 36)
                        Image(systemName: venue.category.icon)
                            .font(VenuuTheme.cardTitleFont)
                            .foregroundStyle(venue.category.color)
                    }

                    Spacer()

                    if let busyness = venue.busyness {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(busyness.color)
                                .frame(width: 7, height: 7)
                            Text(busyness.label)
                                .font(VenuuTheme.microFont)
                                .foregroundStyle(busyness.color)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(busyness.color.opacity(0.12))
                        .clipShape(Capsule())
                    }
                }

                Text(venue.name)
                    .font(VenuuTheme.subheadFont)
                    .lineLimit(2)

                if let wait = venue.estimatedWaitMinutes, wait > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.fill")
                            .font(VenuuTheme.microFont)
                        Text("~\(wait) min wait")
                            .font(VenuuTheme.badgeFont)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .frame(width: 170, height: 120, alignment: .topLeading)
        .background(VenuuTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
}
