import SwiftUI
import MapKit

struct FeaturedVenueCard: View {
    let venue: Venue
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Background Image
            if let image = venue.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 280, height: 350)
                    .clipped()
            } else {
                Rectangle()
                    .fill(venue.themeColor.gradient)
                    .frame(width: 280, height: 350)
                    .overlay(
                        Image(systemName: venue.systemImage)
                            .font(.system(size: 80))
                            .foregroundStyle(.white.opacity(0.3))
                    )
            }
            
            // Gradient Overlay
            LinearGradient(
                colors: [.black.opacity(0.8), .clear], // Changed .transparent to .clear as .transparent is not a standard color
                startPoint: .bottom,
                endPoint: .center
            )
            
            // Content
            VStack(alignment: .leading, spacing: 8) {
                // Badge
                Text("TRENDING")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                
                Spacer()
                
                Text(venue.name)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                
                HStack {
                    Label(venue.category?.rawValue.replacingOccurrences(of: "MKPOICategory", with: "") ?? "Venue", systemImage: "tag.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.9))
                    
                    Spacer()
                    
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                        Text("4.9")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .padding(20)
        }
        .frame(width: 280, height: 350)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
        // Spring animation on press
        .contentShape(Rectangle())
    }
}
