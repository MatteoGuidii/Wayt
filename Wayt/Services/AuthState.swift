import Amplify
import Combine
import os
import SwiftUI

/// Lightweight observable that tracks whether the user is signed in or browsing as guest.
/// Injected via `.environmentObject(authState)` from the app root.
@MainActor
final class AuthState: ObservableObject {

    @Published private(set) var isSignedIn = false
    @Published private(set) var username: String?
    @Published private(set) var displayName: String?

    /// Callback set by AuthRootView so guest→sign-in can be triggered from anywhere.
    var onRequestSignIn: (() -> Void)?

    /// Fired before navigating to auth so sheets/overlays can dismiss first.
    @Published private(set) var dismissSheets = false

    // MARK: - Check Session

    /// Call on launch to see if the user already has a valid Cognito session.
    func checkCurrentSession() async {
        do {
            let session = try await Amplify.Auth.fetchAuthSession()
            if session.isSignedIn {
                let user = try await Amplify.Auth.getCurrentUser()
                username = user.username
                isSignedIn = true
                Log.auth.info("Session valid, user signed in")
            } else {
                isSignedIn = false
                username = nil
                Log.auth.info("No active session, guest mode")
            }
        } catch {
            // No valid session — stay in guest mode
            isSignedIn = false
            username = nil
            Log.auth.notice("Session check failed, defaulting to guest mode: \(error.localizedDescription)")
        }
    }

    /// Called after successful Amplify sign-in/sign-up.
    func didSignIn(username: String) {
        self.username = username
        self.isSignedIn = true
        Log.auth.info("User signed in")
    }

    /// Called after sign-out.
    func didSignOut() {
        username = nil
        displayName = nil
        isSignedIn = false
        Log.auth.info("User signed out")
    }

    /// Updates the display name from the profile view model.
    func updateDisplayName(_ name: String) {
        displayName = name
    }

    /// Prompts the sign-in flow from wherever the user is.
    /// Dismisses any presented sheets first, then navigates after a short delay.
    func requestSignIn() {
        dismissSheets = true

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            dismissSheets = false
            onRequestSignIn?()
        }
    }
}
