import SwiftUI

struct LeaderboardCard: View {

    let entries: [LeaderboardEntry]
    let currentUserEntry: CurrentUserEntry?
    let weekLabel: String
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(WaytTheme.rankGold)
                Text("Top Reporters")
                    .font(WaytTheme.bodyBoldFont)

                Spacer()

                Text(weekLabel)
                    .font(WaytTheme.captionFont)
                    .foregroundStyle(WaytTheme.secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(.systemGray6))
                    .clipShape(Capsule())
            }

            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                        .padding(.vertical, 20)
                    Spacer()
                }
            } else if entries.isEmpty {
                emptyState
            } else {
                VStack(spacing: 6) {
                    ForEach(entries.prefix(5)) { entry in
                        leaderboardRow(entry: entry)
                    }

                    if let userEntry = currentUserEntry,
                       !entries.prefix(5).contains(where: { $0.isCurrentUser }) {
                        Divider()
                            .padding(.vertical, 2)

                        HStack(spacing: 10) {
                            Text("#\(userEntry.rank)")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(WaytTheme.mapsBlue)
                                .frame(width: 30, alignment: .center)

                            Text("You")
                                .font(WaytTheme.subheadFont)
                                .foregroundStyle(WaytTheme.mapsBlue)

                            Spacer()

                            Text("\(userEntry.reportCount)")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(WaytTheme.mapsBlue)

                            Image(systemName: "megaphone.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(WaytTheme.mapsBlue.opacity(0.6))
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .background(WaytTheme.mapsBlue.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
        }
        .padding(16)
        .background(WaytTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: WaytTheme.cardShadow, radius: 6, x: 0, y: 3)
        .padding(.horizontal, 16)
    }

    // MARK: - Row

    private func leaderboardRow(entry: LeaderboardEntry) -> some View {
        HStack(spacing: 10) {
            rankBadge(rank: entry.rank)

            Text(entry.isCurrentUser ? "You" : entry.displayName)
                .font(entry.isCurrentUser ? WaytTheme.subheadFont : WaytTheme.subheadLightFont)
                .foregroundStyle(entry.isCurrentUser ? WaytTheme.mapsBlue : WaytTheme.primaryText)
                .lineLimit(1)

            Spacer()

            Text("\(entry.reportCount)")
                .font(.system(size: 14, weight: .bold, design: .rounded))

            Image(systemName: "megaphone.fill")
                .font(.system(size: 10))
                .foregroundStyle(WaytTheme.secondaryText)
        }
        .padding(.vertical, 4)
    }

    private func rankBadge(rank: Int) -> some View {
        let color: Color = switch rank {
        case 1: WaytTheme.rankGold
        case 2: Color(.systemGray3)
        case 3: Color(red: 0.8, green: 0.5, blue: 0.2)
        default: Color(.systemGray5)
        }

        return ZStack {
            Circle()
                .fill(color.opacity(rank <= 3 ? 0.15 : 0.08))
                .frame(width: 28, height: 28)

            Text("\(rank)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(rank <= 3 ? color : WaytTheme.secondaryText)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 20))
                .foregroundStyle(WaytTheme.secondaryText)

            Text("No reports this week yet")
                .font(WaytTheme.subheadLightFont)
                .foregroundStyle(WaytTheme.secondaryText)

            Text("Be the first to report nearby!")
                .font(WaytTheme.captionFont)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}
