import SwiftUI
import MapKit

struct VenueMarker: View {
    let venue: Venue
    let userLocation: CLLocationCoordinate2D?
    var showTitle: Bool = true
    var isSelected: Bool = false

    var isNearby: Bool {
        guard let userLocation = userLocation else { return false }
        return venue.coordinate.distance(to: userLocation) < 150
    }

    var body: some View {
        VStack(spacing: 6) {
            // Main circle marker
            Circle()
                .fill(venue.themeColor)
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: venue.systemImage)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                )
                .overlay(
                    Group {
                        if isSelected {
                            Circle()
                                .stroke(Color.white, lineWidth: 3)
                        } else if isNearby {
                            Circle()
                                .stroke(venue.themeColor.opacity(0.4), lineWidth: 1.5)
                        }
                    }
                )
                .shadow(
                    color: Color.black.opacity(0.15),
                    radius: isSelected ? 6 : 4,
                    x: 0,
                    y: 2
                )
                .scaleEffect(isSelected ? 1.2 : 1.0)

            // Name label - only when selected
            if showTitle && isSelected {
                Text(venue.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: 180)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(uiColor: .systemBackground))
                    )
                    .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .offset(y: -18)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isSelected)
    }
}

#Preview {
    ZStack {
        Color.gray.ignoresSafeArea()

        VenueMarker(
            venue: Venue(
                 mapItem: {
                     let coordinate = CLLocationCoordinate2D(latitude: 0, longitude: 0)
                     let placemark = MKPlacemark(coordinate: coordinate)
                     let item = MKMapItem(placemark: placemark)
                     item.name = "Sample Venue"
                     return item
                 }()
            ),
            userLocation: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            showTitle: true,
            isSelected: false
        )
    }
}
