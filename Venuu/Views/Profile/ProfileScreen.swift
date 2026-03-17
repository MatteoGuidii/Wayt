import SwiftUI
import Amplify
import AWSCognitoAuthPlugin

struct ProfileScreen: View {

    @EnvironmentObject private var authState: AuthState
    @StateObject private var viewModel = ProfileViewModel()

    var body: some View {
        NavigationStack {
            if authState.isSignedIn {
                signedInContent
            } else {
                guestContent
            }
        }
        .task(id: authState.username ?? "") {
            if authState.isSignedIn {
                await viewModel.loadProfile()
            }
        }
    }

    // MARK: - Signed-In Content

    private var signedInContent: some View {
        let displayName = authState.username ?? "User"
        return List {
            // User info
            Section {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(VenuuTheme.skyPunch.opacity(0.15))
                            .frame(width: 56, height: 56)

                        Text(initials(for: displayName))
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(VenuuTheme.skyPunch)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(displayName)
                            .font(.system(size: 18, weight: .semibold))

                        if !viewModel.memberSince.isEmpty {
                            Text("Member since \(viewModel.memberSince)")
                                .font(VenuuTheme.captionFont)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 8)
            }

            // Stats
            Section("Activity") {
                HStack {
                    Label("Reports Submitted", systemImage: "megaphone.fill")
                    Spacer()
                    Text("\(viewModel.totalReports)")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(VenuuTheme.skyPunch)
                }
            }

            // About
            Section("About") {
                HStack {
                    Label("Version", systemImage: "info.circle")
                    Spacer()
                    Text(appVersion)
                        .foregroundStyle(.secondary)
                }
            }

            // Sign out
            Section {
                Button(role: .destructive) {
                    Task {
                        let result = await Amplify.Auth.signOut()
                        if let globalResult = result as? AWSCognitoSignOutResult,
                           case .failed = globalResult {
                            print("Sign-out failed")
                        } else {
                            authState.didSignOut()
                        }
                    }
                } label: {
                    HStack {
                        Spacer()
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle("Profile")
    }

    // MARK: - Guest Content

    private var guestContent: some View {
        VStack(spacing: 28) {
            Spacer()

            VenuuMascot(size: 120, expression: .happy)

            VStack(spacing: 10) {
                Text("Your profile")
                    .font(.system(size: 26, weight: .bold, design: .rounded))

                Text("Sign in to track your reports,\nsave favorites, and more.")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            Button {
                authState.requestSignIn()
            } label: {
                Text("Sign in or create account")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(VenuuTheme.skyPunch)
                    .clipShape(Capsule())
                    .shadow(color: VenuuTheme.skyPunch.opacity(0.3), radius: 10, y: 5)
            }
            .padding(.horizontal, 40)

            Spacer()
            Spacer()

            HStack {
                Label("Version \(appVersion)", systemImage: "info.circle")
                    .font(VenuuTheme.captionFont)
                    .foregroundStyle(.tertiary)
            }
            .padding(.bottom, 20)
        }
        .navigationTitle("Profile")
    }

    // MARK: - Helpers

    private func initials(for name: String) -> String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}

#Preview("Profile - Guest") {
    ProfileScreen()
        .environmentObject(AuthState())
}

#Preview("Profile - Signed In") {
    let auth = AuthState()
    auth.didSignIn(username: "Matteo")
    return ProfileScreen()
        .environmentObject(auth)
}
