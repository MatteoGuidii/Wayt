import Amplify
import AWSCognitoAuthPlugin
import os
import SwiftUI

@main
struct WaytApp: App {

    @StateObject private var locationService = LocationService()
    @StateObject private var authState = AuthState()
    @AppStorage("wayt_theme") private var theme: String = "system"
    @Environment(\.scenePhase) private var scenePhase

    private var colorSchemeOverride: ColorScheme? {
        switch theme {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    init() {
        configureAmplify()
    }

    var body: some Scene {
        WindowGroup {
            AuthRootView()
                .environmentObject(locationService)
                .environmentObject(authState)
                .preferredColorScheme(colorSchemeOverride)
                .onChange(of: scenePhase) { _, newPhase in
                    Log.app.debug("Scene phase changed to \(String(describing: newPhase))")
                    switch newPhase {
                    case .active:
                        locationService.startUpdating()
                        locationService.requestFreshLocation()
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
            Log.app.info("Amplify configured successfully")
        } catch {
            Log.app.fault("Amplify configuration failed: \(error.localizedDescription)")
        }
    }
}
