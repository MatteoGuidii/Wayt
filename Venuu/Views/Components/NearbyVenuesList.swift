import SwiftUI

struct NearbyVenuesList: View {
    @EnvironmentObject var venueDiscoveryManager: VenueDiscoveryManager
    @Binding var selectedVenue: Venue?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Nearby & Trending")
                .font(.title3.weight(.bold))
                .padding(.horizontal, 20)
            
            LazyVStack(spacing: 24) {
                // Show the rest of the venues
                ForEach(venueDiscoveryManager.venues) { venue in
                    NearbyVenueBigCard(venue: venue, onSave: {
                        // Handle save action
                    })
                    .onTapGesture {
                        selectedVenue = venue
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }
}
