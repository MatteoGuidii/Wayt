import Amplify
import AWSCognitoAuthPlugin
import os
import SwiftUI

struct SettingsScreen: View {

    @EnvironmentObject private var authState: AuthState
    @EnvironmentObject private var profileViewModel: ProfileViewModel
    @EnvironmentObject private var savedVenuesVM: SavedVenuesViewModel

    @AppStorage("wayt_theme") private var theme: String = "system"
    @AppStorage("wayt_distanceUnit") private var distanceUnit: String = "km"

    @State private var showDeleteConfirmation = false
    @State private var showDeleteError = false
    @State private var isDeletingAccount = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                appearanceCard
                unitsCard
                privacyCard
                aboutCard
            }
            .padding(.vertical, 16)
        }
        .background(WaytTheme.backgroundGradient)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete Account?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task { await deleteAccount() }
            }
        } message: {
            Text("This permanently deletes your account and all associated data. This action cannot be undone.")
        }
        .alert("Something went wrong", isPresented: $showDeleteError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Could not delete your account. Please try again later.")
        }
    }

    // MARK: - Appearance

    private var appearanceCard: some View {
        settingsCard {
            settingsRow(icon: "paintbrush.fill", iconColor: WaytTheme.mapsBlue) {
                Text("Theme")
                    .font(WaytTheme.subheadFont)
                Spacer()
                Picker("Theme", selection: $theme) {
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                    Text("System").tag("system")
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
        }
    }

    // MARK: - Units

    private var unitsCard: some View {
        settingsCard {
            settingsRow(icon: "ruler.fill", iconColor: WaytTheme.mapsBlue) {
                Text("Distance")
                    .font(WaytTheme.subheadFont)
                Spacer()
                Picker("Distance", selection: $distanceUnit) {
                    Text("km").tag("km")
                    Text("miles").tag("mi")
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
            }
        }
    }

    // MARK: - Privacy & Data

    private var privacyCard: some View {
        settingsCard {
            Button {
                showDeleteConfirmation = true
            } label: {
                settingsRow(icon: "person.crop.circle.badge.minus", iconColor: .red) {
                    Text("Delete Account")
                        .font(WaytTheme.subheadFont)
                        .foregroundStyle(.red)
                    Spacer()
                    if isDeletingAccount {
                        ProgressView()
                            .tint(.red)
                    }
                }
            }
            .disabled(isDeletingAccount)
        }
    }

    // MARK: - About

    private var aboutCard: some View {
        settingsCard {
            settingsRow(icon: "info.circle.fill", iconColor: WaytTheme.secondaryText) {
                Text("Version")
                    .font(WaytTheme.subheadFont)
                Spacer()
                Text(appVersion)
                    .font(WaytTheme.captionFont)
                    .foregroundStyle(.secondary)
            }

            Divider().padding(.leading, 40)

            Link(destination: URL(string: "https://wayt.app/terms")!) {
                settingsRow(icon: "doc.text.fill", iconColor: WaytTheme.secondaryText) {
                    Text("Terms of Service")
                        .font(WaytTheme.subheadFont)
                        .foregroundStyle(WaytTheme.primaryText)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
            }

            Divider().padding(.leading, 40)

            Link(destination: URL(string: "https://wayt.app/privacy")!) {
                settingsRow(icon: "hand.raised.fill", iconColor: WaytTheme.secondaryText) {
                    Text("Privacy Policy")
                        .font(WaytTheme.subheadFont)
                        .foregroundStyle(WaytTheme.primaryText)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: - Helpers

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(WaytTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: WaytTheme.cardShadow, radius: 6, x: 0, y: 3)
        .padding(.horizontal, 16)
    }

    private func settingsRow<Content: View>(
        icon: String,
        iconColor: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(iconColor)
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "–"
        return "\(version) (\(build))"
    }

    private func deleteAccount() async {
        isDeletingAccount = true
        defer { isDeletingAccount = false }

        do {
            try await APIClient.shared.delete(path: "/user/account")
            let result = await Amplify.Auth.signOut()
            if let globalResult = result as? AWSCognitoSignOutResult,
               case .failed = globalResult {
                Log.auth.error("Sign-out after account deletion failed")
            }
            await MainActor.run {
                profileViewModel.reset()
                savedVenuesVM.reset()
                authState.didSignOut()
            }
        } catch {
            Log.auth.error("Account deletion failed: \(error.localizedDescription)")
            showDeleteError = true
        }
    }
}
