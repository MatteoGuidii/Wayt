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
            
            let categories = [
                ("All", "square.grid.2x2.fill"),
                ("Restaurant", "fork.knife"),
                ("Cafe", "cup.and.saucer.fill"),
                ("Bakery", "birthday.cake.fill"),
                ("Bar", "wineglass.fill"),
                ("Pub", "mug.fill")
            ]
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(categories, id: \.0) { category, icon in
                        let isSelected = selectedCategory == (category == "All" ? nil : category)
                        
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                if category == "All" {
                                    selectedCategory = nil
                                } else {
                                    selectedCategory = category
                                }
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: icon)
                                    .font(.system(size: 14))
                                Text(category)
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(isSelected ? Color.blue : Color(uiColor: .secondarySystemBackground))
                            .foregroundStyle(isSelected ? .white : .primary)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .strokeBorder(isSelected ? Color.clear : Color.primary.opacity(0.1), lineWidth: 1)
                            )
                            .scaleEffect(isSelected ? 1.05 : 1.0)
                            .shadow(color: isSelected ? .blue.opacity(0.3) : .clear, radius: 8, x: 0, y: 4)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8) // Space for shadow
            }
        }
    }
    
    private func toggleCategory(_ category: String) {
        let radius = locationManager.region.span.toRadius()
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
}
