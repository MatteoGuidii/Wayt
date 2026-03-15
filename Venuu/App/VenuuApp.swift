import SwiftUI
import Amplify
import AWSCognitoAuthPlugin

@main
struct VenuuApp: App {

    @StateObject private var locationService = LocationService()
    @StateObject private var authState = AuthState()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        configureAmplify()
    }

    var body: some Scene {
        WindowGroup {
            AuthRootView()
                .environmentObject(locationService)
                .environmentObject(authState)
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .active:
                        locationService.startUpdating()
                    case .background:
                        locationService.stopUpdating()
                    default:
                        break
                    }
                }
        }
    }

    private func configureAmplify() {
        do {
            try Amplify.add(plugin: AWSCognitoAuthPlugin())
            try Amplify.configure()
            print("[Venuu] Amplify configured")
        } catch {
            print("[Venuu] Amplify failed: \(error)")
        }
    }
}
