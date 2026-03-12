import SwiftUI
import CoreLocation

/// Reusable list row showing venue info + busyness badge.
struct VenueRow: View {

    let venue: Venue
    var userLocation: CLLocation?

    var body: some View {
        HStack(spacing: 12) {
            // Venue type icon
            ZStack {
                Circle()
                    .fill(venue.type.color.opacity(0.15))
                    .frame(width: 44, height: 44)

                Image(systemName: venue.type.icon)
                    .font(.system(size: 18))
                    .foregroundStyle(venue.type.color)
            }

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(venue.name)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(venue.type.displayName)
                        .font(VenuuTheme.captionFont)
                        .foregroundStyle(.secondary)

                    if let distance = formattedDistance {
                        Text("•")
                            .foregroundStyle(.quaternary)
                        Text(distance)
                            .font(VenuuTheme.captionFont)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // Busyness badge
            BusynessBadge(
                level: venue.busyness,
                confidence: venue.busynessConfidence,
                style: .compact
            )
        }
        .padding(.vertical, 4)
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
