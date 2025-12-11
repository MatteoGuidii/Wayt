import SwiftUI
import MapKit

/// A floating quick peek card that appears when long-pressing a venue marker
struct VenueQuickPeekCard: View {
    let venue: Venue
    let userLocation: CLLocationCoordinate2D?
    let onDismiss: () -> Void

    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Enhanced venue image or icon section
            ZStack(alignment: .topTrailing) {
                if let image = venue.image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 160)
                        .clipped()
                        .overlay(
                            // Subtle gradient overlay for better text readability
                            LinearGradient(
                                colors: [.clear, .black.opacity(0.1)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                } else {
                    ZStack {
                        // Enhanced gradient with more depth
                        LinearGradient(
                            colors: [
                                venue.themeColor.opacity(0.9),
                                venue.themeColor,
                                venue.themeColor.opacity(0.7)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .frame(height: 160)

                        // Background pattern for visual interest
                        Circle()
                            .fill(venue.themeColor.opacity(0.2))
                            .frame(width: 150, height: 150)
                            .blur(radius: 30)
                            .offset(x: -40, y: -30)

                        Image(systemName: venue.systemImage)
                            .font(.system(size: 56, weight: .light))
                            .foregroundStyle(.white.opacity(0.95))
                            .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                    }
                }

                // Enhanced dismiss button
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .background(
                            Circle()
                                .fill(.black.opacity(0.4))
                                .frame(width: 32, height: 32)
                                .blur(radius: 6)
                        )
                        .padding(14)
                }
                .buttonStyle(.plain)
            }

            // Content section with better spacing
            VStack(alignment: .leading, spacing: 12) {
                // Venue name with better typography
                Text(venue.name)
                    .font(.title3.weight(.bold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                // Enhanced type badge with icon
                HStack(spacing: 6) {
                    Image(systemName: venue.systemImage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(venue.themeColor) // Keep icon colored
                    Text(venue.type.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary) // TEXT IS NOW READABLE
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Material.thick) // Thicker material for background contrast
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(venue.themeColor.opacity(0.4), lineWidth: 1)
                )

                // Enhanced distance display
                if let distance = distanceText {
                    HStack(spacing: 6) {
                        Image(systemName: "location.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(venue.themeColor)
                        
                        Text(distance)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Material.thick)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(venue.themeColor.opacity(0.4), lineWidth: 1)
                    )
                }

                // Enhanced action button with gradient
                Button {
                    // In a real app, this would navigate or show more details
                    onDismiss()
                } label: {
                    HStack(spacing: 8) {
                        Text("View Details")
                            .font(.subheadline.weight(.bold))
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.subheadline)
                    }
                    .foregroundStyle(.white) // Keep white on colored button (usually ok with strong theme colors)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: [venue.themeColor, venue.themeColor.opacity(0.85)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                    .shadow(color: venue.themeColor.opacity(0.4), radius: 8, x: 0, y: 4)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 18)
        }
        .frame(width: 300)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.3), .white.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
        .shadow(color: .black.opacity(0.3), radius: 30, x: 0, y: 15)
        .scaleEffect(appeared ? 1 : 0.85)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
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
