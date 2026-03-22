import SwiftUI

/// Bold venue card for horizontal carousels — playful, Waze-inspired.
/// Shows a LookAround thumbnail at the top with venue info overlaid at the bottom.
struct VenueCard: View {

    let venue: Venue

    var body: some View {
        ZStack(alignment: .bottom) {
            // LookAround thumbnail fills the card
            LookAroundThumbnail(
                coordinate: venue.coordinate,
                category: venue.category,
                size: CGSize(width: 170, height: 160)
            )

            // Bottom overlay: name + badges on a gradient scrim
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if venue.isOpen == false {
                        statusBadge(
                            icon: "moon.zzz.fill",
                            text: "Closed",
                            color: Color(.systemGray)
                        )
                    } else if let busyness = venue.busyness {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(busyness.color)
                                .frame(width: 6, height: 6)
                            Text(busyness.label)
                                .font(WaytTheme.microFont)
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(busyness.color.opacity(0.8))
                        .clipShape(Capsule())
                    }

                    if let wait = venue.estimatedWaitMinutes, wait > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "clock.fill")
                                .font(WaytTheme.nanoFont)
                            Text("~\(wait)m")
                                .font(WaytTheme.microFont)
                        }
                        .foregroundStyle(.white.opacity(0.9))
                    }
                }

                Text(venue.name)
                    .font(WaytTheme.subheadFont)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(
                LinearGradient(
                    colors: [.clear, .black.opacity(0.6)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .frame(width: 170, height: 160)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .busynessGlow(venue.isOpen == false ? nil : venue.busyness?.color)
    }

    private func statusBadge(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .medium))
            Text(text)
                .font(WaytTheme.microFont)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(color.opacity(0.8))
        .clipShape(Capsule())
    }
}
