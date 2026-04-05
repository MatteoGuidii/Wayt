import SwiftUI

struct ImpactCard: View {

    let totalReports: Int
    let distinctVenues: Int
    let topVenueName: String?
    let topVenueCategory: VenueCategory?
    let confirmationsReceived: Int
    var onTapTopVenue: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "waveform.path")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(WaytTheme.mapsBlue)
                Text("Your Impact")
                    .font(WaytTheme.bodyBoldFont)
                Spacer()
            }

            VStack(spacing: 10) {
                impactRow(
                    icon: "megaphone.fill",
                    color: WaytTheme.mapsBlue,
                    text: "You've shared **\(totalReports)** report\(totalReports == 1 ? "" : "s")"
                )

                if distinctVenues > 0 {
                    impactRow(
                        icon: "map.fill",
                        color: WaytTheme.mapsBlue,
                        text: "Across **\(distinctVenues)** venue\(distinctVenues == 1 ? "" : "s")"
                    )
                }

                if confirmationsReceived > 0 {
                    impactRow(
                        icon: "checkmark.seal.fill",
                        color: .green,
                        text: "**\(confirmationsReceived)** report\(confirmationsReceived == 1 ? "" : "s") confirmed by others"
                    )
                }

                if let topVenue = topVenueName {
                    Button {
                        onTapTopVenue?()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(WaytTheme.rankGold)
                                .frame(width: 20)

                            HStack(spacing: 6) {
                                Text("Most reported:")
                                    .font(WaytTheme.subheadLightFont)
                                    .foregroundStyle(WaytTheme.primaryText)

                                if let category = topVenueCategory {
                                    Image(systemName: category.icon)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(WaytTheme.secondaryText)
                                }

                                Text(topVenue)
                                    .font(WaytTheme.subheadFont)
                                    .foregroundStyle(WaytTheme.primaryText)
                                    .lineLimit(1)
                            }

                            Spacer()

                            if onTapTopVenue != nil {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(WaytTheme.secondaryText)
                            }
                        }
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
    }

    private func impactRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 20)

            Text(.init(text))
                .font(WaytTheme.subheadLightFont)

            Spacer()
        }
    }
}
