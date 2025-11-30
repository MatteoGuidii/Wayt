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
                    headerSection
                    
                    // Search
                    searchBar
                    
                    // Map Preview
                    if showMap {
                        mapSection
                    }
                    
                    if venueDiscoveryManager.isSearching && venueDiscoveryManager.venues.isEmpty {
                        ProgressView()
                            .padding(.top, 40)
                    } else {
                        // Featured / Top Picks
                        if !venueDiscoveryManager.venues.isEmpty {
                            featuredSection
                        }
                        
                        // Categories
                        categoriesSection
                        
                        // Vibes
                        vibesSection
                        
                        // Nearby List
                        nearbySection
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
        .onChange(of: locationManager.region.center.latitude) { oldValue, newValue in
            triggerSearchOnMapChange()
        }
        .onChange(of: locationManager.region.span.latitudeDelta) { oldValue, newValue in
            triggerSearchOnMapChange()
        }
        .onReceive(locationManager.$region) { region in
            // Sync camera position when location manager updates (e.g. GPS)
            // We only update if the map isn't being interacted with to avoid fighting
            // For now, we'll just set it if it's significantly different or on first load
            // A simple approach is to let the Map handle user interaction and only force update if needed.
            // But since we want the map to follow the user initially:
            // cameraPosition = .region(region) // This might cause loops if not careful
        }
    }
    
    private func triggerSearchOnMapChange() {
        // Debounce is handled in Manager, but we can also check if we should trigger
        let center = CLLocation(latitude: locationManager.region.center.latitude, longitude: locationManager.region.center.longitude)
        let radius = calculateRadius(from: locationManager.region.span)
        
        // Use the manager's update logic which handles distance checks
        venueDiscoveryManager.updateUserLocation(center, radius: radius)
    }
    
    private func calculateRadius(from span: MKCoordinateSpan) -> CLLocationDistance {
        // 1 degree of latitude is approx 111km
        // We take half the span as radius
        let meters = span.latitudeDelta * 111_000 / 2
        return max(500, min(meters, 50_000)) // Clamp between 500m and 50km
    }
    
    // MARK: - Sections
    
    var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(timeBasedGreeting)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            
            HStack {
                Text("Find your vibe")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Button {
                    withAnimation {
                        showMap.toggle()
                    }
                } label: {
                    Image(systemName: showMap ? "map.fill" : "map")
                        .font(.title2)
                        .foregroundStyle(.primary)
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }
    
    var searchBar: some View {
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
    
    var mapSection: some View {
        Map(position: $cameraPosition) {
            UserAnnotation()
            
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
        .onMapCameraChange(frequency: .continuous) { context in
            locationManager.region = context.region
        }
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 20)
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
    }
    
    var featuredSection: some View {
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
    
    @State private var selectedCategory: String?
    
    var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Categories")
                .font(.headline)
                .padding(.horizontal, 20)
                
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    Button {
                        toggleCategory("Live Music")
                    } label: {
                        CategoryChip(icon: "music.mic", label: "Live Music", isSelected: selectedCategory == "Live Music")
                    }
                    
                    Button {
                        toggleCategory("Bars")
                    } label: {
                        CategoryChip(icon: "wineglass.fill", label: "Bars", isSelected: selectedCategory == "Bars")
                    }
                    
                    Button {
                        toggleCategory("Food")
                    } label: {
                        CategoryChip(icon: "fork.knife", label: "Food", isSelected: selectedCategory == "Food")
                    }
                    
                    Button {
                        toggleCategory("Clubs")
                    } label: {
                        CategoryChip(icon: "figure.dance", label: "Clubs", isSelected: selectedCategory == "Clubs")
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
            }
        }
    }
    
    var vibesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Vibes")
                .font(.headline)
                .padding(.horizontal, 20)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(["Chill", "Party", "Date", "Fancy", "Good Mood"], id: \.self) { vibe in
                        Button {
                            toggleCategory(vibe)
                        } label: {
                            CategoryChip(
                                icon: getIconForVibe(vibe),
                                label: vibe,
                                isSelected: selectedCategory == vibe
                            )
                        }
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
            }
        }
    }
    
    private func getIconForVibe(_ vibe: String) -> String {
        switch vibe {
        case "Chill": return "leaf.fill"
        case "Party": return "party.popper.fill"
        case "Date": return "heart.fill"
        case "Fancy": return "star.fill"
        case "Good Mood": return "face.smiling.fill"
        default: return "sparkles"
        }
    }
    
    private func toggleCategory(_ category: String) {
        let radius = calculateRadius(from: locationManager.region.span)
        if selectedCategory == category {
            // Deselect and clear search
            selectedCategory = nil
            venueDiscoveryManager.search(text: "", radius: radius)
        } else {
            // Select and search
            selectedCategory = category
            venueDiscoveryManager.search(text: category, radius: radius)
        }
    }
    
    var nearbySection: some View {
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
    
    // MARK: - Helpers
    
    var timeBasedGreeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return NSLocalizedString("Good Morning", comment: "")
        case 12..<17: return NSLocalizedString("Good Afternoon", comment: "")
        case 17..<22: return NSLocalizedString("Good Evening", comment: "")
        default: return NSLocalizedString("Good Night", comment: "")
        }
    }
}

// MARK: - Subviews

struct FeaturedVenueCard: View {
    let venue: Venue
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Image
            if let image = venue.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 260, height: 160)
                    .clipped()
            } else {
                ZStack {
                    Rectangle()
                        .fill(venue.themeColor.gradient)
                    Image(systemName: venue.systemImage)
                        .font(.system(size: 40))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .frame(width: 260, height: 160)
            }
            
            // Info
            VStack(alignment: .leading, spacing: 6) {
                Text(venue.name)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                
                Text(venue.category?.rawValue.replacingOccurrences(of: "MKPOICategory", with: "") ?? "Venue")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            .padding(12)
            .frame(width: 260, alignment: .leading)
            .background(.ultraThinMaterial)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
    }
}

struct NearbyVenueRow: View {
    let venue: Venue
    
    var body: some View {
        HStack(spacing: 16) {
            // Thumb
            if let image = venue.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 70, height: 70)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(venue.themeColor.opacity(0.2))
                    .frame(width: 70, height: 70)
                    .overlay(
                        Image(systemName: venue.systemImage)
                            .foregroundStyle(venue.themeColor)
                    )
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(venue.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                Text(venue.category?.rawValue.replacingOccurrences(of: "MKPOICategory", with: "") ?? "Venue")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct CategoryChip: View {
    let icon: String
    let label: String
    var isSelected: Bool = false
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(NSLocalizedString(label, comment: ""))
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(isSelected ? .white : .primary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isSelected ? Color.blue : Color.clear)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(isSelected ? Color.blue : .secondary.opacity(0.2), lineWidth: 1)
        )
    }
}

#Preview {
    DiscoverView()
        .environmentObject(LocationManager())
}
