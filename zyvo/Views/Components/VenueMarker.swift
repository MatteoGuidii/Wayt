import SwiftUI
import MapKit

struct VenueMarker: View {
    let venue: Venue
    let userLocation: CLLocationCoordinate2D?
    let onLongPress: () -> Void

    @State private var isAnimating = false
    @State private var isPressed = false
    @State private var appearAnimation = false

    var isNearby: Bool {
        guard let userLocation = userLocation else { return false }
        let venueLoc = CLLocation(latitude: venue.coordinate.latitude, longitude: venue.coordinate.longitude)
        let userLoc = CLLocation(latitude: userLocation.latitude, longitude: userLocation.longitude)
        return venueLoc.distance(from: userLoc) < 150
    }

    var body: some View {
        Button(action: onLongPress) {
            VStack(spacing: -2) { // Negative spacing to connect pill and pointer
                HStack(spacing: 8) {
                    // Icon Circle
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        venue.themeColor.opacity(0.9),
                                        venue.themeColor
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 32, height: 32)
                            .shadow(color: venue.themeColor.opacity(0.4), radius: 4, x: 0, y: 2)
                        
                        Image(systemName: venue.systemImage)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    
                    // Venue Name
                    Text(venue.name)
                        .font(.system(size: 13, weight: .bold)) // Bold for better readability
                        .foregroundStyle(.primary) // Auto adapts to light/dark
                        .lineLimit(1)
                        .padding(.trailing, 4)
                }
                .padding(.leading, 4)
                .padding(.vertical, 4)
                .padding(.trailing, 10)
                .background(Material.thick) // Thicker material for better contrast
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.6),
                                    .white.opacity(0.2)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 3)
                
                // Precision Pointer
                Image(systemName: "triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Material.thick) // Match the pill background
                    .rotationEffect(.degrees(180))
                    .offset(y: -4) // Tuck it up into the pill
                    .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 2)
                    .overlay(
                        // Optional: Add a colored tip to the pointer for extra precision styling
                         Image(systemName: "triangle.fill")
                             .font(.system(size: 6))
                             .foregroundStyle(venue.themeColor)
                             .rotationEffect(.degrees(180))
                             .offset(y: -3)
                             .opacity(0.8)
                    )
            }
            // Nearyby subtle pulse - applied to the whole stack or just the pill
            .overlay(
                Group {
                    if isNearby {
                        Capsule() // Pulse follows the main shape loosely
                            .stroke(venue.themeColor.opacity(0.5), lineWidth: 2)
                            .frame(height: 40) // Approximate height of the pill part
                            .offset(y: -5) // Shift up to match pill position
                            .scaleEffect(isAnimating ? 1.1 : 1.0)
                            .opacity(isAnimating ? 0.0 : 0.5)
                            .onAppear {
                                withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: false)) {
                                    isAnimating = true
                                }
                            }
                    }
                }
            )
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .scaleEffect(appearAnimation ? 1.0 : 0.1)
        .offset(y: -20) // Shift entire marker up so the pointer tip is at the coordinate
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        .onAppear {
             withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                 appearAnimation = true
             }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

#Preview {
    ZStack {
        Color.gray.ignoresSafeArea()
        
        VenueMarker(
            venue: Venue(
                 mapItem: MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0)))
            ),
            userLocation: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            onLongPress: {}
        )
    }
}
