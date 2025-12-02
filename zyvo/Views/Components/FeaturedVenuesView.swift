import SwiftUI

struct FeaturedVenuesView: View {
    @EnvironmentObject var venueDiscoveryManager: VenueDiscoveryManager
    @Binding var selectedVenue: Venue?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Featured")
                .font(.title3.weight(.bold))
                .padding(.horizontal, 20)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    // Show top 5 venues as featured
                    ForEach(venueDiscoveryManager.venues.prefix(5)) { venue in
                        FeaturedVenueCard(venue: venue)
                            .onTapGesture {
                                selectedVenue = venue
                            }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }
}
