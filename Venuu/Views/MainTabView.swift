import SwiftUI

struct MainTabView: View {

    @State private var selectedTab: Tab = .map
    @StateObject private var filterState = VenueFilterState()
    @StateObject private var mapViewModel = MapViewModel()

    var body: some View {
        TabView(selection: $selectedTab) {
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
        .environmentObject(filterState)
        .environmentObject(mapViewModel)
        .task {
            mapViewModel.filterState = filterState
            mapViewModel.startLiveRefresh()
        }
    }
}

// MARK: - Tab

private enum Tab: Hashable {
    case map
    case discover
    case profile
}
