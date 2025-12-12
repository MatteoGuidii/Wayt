import SwiftUI
import MapKit

struct FeaturedVenueCard: View {
    let venue: Venue
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Image
            if let image = venue.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 260, height: 160)
                    .clipped()
            } else {
                ZStack {
                    Rectangle()
                        .fill(venue.themeColor.gradient)
                    Image(systemName: venue.systemImage)
                        .font(.system(size: 40))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .frame(width: 260, height: 160)
            }
            
            // Info
            VStack(alignment: .leading, spacing: 6) {
                Text(venue.name)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                
                Text(venue.category?.rawValue.replacingOccurrences(of: "MKPOICategory", with: "") ?? "Venue")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            .padding(12)
            .frame(width: 260, alignment: .leading)
            .background(.ultraThinMaterial)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
    }
}
