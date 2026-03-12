import SwiftUI
import Amplify
import AWSCognitoAuthPlugin

@main
struct VenuuApp: App {

    @StateObject private var locationService = LocationService()

    init() {
        configureAmplify()
    }

    var body: some Scene {
        WindowGroup {
            AuthRootView()
                .environmentObject(locationService)
        }
    }

    private func configureAmplify() {
        do {
            try Amplify.add(plugin: AWSCognitoAuthPlugin())
            try Amplify.configure()
            print("[Venuu] Amplify configured ✓")
        } catch {
            print("[Venuu] Amplify failed: \(error)")
        }
    }
}
