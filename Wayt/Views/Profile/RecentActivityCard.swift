import SwiftUI

struct RecentActivityCard: View {

    let entries: [ReportHistoryEntry]
    var onTapVenue: ((ReportHistoryEntry) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(WaytTheme.mapsBlue)
                Text("Recent Activity")
                    .font(WaytTheme.bodyBoldFont)
                Spacer()
            }

            if entries.isEmpty {
                // Empty state
                VStack(spacing: 8) {
                    Image(systemName: "megaphone")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(WaytTheme.secondaryText)
                    Text("Your reports will appear here")
                        .font(WaytTheme.footnoteLightFont)
                        .foregroundStyle(WaytTheme.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else {
                let visible = Array(entries.prefix(5))
                VStack(spacing: 0) {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, entry in
                        activityRow(entry)

                        if index < visible.count - 1 {
                            Divider()
                                .padding(.leading, 24)
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

    private func activityRow(_ entry: ReportHistoryEntry) -> some View {
        Button {
            onTapVenue?(entry)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: entry.category.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WaytTheme.mapsBlue)
                    .frame(width: 20)

                Text(entry.venueName)
                    .font(WaytTheme.subheadFont)
                    .foregroundStyle(WaytTheme.primaryText)
                    .lineLimit(1)

                Spacer()

                Text(entry.relativeTime)
                    .font(WaytTheme.captionLightFont)
                    .foregroundStyle(WaytTheme.secondaryText)

                if onTapVenue != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(WaytTheme.secondaryText)
                }
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}
