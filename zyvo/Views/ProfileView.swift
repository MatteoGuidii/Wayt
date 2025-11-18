//
//  ProfileView.swift
//  zyvo
//
//  Created by Claude Code
//

import SwiftUI

struct ProfileView: View {
    let username: String
    let onSignOut: () -> Void

    var body: some View {
        ZStack {
            // Purple-blue gradient background
            LinearGradient(
                colors: [
                    Color.purple.opacity(0.3),
                    Color.blue.opacity(0.4)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    // Header with close button
                    header

                    // Profile card
                    profileCard

                    // Stats
                    statsCard

                    // Activity section
                    activitySection

                    // Settings section
                    settingsSection

                    // Sign out button
                    signOutButton

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
        }
    }
}

// MARK: - Components
private extension ProfileView {
    var header: some View {
        HStack {
            Text("Profile")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Spacer()
        }
        .padding(.vertical, 8)
    }

    var profileCard: some View {
        VStack(spacing: 16) {
            // Avatar
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.purple, Color.blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)

                Text(username.prefix(2).uppercased())
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }

            // Username
            Text(username)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)

            Text("Nightlife Explorer")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 8)
    }

    var statsCard: some View {
        HStack(spacing: 0) {
            StatItem(value: "42", label: "Venues")

            Divider()
                .frame(height: 40)
                .overlay(.white.opacity(0.3))

            StatItem(value: "18", label: "Check-ins")

            Divider()
                .frame(height: 40)
                .overlay(.white.opacity(0.3))

            StatItem(value: "127", label: "Reviews")
        }
        .padding(.vertical, 20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 8)
    }

    var activitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Activity")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 4)

            VStack(spacing: 12) {
                ActivityRow(
                    icon: "music.note",
                    title: "Reviewed The Blue Note",
                    subtitle: "Great vibe, packed crowd",
                    time: "2h ago"
                )

                ActivityRow(
                    icon: "mappin.circle.fill",
                    title: "Checked in at Skybar",
                    subtitle: "Amazing rooftop views",
                    time: "1d ago"
                )

                ActivityRow(
                    icon: "star.fill",
                    title: "Rated The Underground",
                    subtitle: "5 stars",
                    time: "3d ago"
                )
            }
        }
    }

    var settingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 4)

            VStack(spacing: 12) {
                SettingsRow(icon: "bell.fill", title: "Notifications")
                SettingsRow(icon: "lock.fill", title: "Privacy")
                SettingsRow(icon: "heart.fill", title: "Favorites")
                SettingsRow(icon: "person.2.fill", title: "Friends")
            }
        }
    }

    var signOutButton: some View {
        Button(action: onSignOut) {
            HStack {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.body.weight(.semibold))

                Text("Sign Out")
                    .font(.body.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(.red.opacity(0.7), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .red.opacity(0.3), radius: 8, x: 0, y: 4)
        }
        .padding(.top, 8)
    }
}

// MARK: - Subviews
private struct StatItem: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title.weight(.bold))
                .foregroundStyle(.white)

            Text(label)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ActivityRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let time: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.15))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }

            Spacer()

            Text(time)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct SettingsRow: View {
    let icon: String
    let title: String

    var body: some View {
        Button(action: {}) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 32)

                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

#Preview {
    ProfileView(username: "matteo@example.com", onSignOut: {})
}
