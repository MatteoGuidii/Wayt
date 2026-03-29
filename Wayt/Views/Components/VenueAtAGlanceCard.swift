import SwiftUI

/// Inline metadata row: rating + reviews + price — Google Maps style.
struct VenueAtAGlanceCard: View {

    let rating: Double?
    let userRatingCount: Int?
    let priceLevel: String?
    let priceRange: String?
    var onReviewsTapped: (() -> Void)?

    var body: some View {
        HStack(spacing: 6) {
            // Rating + stars + review count (tappable)
            if let rating {
                HStack(spacing: 4) {
                    Text(String(format: "%.1f", rating))
                        .font(WaytTheme.bodyBoldFont)
                        .foregroundStyle(WaytTheme.primaryText)

                    compactStars(rating: rating)
                }

                if let count = userRatingCount, count > 0 {
                    Button {
                        onReviewsTapped?()
                    } label: {
                        Text("(\(formatCount(count)))")
                            .font(WaytTheme.captionFont)
                            .foregroundStyle(WaytTheme.mapsBlue)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Price
            if let price = PriceLevel.format(priceLevel, priceRange: priceRange) {
                if rating != nil {
                    Text("·")
                        .font(WaytTheme.captionFont)
                        .foregroundStyle(WaytTheme.secondaryText)
                }

                Text(price)
                    .font(WaytTheme.bodyBoldFont)
                    .foregroundStyle(WaytTheme.secondaryText)
            }

            Spacer()
        }
    }

    // MARK: - Helpers

    private func compactStars(rating: Double) -> some View {
        HStack(spacing: 1) {
            ForEach(1...5, id: \.self) { i in
                let iconName = starIcon(for: i, rating: rating)
                Image(systemName: iconName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(iconName == "star" ? Color.gray.opacity(0.3) : .orange)
            }
        }
    }

    private func starIcon(for position: Int, rating: Double) -> String {
        let value = Double(position)
        if value <= rating {
            return "star.fill"
        } else if value - 0.5 <= rating {
            return "star.leadinghalf.filled"
        }
        return "star"
    }

    private func formatCount(_ count: Int) -> String {
        if count >= 1000 {
            return String(format: "%.1fk", Double(count) / 1000.0)
        }
        return "\(count)"
    }
}
