import SwiftUI

/// Compact badge showing busyness level with color + label.
struct BusynessBadge: View {

    let level: BusynessLevel?
    let confidence: BusynessConfidence
    var style: BadgeStyle = .standard

    var body: some View {
        if let level {
            HStack(spacing: 4) {
                Circle()
                    .fill(level.color)
                    .frame(width: dotSize, height: dotSize)

                Text(level.label)
                    .font(style == .compact ? VenuuTheme.badgeFont : VenuuTheme.captionFont)
                    .fontWeight(.semibold)
                    .foregroundStyle(level.color)

                if style == .standard, confidence != .none {
                    Text("• \(confidence.label)")
                        .font(VenuuTheme.badgeFont)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, style == .compact ? 6 : 8)
            .padding(.vertical, style == .compact ? 3 : 5)
            .background(level.color.opacity(0.12))
            .clipShape(Capsule())
        } else {
            Text("No data")
                .font(VenuuTheme.badgeFont)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.gray.opacity(0.10))
                .clipShape(Capsule())
        }
    }

    private var dotSize: CGFloat {
        style == .compact ? 6 : 8
    }

    enum BadgeStyle {
        case standard
        case compact
    }
}
