import Combine
import SwiftUI

struct MainTabView: View {

    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var authState: AuthState
    @StateObject private var tabSelection = TabSelection()
    @StateObject private var filterState = VenueFilterState()
    @StateObject private var mapViewModel = MapViewModel()
    @StateObject private var profileViewModel = ProfileViewModel()
    @StateObject private var savedVenuesVM = SavedVenuesViewModel()
    @State private var showRankCelebration = false
    @State private var sessionStart = Date()

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
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                sessionStart = Date()
                mapViewModel.startLiveRefresh()
                Task { await AnalyticsService.shared.track(.appSession, properties: ["action": .string("foreground")]) }
            case .background:
                let durationMs = Int(Date().timeIntervalSince(sessionStart) * 1000)
                mapViewModel.stopLiveRefresh()
                Task {
                    await AnalyticsService.shared.track(.appSession, properties: ["action": .string("background"), "durationMs": .int(durationMs)])
                    await AnalyticsService.shared.onBackground()
                }
            default:
                break
            }
        }
        .onChange(of: tabSelection.selectedTab) { oldTab, newTab in
            Task { await AnalyticsService.shared.track(.tabSwitch, properties: ["fromTab": .string("\(oldTab)"), "toTab": .string("\(newTab)")]) }
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
