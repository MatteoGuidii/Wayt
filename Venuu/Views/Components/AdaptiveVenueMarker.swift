import SwiftUI
import MapKit

/// Display mode for venue markers at different zoom levels
enum MarkerDisplayMode {
    case dot       // Minimal: 16px colored dot for high density
    case icon      // Medium: 32px circle with icon only
    case full      // Complete: 36px circle with icon + venue name (on selection)
}

/// Adaptive venue marker that changes appearance based on zoom level
struct AdaptiveVenueMarker: View {
    let venue: Venue
    let displayMode: MarkerDisplayMode
    let userLocation: CLLocationCoordinate2D?
    let isSelected: Bool

    var isNearby: Bool {
        guard let userLocation = userLocation else { return false }
        return venue.coordinate.distance(to: userLocation) < 150
    }

    var body: some View {
        Group {
            switch displayMode {
            case .dot:
                DotMarker(
                    venue: venue,
                    isSelected: isSelected,
                    isNearby: isNearby
                )
            case .icon:
                IconMarker(
                    venue: venue,
                    isSelected: isSelected,
                    isNearby: isNearby
                )
            case .full:
                FullMarker(
                    venue: venue,
                    isSelected: isSelected,
                    isNearby: isNearby
                )
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: displayMode)
    }
}

// MARK: - Dot Marker (High Density)

private struct DotMarker: View {
    let venue: Venue
    let isSelected: Bool
    let isNearby: Bool

    var body: some View {
        Circle()
            .fill(venue.themeColor)
            .frame(width: 16, height: 16)
            .overlay(
                Circle()
                    .stroke(Color.white, lineWidth: isSelected ? 3 : 2)
            )
            .overlay(
                Group {
                    if isNearby && !isSelected {
                        Circle()
                            .stroke(venue.themeColor.opacity(0.4), lineWidth: 1.5)
                            .padding(-2)
                    }
                }
            )
            .shadow(color: Color.black.opacity(0.15), radius: isSelected ? 3 : 2, x: 0, y: 1)
            .scaleEffect(isSelected ? 1.2 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isSelected)
            .offset(y: -8)
    }
}

// MARK: - Icon Marker (Medium Density)

private struct IconMarker: View {
    let venue: Venue
    let isSelected: Bool
    let isNearby: Bool

    var body: some View {
        Circle()
            .fill(venue.themeColor)
            .frame(width: 32, height: 32)
            .overlay(
                Image(systemName: venue.systemImage)
                    .font(.system(size: 16, weight: .semibold))
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
                radius: isSelected ? 5 : 3,
                x: 0,
                y: 2
            )
            .scaleEffect(isSelected ? 1.15 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isSelected)
            .offset(y: -16)
    }
}

// MARK: - Full Marker (Low Density)

private struct FullMarker: View {
    let venue: Venue
    let isSelected: Bool
    let isNearby: Bool

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
            if isSelected {
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
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isSelected)
        .offset(y: -18)
    }
}

#Preview {
    ZStack {
        Color.gray.ignoresSafeArea()

        VStack(spacing: 40) {
            AdaptiveVenueMarker(
                venue: Venue(
                    mapItem: {
                        let coordinate = CLLocationCoordinate2D(latitude: 0, longitude: 0)
                        let placemark = MKPlacemark(coordinate: coordinate)
                        let item = MKMapItem(placemark: placemark)
                        item.name = "Sample Venue"
                        return item
                    }()
                ),
                displayMode: .dot,
                userLocation: nil,
                isSelected: false
            )

            AdaptiveVenueMarker(
                venue: Venue(
                    mapItem: {
                        let coordinate = CLLocationCoordinate2D(latitude: 0, longitude: 0)
                        let placemark = MKPlacemark(coordinate: coordinate)
                        let item = MKMapItem(placemark: placemark)
                        item.name = "Sample Venue"
                        return item
                    }()
                ),
                displayMode: .icon,
                userLocation: nil,
                isSelected: false
            )

            AdaptiveVenueMarker(
                venue: Venue(
                    mapItem: {
                        let coordinate = CLLocationCoordinate2D(latitude: 0, longitude: 0)
                        let placemark = MKPlacemark(coordinate: coordinate)
                        let item = MKMapItem(placemark: placemark)
                        item.name = "Sample Venue"
                        return item
                    }()
                ),
                displayMode: .full,
                userLocation: nil,
                isSelected: false
            )
        }
    }
}
