import Combine
import SwiftUI

struct MainTabView: View {

    @EnvironmentObject private var authState: AuthState
    @StateObject private var tabSelection = TabSelection()
    @StateObject private var filterState = VenueFilterState()
    @StateObject private var mapViewModel = MapViewModel()
    @StateObject private var profileViewModel = ProfileViewModel()
    @StateObject private var savedVenuesVM = SavedVenuesViewModel()
    @State private var showRankCelebration = false

    var body: some View {
        ZStack {
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
            .tint(WaytTheme.mapsBlue)

            if showRankCelebration, let rank = profileViewModel.rankUpEvent {
                RankUpCelebration(rank: rank) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        showRankCelebration = false
                        profileViewModel.markRankUpCelebrated()
                    }
                }
                .transition(.opacity)
                .zIndex(100)
            }
        }
        .onChange(of: profileViewModel.rankUpEvent) { _, newValue in
            guard newValue != nil else { return }
            if !mapViewModel.venueSheetOpen {
                withAnimation(.easeIn(duration: 0.2)) {
                    showRankCelebration = true
                }
            }
        }
        .onChange(of: mapViewModel.venueSheetOpen) { _, isOpen in
            if !isOpen, profileViewModel.rankUpEvent != nil, !showRankCelebration {
                withAnimation(.easeIn(duration: 0.2)) {
                    showRankCelebration = true
                }
            }
        }
        .environmentObject(tabSelection)
        .environmentObject(filterState)
        .environmentObject(mapViewModel)
        .environmentObject(profileViewModel)
        .environmentObject(savedVenuesVM)
        .task {
            mapViewModel.filterState = filterState
            mapViewModel.startLiveRefresh()

            // Preload profile data as soon as tabs appear (don't wait for profile tab visit)
            if authState.isSignedIn {
                async let profileLoad: () = profileViewModel.loadProfile()
                async let venuesLoad: () = savedVenuesVM.loadSavedVenues()
                _ = await (profileLoad, venuesLoad)
            }
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
