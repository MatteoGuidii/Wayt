import SwiftUI

struct BadgesCard: View {

    let earnedBadges: [Badge]

    @State private var selectedBadge: Badge?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "medal.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(WaytTheme.rankGold)
                Text("Badges")
                    .font(WaytTheme.bodyBoldFont)

                Spacer()

                Text("\(earnedBadges.count)/\(Badge.allCases.count)")
                    .font(WaytTheme.captionFont)
                    .foregroundStyle(WaytTheme.secondaryText)
            }

            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(Badge.allCases) { badge in
                    let isEarned = earnedBadges.contains(badge)
                    Button { selectedBadge = badge } label: {
                        badgeCell(badge: badge, isEarned: isEarned)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(WaytTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: WaytTheme.cardShadow, radius: 6, x: 0, y: 3)
        .padding(.horizontal, 16)
        .alert(item: $selectedBadge) { badge in
            let isEarned = earnedBadges.contains(badge)
            return Alert(
                title: Text(badge.rawValue),
                message: Text(isEarned ? "Earned!" : badge.subtitle),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private func badgeCell(badge: Badge, isEarned: Bool) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(isEarned ? WaytTheme.rankGold.opacity(0.15) : Color(.systemGray6))
                    .frame(width: 48, height: 48)
                Image(systemName: badge.icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(isEarned ? WaytTheme.rankGold : Color(.systemGray4))
            }

            Text(badge.rawValue)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(isEarned ? WaytTheme.primaryText : WaytTheme.secondaryText)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 24)
        }
    }
}
