import SwiftUI
import MapKit

struct VibeFilterView: View {
    @Binding var selectedCategory: String?
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var venueDiscoveryManager: VenueDiscoveryManager
    
    var body: some View {
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
