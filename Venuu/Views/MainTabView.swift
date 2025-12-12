//
//  MainTabView.swift
//  Venuu
//
//  Created by Claude Code
//

import SwiftUI

struct MainTabView: View {
    let username: String
    let onSignOut: () -> Void

    @State private var selectedTab = 0
    @StateObject private var venueDiscoveryManager = VenueDiscoveryManager()

    var body: some View {
        TabView(selection: $selectedTab) {
            // Map Tab
            MainMapView(username: username, onSignOut: onSignOut)
                .tabItem {
                    Label("Map", systemImage: "map.fill")
                }
                .tag(0)

            // Discover Tab
            DiscoverView()
                .tabItem {
                    Label("Discover", systemImage: "safari.fill")
                }
                .tag(1)

            // Post Tab
            PostView()
                .tabItem {
                    Label("Post", systemImage: "plus.circle.fill")
                }
                .tag(2)

            // Profile Tab
            ProfileView(username: username, onSignOut: onSignOut)
                .tabItem {
                    Label("Profile", systemImage: "person.fill")
                }
                .tag(3)
        }
        .environmentObject(venueDiscoveryManager)
        .accentColor(.purple) // Tab bar selected color
    }
}

#Preview {
    MainTabView(username: "matteo@example.com", onSignOut: {})
        .environmentObject(LocationManager())
}
