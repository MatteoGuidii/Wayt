//
//  zyvoApp.swift
//  zyvo
//
//  Created by Matteo Guidi on 2025-11-12.
//

import SwiftUI
import Amplify
import AWSCognitoAuthPlugin

@main
struct zyvoApp: App {
    var body: some Scene {
        WindowGroup {
            AuthView()
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