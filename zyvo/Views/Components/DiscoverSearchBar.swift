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
                    let radius = calculateRadius(from: locationManager.region.span)
                    venueDiscoveryManager.search(text: searchText, radius: radius)
                }
            
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    let radius = calculateRadius(from: locationManager.region.span)
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
    
    private func calculateRadius(from span: MKCoordinateSpan) -> CLLocationDistance {
        // 1 degree of latitude is approx 111km
        // We take half the span as radius
        let meters = span.latitudeDelta * 111_000 / 2
        return max(500, min(meters, 50_000)) // Clamp between 500m and 50km
    }
}
