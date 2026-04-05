import SwiftUI

struct StatsCard: View {

    let reportsThisWeek: Int
    let reportsThisMonth: Int
    let totalReports: Int
    let categoryBreakdown: [(category: VenueCategory, count: Int)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(WaytTheme.mapsBlue)
                Text("Your Stats")
                    .font(WaytTheme.bodyBoldFont)
                Spacer()
            }

            HStack(spacing: 0) {
                statColumn(value: reportsThisWeek, label: "This Week")
                Divider().frame(height: 36)
                statColumn(value: reportsThisMonth, label: "This Month")
                Divider().frame(height: 36)
                statColumn(value: totalReports, label: "All Time")
            }

            if !categoryBreakdown.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Categories")
                        .font(WaytTheme.captionFont)
                        .foregroundStyle(WaytTheme.secondaryText)

                    let maxCount = categoryBreakdown.first?.count ?? 1
                    ForEach(categoryBreakdown.prefix(4), id: \.category) { item in
                        HStack(spacing: 10) {
                            Image(systemName: item.category.icon)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(WaytTheme.mapsBlue)
                                .frame(width: 18)

                            Text(item.category.displayName)
                                .font(WaytTheme.captionLightFont)
                                .frame(width: 70, alignment: .leading)

                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(WaytTheme.mapsBlue.opacity(0.2))
                                    .frame(width: geo.size.width)
                                    .overlay(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                                            .fill(WaytTheme.mapsBlue)
                                            .frame(width: max(4, geo.size.width * CGFloat(item.count) / CGFloat(maxCount)))
                                    }
                            }
                            .frame(height: 8)

                            Text("\(item.count)")
                                .font(WaytTheme.captionFont)
                                .foregroundStyle(WaytTheme.secondaryText)
                                .frame(width: 28, alignment: .trailing)
                        }
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

    private func statColumn(value: Int, label: String) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(WaytTheme.primaryText)
            Text(label)
                .font(WaytTheme.captionLightFont)
                .foregroundStyle(WaytTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }
}
