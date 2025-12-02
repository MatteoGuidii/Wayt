import SwiftUI
import MapKit
import CoreLocation

struct DiscoverView: View {
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var venueDiscoveryManager: VenueDiscoveryManager
    @State private var selectedVenue: Venue?
    @State private var searchText = ""
    @State private var showMap = true
    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var selectedCategory: String?
    
    var body: some View {
        ZStack {
            // Background
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()
            
            // Ambient Gradient Mesh
            GeometryReader { proxy in
                ZStack {
                    Circle()
                        .fill(Color.purple.opacity(0.15))
                        .frame(width: proxy.size.width * 0.8)
                        .offset(x: -proxy.size.width * 0.2, y: -proxy.size.height * 0.2)
                        .blur(radius: 60)
                    
                    Circle()
                        .fill(Color.blue.opacity(0.15))
                        .frame(width: proxy.size.width * 0.8)
                        .offset(x: proxy.size.width * 0.2, y: proxy.size.height * 0.1)
                        .blur(radius: 60)
                }
            }
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    // Header
                    DiscoverHeaderView(showMap: $showMap)
                    
                    // Search
                    DiscoverSearchBar(searchText: $searchText)
                    
                    // Map Preview
                    if showMap {
                        DiscoverMapPreview(
                            cameraPosition: $cameraPosition,
                            userLocation: locationManager.userLocation?.coordinate,
                            selectedVenue: $selectedVenue
                        )
                    }
                    
                    if venueDiscoveryManager.isSearching && venueDiscoveryManager.venues.isEmpty {
                        ProgressView()
                            .padding(.top, 40)
                    } else {
                        // Featured / Top Picks
                        if !venueDiscoveryManager.venues.isEmpty {
                            FeaturedVenuesView(selectedVenue: $selectedVenue)
                        }
                        
                        // Categories
                        CategoryFilterView(selectedCategory: $selectedCategory)
                        
                        // Vibes
                        VibeFilterView(selectedCategory: $selectedCategory)
                        
                        // Nearby List
                        NearbyVenuesList(selectedVenue: $selectedVenue)
                    }
                    
                    Spacer(minLength: 100) // Bottom padding for tab bar
                }
            }
            .refreshable {
                if let location = locationManager.userLocation {
                    // Calculate radius based on current span
                    let radius = calculateRadius(from: locationManager.region.span)
                    venueDiscoveryManager.updateUserLocation(location, radius: radius)
                }
            }
        }
        .sheet(item: $selectedVenue) { venue in
            VenueDetailView(venue: venueDiscoveryManager.venues.first(where: { $0.id == venue.id }) ?? venue)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .onReceive(locationManager.$region) { region in
            // Trigger venue search when user location changes
            // We use the region center as a proxy for user location when tracking
            let center = CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)
            let radius = calculateRadius(from: region.span)
            
            // Delegate update logic to manager (debounce, distance check)
            venueDiscoveryManager.updateUserLocation(center, radius: radius)
        }

        .onChange(of: showMap) { oldValue, newValue in
            if newValue {
                // Reset to user location/region when map is shown again
                if let location = locationManager.userLocation {
                    cameraPosition = .region(MKCoordinateRegion(
                        center: location.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                    ))
                } else {
                    cameraPosition = .region(locationManager.region)
                }
            }
        }
    }
    

    
    private func calculateRadius(from span: MKCoordinateSpan) -> CLLocationDistance {
        // 1 degree of latitude is approx 111km
        // We take half the span as radius
        let meters = span.latitudeDelta * 111_000 / 2
        return max(500, min(meters, 50_000)) // Clamp between 500m and 50km
    }
}

#Preview {
    DiscoverView()
        .environmentObject(LocationManager())
}
