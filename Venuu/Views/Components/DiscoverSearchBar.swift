import SwiftUI
import MapKit

struct DiscoverSearchBar: View {
    @Binding var searchText: String
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var venueDiscoveryManager: VenueDiscoveryManager
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            
            TextField("Search venues, vibes...", text: $searchText)
                .onSubmit {
                    let radius = locationManager.region.span.toRadius()
                    venueDiscoveryManager.search(text: searchText, radius: radius)
                }

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    let radius = locationManager.region.span.toRadius()
                    venueDiscoveryManager.search(text: "", radius: radius)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 20)
    }
}
