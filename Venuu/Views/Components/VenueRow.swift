import SwiftUI
import CoreLocation

/// Bold card-style venue row — playful, glanceable, Waze-inspired.
struct VenueRow: View {

    let venue: Venue
    var userLocation: CLLocation?

    var body: some View {
        HStack(spacing: 12) {
            // Busyness accent bar
            RoundedRectangle(cornerRadius: 3)
                .fill(venue.busyness?.color ?? Color.gray.opacity(0.3))
                .frame(width: 5, height: 52)

            // Category icon
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(venue.category.color.opacity(0.12))
                    .frame(width: 44, height: 44)

                Image(systemName: venue.category.icon)
                    .font(VenuuTheme.calloutBoldFont)
                    .foregroundStyle(venue.category.color)
            }

            // Venue info
            VStack(alignment: .leading, spacing: 4) {
                Text(venue.name)
                    .font(VenuuTheme.cardTitleFont)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(venue.category.shortName)
                        .font(VenuuTheme.captionLightFont)
                        .foregroundStyle(.secondary)

                    if let distance = formattedDistance {
                        Circle()
                            .fill(Color.secondary.opacity(0.5))
                            .frame(width: 3, height: 3)
                        Text(distance)
                            .font(VenuuTheme.captionLightFont)
                            .foregroundStyle(.secondary)
                    }

                    if let wait = venue.estimatedWaitMinutes, wait > 0 {
                        Circle()
                            .fill(Color.secondary.opacity(0.5))
                            .frame(width: 3, height: 3)
                        HStack(spacing: 2) {
                            Image(systemName: "clock.fill")
                                .font(VenuuTheme.nanoFont)
                            Text("~\(wait)m")
                                .font(VenuuTheme.captionFont)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            BusynessBadge(
                level: venue.busyness,
                confidence: venue.busynessConfidence,
                style: .compact
            )
        }
        .padding(12)
        .background(VenuuTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
    }

    // MARK: - Distance

    private var formattedDistance: String? {
        guard let userLocation else { return nil }
        let venueLocation = CLLocation(
            latitude: venue.coordinate.latitude,
            longitude: venue.coordinate.longitude
        )
        let meters = userLocation.distance(from: venueLocation)
        if meters < 1000 {
            return "\(Int(meters))m"
        } else {
            return String(format: "%.1fkm", meters / 1000)
        }
    }
}
