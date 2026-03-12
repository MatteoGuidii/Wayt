import SwiftUI

struct ProfileScreen: View {

    let username: String
    let onSignOut: () -> Void

    @StateObject private var viewModel: ProfileViewModel

    init(username: String, onSignOut: @escaping () -> Void) {
        self.username = username
        self.onSignOut = onSignOut
        _viewModel = StateObject(wrappedValue: ProfileViewModel(
            username: username,
            onSignOut: onSignOut
        ))
    }

    var body: some View {
        NavigationStack {
            List {
                // User info section
                Section {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(VenuuTheme.primaryPurple.opacity(0.15))
                                .frame(width: 56, height: 56)

                            Text(initials)
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(VenuuTheme.primaryPurple)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(viewModel.username)
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

                // Stats section
                Section("Activity") {
                    HStack {
                        Label("Reports Submitted", systemImage: "megaphone.fill")
                        Spacer()
                        Text("\(viewModel.totalReports)")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(VenuuTheme.primaryPurple)
                    }
                }

                // About section
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
                        viewModel.signOut()
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
        .task { await viewModel.loadProfile() }
    }

    // MARK: - Helpers

    private var initials: String {
        let parts = username.split(separator: " ")
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        }
        return String(username.prefix(2)).uppercased()
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}
