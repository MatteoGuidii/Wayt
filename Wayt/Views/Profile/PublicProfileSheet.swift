import SwiftUI

struct PublicProfileSheet: View {

    let userId: String
    let displayName: String

    @State private var profile: PublicProfile?
    @State private var isLoading = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if isLoading {
                        ProgressView()
                            .padding(.top, 60)
                    } else if let profile {
                        profileContent(profile)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
            .scrollIndicators(.hidden)
            .background(WaytTheme.backgroundGradient.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(WaytTheme.mapsBlue)
                            .font(.title3)
                    }
                }
            }
        }
        .task {
            await loadProfile()
        }
    }

    private func profileContent(_ profile: PublicProfile) -> some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                if let imageUrl = profile.profileImageUrl, let url = URL(string: imageUrl) {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        initialsView
                    }
                    .frame(width: 80, height: 80)
                    .clipShape(Circle())
                } else {
                    initialsView
                }

                VStack(spacing: 4) {
                    HStack(spacing: 6) {
                        Text(profile.displayName)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                        Image(systemName: rankIcon(for: profile.rankLevel))
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(rankColor(for: profile.rankLevel))
                    }

                    if let joinedAt = profile.joinedAt {
                        Text("Member since \(formattedDate(joinedAt))")
                            .font(WaytTheme.captionLightFont)
                            .foregroundStyle(WaytTheme.secondaryText)
                    }
                }
            }

            HStack(spacing: 0) {
                VStack(spacing: 4) {
                    Text("\(profile.totalReports)")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                    Text("Reports")
                        .font(WaytTheme.captionLightFont)
                        .foregroundStyle(WaytTheme.secondaryText)
                }
                .frame(maxWidth: .infinity)

                Divider().frame(height: 36)

                VStack(spacing: 4) {
                    Text("Lv.\(profile.rankLevel)")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                    Text("Rank")
                        .font(WaytTheme.captionLightFont)
                        .foregroundStyle(WaytTheme.secondaryText)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(16)
            .background(WaytTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: WaytTheme.cardShadow, radius: 6, x: 0, y: 3)
        }
    }

    private var initialsView: some View {
        Circle()
            .fill(Color(.systemGray5))
            .frame(width: 80, height: 80)
            .overlay {
                Text(String(displayName.prefix(1)).uppercased())
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(WaytTheme.secondaryText)
            }
    }

    private func loadProfile() async {
        defer { isLoading = false }
        do {
            let result: PublicProfile = try await APIClient.shared.get(
                path: "/user/profile/\(userId)/public"
            )
            profile = result
        } catch {
            // Show what we already have from the leaderboard
            profile = PublicProfile(
                userId: userId,
                displayName: displayName,
                totalReports: 0,
                joinedAt: nil,
                profileImageUrl: nil,
                rankLevel: 1
            )
        }
    }

    private func rankIcon(for level: Int) -> String {
        switch level {
        case 1: "leaf.fill"
        case 2: "binoculars.fill"
        case 3: "flag.fill"
        case 4: "star.fill"
        default: "trophy.fill"
        }
    }

    private func rankColor(for level: Int) -> Color {
        switch level {
        case 1: WaytTheme.rankGreen
        case 2: WaytTheme.skyPunch
        case 3: WaytTheme.rankOrange
        case 4: WaytTheme.rankPurple
        default: WaytTheme.rankGold
        }
    }

    private static let isoFormatter = ISO8601DateFormatter()
    private static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM yyyy"
        return f
    }()

    private func formattedDate(_ iso: String) -> String {
        guard let date = Self.isoFormatter.date(from: iso) else { return iso }
        return Self.displayFormatter.string(from: date)
    }
}

struct PublicProfile: Codable, Sendable {
    let userId: String
    let displayName: String
    let totalReports: Int
    let joinedAt: String?
    let profileImageUrl: String?
    let rankLevel: Int
}
