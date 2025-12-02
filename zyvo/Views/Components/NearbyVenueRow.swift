import SwiftUI
import MapKit

struct NearbyVenueRow: View {
    let venue: Venue
    
    var body: some View {
        HStack(spacing: 16) {
            // Thumb
            if let image = venue.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 70, height: 70)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(venue.themeColor.opacity(0.2))
                    .frame(width: 70, height: 70)
                    .overlay(
                        Image(systemName: venue.systemImage)
                            .foregroundStyle(venue.themeColor)
                    )
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(venue.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                Text(venue.category?.rawValue.replacingOccurrences(of: "MKPOICategory", with: "") ?? "Venue")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
