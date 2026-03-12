import SwiftUI

struct MainTabView: View {

    let username: String
    let onSignOut: () -> Void

    @State private var selectedTab: Tab = .map

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

            ProfileScreen(username: username, onSignOut: onSignOut)
                .tabItem {
                    Label("Profile", systemImage: "person.fill")
                }
                .tag(Tab.profile)
        }
        .tint(VenuuTheme.primaryPurple)
    }
}

// MARK: - Tab

private enum Tab: Hashable {
    case map
    case discover
    case profile
}
