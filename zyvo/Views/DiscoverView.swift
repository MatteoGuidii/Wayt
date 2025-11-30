import SwiftUI
import MapKit
import CoreLocation

struct DiscoverView: View {
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var venueDiscoveryManager: VenueDiscoveryManager
    @State private var selectedVenue: Venue?
    @State private var searchText = ""
    
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
                    venueDiscoveryManager.updateUserLocation(location)
                }
            }
        }
        .sheet(item: $selectedVenue) { venue in
            VenueDetailView(venue: venueDiscoveryManager.venues.first(where: { $0.id == venue.id }) ?? venue)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .onReceive(locationManager.$region) { region in
            // Trigger search when we have a valid location
            let location = CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)
            venueDiscoveryManager.updateUserLocation(location)
        }
    }
    
    // MARK: - Sections
    
    var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(timeBasedGreeting)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            
            Text("Find your vibe")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
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
                    venueDiscoveryManager.search(text: searchText)
                }
            
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    venueDiscoveryManager.search(text: "")
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
        if selectedCategory == category {
            // Deselect and clear search
            selectedCategory = nil
            venueDiscoveryManager.search(text: "")
        } else {
            // Select and search
            selectedCategory = category
            venueDiscoveryManager.search(text: category)
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
        case 5..<12: return "Good Morning"
        case 12..<17: return "Good Afternoon"
        case 17..<22: return "Good Evening"
        default: return "Good Night"
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
            Text(label)
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
