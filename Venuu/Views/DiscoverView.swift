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
    
    // Scroll tracking
    @State private var scrollOffset: CGFloat = 0
    
    
    var body: some View {
        ZStack(alignment: .top) {
            // Background
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()
            
            // Ambient Gradient Mesh
            GeometryReader { proxy in
                ZStack {
                    Circle()
                        .fill(Color.purple.opacity(0.12))
                        .frame(width: proxy.size.width * 0.9)
                        .offset(x: -proxy.size.width * 0.3, y: -proxy.size.height * 0.2)
                        .blur(radius: 80)
                    
                    Circle()
                        .fill(Color.blue.opacity(0.12))
                        .frame(width: proxy.size.width * 0.9)
                        .offset(x: proxy.size.width * 0.3, y: -proxy.size.height * 0.1)
                        .blur(radius: 80)
                }
            }
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                // Scroll Offset Reader
                GeometryReader { proxy in
                    Color.clear.preference(key: ScrollOffsetPreferenceKey.self, value: proxy.frame(in: .named("scroll")).minY)
                }
                .frame(height: 0)
                
                VStack(spacing: 32) {
                    // Spacer for fixed header/search area
                    Spacer()
                        .frame(height: 60) 
                    
                    // Immersive Header
                    HStack(spacing: 6) {
                        Text(locationManager.currentCity)
                            .font(.system(size: 34, weight: .bold))
                        Image(systemName: "chevron.down.circle.fill")
                            .font(.system(size: 20)) // Sized to match text visually
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    
                    // Featured / Top Picks
                    if !venueDiscoveryManager.venues.isEmpty {
                        FeaturedVenuesView(selectedVenue: $selectedVenue)
                    }
                    
                    // Categories
                    CategoryFilterView(selectedCategory: $selectedCategory)
                    
                    // Map Preview Section
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Map View")
                                .font(.title3.weight(.bold))
                            Spacer()
                            Button(action: { showMap.toggle() }) {
                                HStack(spacing: 4) {
                                    Text(showMap ? "Hide" : "Show")
                                    Image(systemName: showMap ? "chevron.up" : "chevron.down")
                                }
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.blue)
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        if showMap {
                            DiscoverMapPreview(
                                cameraPosition: $cameraPosition,
                                userLocation: locationManager.userLocation?.coordinate,
                                selectedVenue: $selectedVenue
                            )
                            .frame(height: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .padding(.horizontal, 20)
                            .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
                            .transition(.scale(scale: 0.95).combined(with: .opacity))
                        }
                    }

                    // Feed List
                    if venueDiscoveryManager.isSearching && venueDiscoveryManager.venues.isEmpty {
                        ProgressView()
                            .padding(.vertical, 40)
                    } else {
                        NearbyVenuesList(selectedVenue: $selectedVenue)
                    }
                    
                    Spacer(minLength: 120) // Bottom padding tab bar
                }
            }
            .coordinateSpace(name: "scroll")
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                scrollOffset = value
            }
            .refreshable {
                if let location = locationManager.userLocation {
                    let radius = locationManager.region.span.toRadius()
                    venueDiscoveryManager.updateUserLocation(location, radius: radius)
                }
            }
            
            // Sticky Search Bar Area
            VStack(spacing: 0) {
                // Frosted Background when scrolled
                ZStack(alignment: .bottom) {
                    if scrollOffset < -50 {
                        Rectangle()
                            .fill(.ultraThinMaterial)
                            .ignoresSafeArea()
                    }
                    
                    DiscoverSearchBar(searchText: $searchText)
                        .padding(.bottom, 12)
                }
                .frame(height: 110) // Approx height including safe area
                
                Divider()
                    .opacity(scrollOffset < -50 ? 1 : 0)
            }
        }
        .sheet(item: $selectedVenue) { venue in
            VenueDetailView(venue: venueDiscoveryManager.venues.first(where: { $0.id == venue.id }) ?? venue)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .onReceive(locationManager.$region) { region in
            let center = CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)
            let radius = region.span.toRadius()
            venueDiscoveryManager.updateUserLocation(center, radius: radius)
        }
        .onChange(of: showMap) { oldValue, newValue in
            if newValue {
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
}

// Preference Key for Scroll Tracking
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

#Preview {
    DiscoverView()
        .environmentObject(LocationManager())
}
