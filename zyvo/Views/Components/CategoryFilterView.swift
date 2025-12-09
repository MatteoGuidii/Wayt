import SwiftUI
import MapKit

struct CategoryFilterView: View {
    @Binding var selectedCategory: String?
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var venueDiscoveryManager: VenueDiscoveryManager
    
    var body: some View {
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
    
    private func toggleCategory(_ category: String) {
        let radius = locationManager.region.span.toRadius()
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
}
