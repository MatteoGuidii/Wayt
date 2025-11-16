//
//  zyvoApp.swift
//  zyvo
//
//  Created by Matteo Guidi on 2025-11-12.
//

import SwiftUI
import Amplify
import Authenticator
import AWSCognitoAuthPlugin

@main
struct zyvoApp: App {
    @StateObject private var locationManager = LocationManager()

    init() {
        configureAmplify()
    }

    var body: some Scene {
        WindowGroup {
            AuthRootView()
                .environmentObject(locationManager)
        }
    }

    private func configureAmplify() {
        do {
            // If you ever call this from multiple places, guard with a flag.
            try Amplify.add(plugin: AWSCognitoAuthPlugin())
            try Amplify.configure()
            print("Amplify configured with Cognito Auth plugin")
        } catch {
            print("Failed to initialize Amplify with \(error)")
        }
    }
}

/// Root view that owns the Authenticator + background.
/// Keeping this separate helps avoid unnecessary re-renders of Authenticator.
struct AuthRootView: View {
    var body: some View {
        ZStack {
            // Background gradient fills entire screen
            ZyvoAuthTheme.backgroundGradient
                .ignoresSafeArea()
            
            // Authenticator on top
            Authenticator(
                headerContent: {
                    ZyvoAuthTheme.headerView
                }
            ) { state in
                MainMapView(username: state.user.username) {
                    Task {
                        await state.signOut()
                    }
                }
                .transition(.opacity.combined(with: .scale))
            }
            .authenticatorTheme(ZyvoAuthTheme.authenticatorTheme)
            .keyboardAccessoryPadding()
        }
    }
}

#Preview {
    AuthRootView()
}
