import SwiftUI
import MapKit

/// Compact row for displaying a saved venue from backend data (no MKMapItem needed).
struct SavedVenueRow: View {

    let venue: SavedVenue
    var onTap: (() -> Void)?
    var onUnsave: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            // Category icon
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(venue.category.color.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: venue.category.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(venue.category.color)
            }

            // Name + address
            VStack(alignment: .leading, spacing: 2) {
                Text(venue.venueName)
                    .font(VenuuTheme.subheadFont)
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                if let address = venue.address {
                    Text(address)
                        .font(VenuuTheme.captionFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Unsave button
            if let onUnsave {
                Button {
                    onUnsave()
                } label: {
                    Image(systemName: "bookmark.slash.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.orange)
                }
            }

            // Directions button (secondary action)
            Button {
                let placemark = MKPlacemark(coordinate: venue.coordinate)
                let mapItem = MKMapItem(placemark: placemark)
                mapItem.name = venue.venueName
                mapItem.openInMaps(launchOptions: [
                    MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault
                ])
            } label: {
                Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(VenuuTheme.mapsBlue)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
    }
}
