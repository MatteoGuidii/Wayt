import SwiftUI
import MapKit

struct DiscoverMapPreview: View {
    @Binding var cameraPosition: MapCameraPosition
    let userLocation: CLLocationCoordinate2D?
    @EnvironmentObject var venueDiscoveryManager: VenueDiscoveryManager
    @Binding var selectedVenue: Venue?
    
    var body: some View {
        Map(position: $cameraPosition) {
            if let userLocation = userLocation {
                Annotation("You", coordinate: userLocation) {
                    ZStack {
                        Circle()
                            .fill(.white)
                            .frame(width: 24, height: 24)
                        Circle()
                            .fill(.blue)
                            .frame(width: 18, height: 18)
                    }
                    .shadow(radius: 2)
                }
            }
            
            ForEach(venueDiscoveryManager.venues) { venue in
                Annotation(venue.name, coordinate: venue.coordinate) {
                    Button {
                        selectedVenue = venue
                    } label: {
                        Image(systemName: venue.systemImage)
                            .padding(6)
                            .background(venue.themeColor)
                            .foregroundStyle(.white)
                            .clipShape(Circle())
                            .shadow(radius: 4)
                    }
                }
            }
        }
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 20)
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
    }
}
