import Combine
import SwiftUI

struct MainTabView: View {

    @StateObject private var tabSelection = TabSelection()
    @StateObject private var filterState = VenueFilterState()
    @StateObject private var mapViewModel = MapViewModel()
    @StateObject private var profileViewModel = ProfileViewModel()
    @StateObject private var savedVenuesVM = SavedVenuesViewModel()

    var body: some View {
        TabView(selection: $tabSelection.selectedTab) {
            MapScreen()
                .tabItem {
                    Label("Map", systemImage: "map.fill")
                }
                .tag(Tab.map)

            DiscoverScreen()
                .tabItem {
                    Label("Discover", systemImage: "magnifyingglass")
                }
                .tag(Tab.discover)

            ProfileScreen()
                .tabItem {
                    Label("Profile", systemImage: "person.fill")
                }
                .tag(Tab.profile)
        }
        .tint(VenuuTheme.mapsBlue)
        .environmentObject(tabSelection)
        .environmentObject(filterState)
        .environmentObject(mapViewModel)
        .environmentObject(profileViewModel)
        .environmentObject(savedVenuesVM)
        .task {
            mapViewModel.filterState = filterState
            mapViewModel.startLiveRefresh()
        }
    }
}

// MARK: - Tab

enum Tab: Hashable {
    case map
    case discover
    case profile
}

/// Observable wrapper so child views can switch tabs.
@MainActor
final class TabSelection: ObservableObject {
    @Published var selectedTab: Tab = .map
}
