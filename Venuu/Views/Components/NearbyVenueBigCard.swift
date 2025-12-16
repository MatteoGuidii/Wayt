import SwiftUI
import MapKit

struct NearbyVenueBigCard: View {
    let venue: Venue
    var onSave: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 0) {
            // Main Image Area
            ZStack(alignment: .topTrailing) {
                if let image = venue.image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 220)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(venue.themeColor.opacity(0.1))
                        .frame(height: 220)
                        .overlay(
                            Image(systemName: venue.systemImage)
                                .font(.system(size: 60))
                                .foregroundStyle(venue.themeColor.opacity(0.3))
                        )
                }
                
                // Save Button Overlay
                Button(action: { onSave?() }) {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: "bookmark") // or bookmark.fill if saved
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                        )
                        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                }
                .padding(16)
                
                // Gradient Overlay for Text Visibility
                VStack {
                    Spacer()
                    LinearGradient(
                        colors: [.black.opacity(0.7), .transparent],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                    .frame(height: 80)
                }
            }
            .frame(height: 220)
            
            // Content Area
            VStack(alignment: .leading, spacing: 12) {
                // Title and Rating
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(venue.name)
                            .font(.system(size: 20, weight: .bold, design: .default))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        
                        Text(venue.category?.rawValue.replacingOccurrences(of: "MKPOICategory", with: "") ?? "Venue")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    // Rating Badge (Mock for now, or real if available)
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.yellow)
                        Text("4.8")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                }
                
                Divider()
                    .padding(.vertical, 4)
                
                // Info Row
                HStack(spacing: 16) {
                    Label("1.2 km", systemImage: "location.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Label("$$$", systemImage: "dollarsign.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    Text("Open Now")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.1))
                        .clipShape(Capsule())
                }
            }
            .padding(16)
            .background(Color(uiColor: .secondarySystemBackground))
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 15, x: 0, y: 8)
    }
}

extension Color {
    static let transparent = Color.black.opacity(0)
}

#Preview {
    ZStack {
        Color.gray.opacity(0.1).ignoresSafeArea()
        NearbyVenueBigCard(
            venue: Venue(
                 mapItem: {
                     let coordinate = CLLocationCoordinate2D(latitude: 0, longitude: 0)
                     let placemark = MKPlacemark(coordinate: coordinate)
                     let item = MKMapItem(placemark: placemark)
                     item.name = "The Rooftop Lounge"
                     return item
                 }()
            )
        )
        .padding()
    }
}
