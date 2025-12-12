import SwiftUI

struct NearbyVenuesList: View {
    @EnvironmentObject var venueDiscoveryManager: VenueDiscoveryManager
    @Binding var selectedVenue: Venue?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Nearby")
                .font(.title3.weight(.bold))
                .padding(.horizontal, 20)
            
            LazyVStack(spacing: 16) {
                // Show the rest of the venues
                ForEach(Array(venueDiscoveryManager.venues.dropFirst(5).enumerated()), id: \.element.id) { index, venue in
                    NearbyVenueRow(venue: venue)
                        .onTapGesture {
                            selectedVenue = venue
                        }
                        .transition(.opacity.combined(with: .slide))
                        .animation(.easeOut.delay(Double(index) * 0.05), value: venueDiscoveryManager.venues)
                }
            }
            .padding(.horizontal, 20)
        }
    }
}
