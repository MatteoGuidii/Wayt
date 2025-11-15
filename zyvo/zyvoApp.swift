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

    var body: some Scene {
        WindowGroup {
            ZStack {
                ZyvoAuthTheme.backgroundGradient
                    .ignoresSafeArea()
                
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
                    .environmentObject(locationManager)
                }
                .authenticatorTheme(ZyvoAuthTheme.authenticatorTheme)
            }
        }
    }
    
    init() {
        configureAmplify()
    }
    
    private func configureAmplify() {
        do {
            try Amplify.add(plugin: AWSCognitoAuthPlugin())
            try Amplify.configure()
            print("Amplify configured with Cognito Auth plugin")
        } catch {
            print("Failed to initialize Amplify with \(error)")
        }
    }
}
