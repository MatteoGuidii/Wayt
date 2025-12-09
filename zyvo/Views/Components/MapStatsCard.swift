import SwiftUI

/// A floating stats card showing venue count and discovery stats
struct MapStatsCard: View {
    let totalVenues: Int
    let filteredVenues: Int
    let isFiltering: Bool

    @State private var appeared = false

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue.opacity(0.8), .purple.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)

                Image(systemName: "mappin.and.ellipse")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                if isFiltering {
                    HStack(spacing: 4) {
                        Text("\(filteredVenues)")
                            .font(.headline.weight(.bold))
                        Text("of")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(totalVenues)")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("\(totalVenues)")
                        .font(.headline.weight(.bold))
                }

                Text(isFiltering ? "filtered venues" : "venues nearby")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        .scaleEffect(appeared ? 1 : 0.8)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7).delay(0.2)) {
                appeared = true
            }
        }
    }
}
