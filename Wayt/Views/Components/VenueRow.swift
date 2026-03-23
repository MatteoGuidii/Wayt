import SwiftUI
import CoreLocation

/// Bold card-style venue row — playful, glanceable, Waze-inspired.
struct VenueRow: View {

    let venue: Venue
    var userLocation: CLLocation?

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

                HStack(spacing: 6) {
                    Text(venue.category.shortName)
                        .font(WaytTheme.captionLightFont)
                        .foregroundStyle(WaytTheme.secondaryText)

                    if let distance = formattedDistance {
                        Circle()
                            .fill(Color.secondary.opacity(0.5))
                            .frame(width: 3, height: 3)
                        Text(distance)
                            .font(WaytTheme.captionLightFont)
                            .foregroundStyle(WaytTheme.secondaryText)
                    }

                    if let wait = venue.estimatedWaitMinutes, wait > 0 {
                        Circle()
                            .fill(Color.secondary.opacity(0.5))
                            .frame(width: 3, height: 3)
                        HStack(spacing: 2) {
                            Image(systemName: "clock.fill")
                                .font(WaytTheme.nanoFont)
                            Text("~\(wait)m")
                                .font(WaytTheme.captionFont)
                        }
                        .foregroundStyle(WaytTheme.secondaryText)
                    }
                }

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
                style: .compact
            )
        }
        .padding(12)
        .background(WaytTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
        .busynessGlow(venue.busyness?.color, radius: 6, y: 3)
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
