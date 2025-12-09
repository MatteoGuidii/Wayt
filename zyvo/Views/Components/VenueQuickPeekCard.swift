import SwiftUI
import MapKit

/// A floating quick peek card that appears when long-pressing a venue marker
struct VenueQuickPeekCard: View {
    let venue: Venue
    let userLocation: CLLocationCoordinate2D?
    let onDismiss: () -> Void

    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Venue image or icon
            ZStack(alignment: .topTrailing) {
                if let image = venue.image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 140)
                        .clipped()
                } else {
                    ZStack {
                        LinearGradient(
                            colors: [venue.themeColor.opacity(0.8), venue.themeColor],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .frame(height: 140)

                        Image(systemName: venue.systemImage)
                            .font(.system(size: 48, weight: .light))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }

                // Dismiss button
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .background(
                            Circle()
                                .fill(.black.opacity(0.3))
                                .blur(radius: 4)
                        )
                        .padding(12)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 8) {
                // Venue name
                Text(venue.name)
                    .font(.headline.weight(.bold))
                    .lineLimit(2)

                // Type badge
                HStack(spacing: 8) {
                    Image(systemName: venue.systemImage)
                        .font(.caption)
                    Text(venue.type.rawValue)
                        .font(.subheadline.weight(.medium))
                }
                .foregroundStyle(venue.themeColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(venue.themeColor.opacity(0.15))
                )

                // Distance
                if let distance = distanceText {
                    HStack(spacing: 6) {
                        Image(systemName: "location.fill")
                            .font(.caption)
                        Text(distance)
                            .font(.subheadline)
                    }
                    .foregroundStyle(.secondary)
                }

                // Quick action button
                Button {
                    // In a real app, this would navigate or show more details
                    onDismiss()
                } label: {
                    HStack {
                        Text("View Details")
                            .font(.subheadline.weight(.semibold))
                        Image(systemName: "arrow.right")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(venue.themeColor, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .frame(width: 280)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 24, x: 0, y: 12)
        .scaleEffect(appeared ? 1 : 0.8)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                appeared = true
            }
        }
    }

    private var distanceText: String? {
        guard let userLocation = userLocation else { return nil }
        let venueLoc = CLLocation(latitude: venue.coordinate.latitude, longitude: venue.coordinate.longitude)
        let userLoc = CLLocation(latitude: userLocation.latitude, longitude: userLocation.longitude)
        let distance = venueLoc.distance(from: userLoc)

        if distance < 1000 {
            return String(format: "%.0f m away", distance)
        } else {
            return String(format: "%.1f km away", distance / 1000)
        }
    }
}
