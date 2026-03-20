import SwiftUI

/// Compact badge showing busyness level with color + label.
struct BusynessBadge: View {

    let level: BusynessLevel?
    let confidence: BusynessConfidence
    var style: BadgeStyle = .standard

    @State private var isPulsing = false

    var body: some View {
        if let level {
            HStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(level.color.opacity(0.35))
                        .frame(width: dotSize, height: dotSize)
                        .scaleEffect(isPulsing ? 1.6 : 1.0)
                        .animation(
                            .easeInOut(duration: 1.2)
                                .repeatForever(autoreverses: true),
                            value: isPulsing
                        )
                    Circle()
                        .fill(level.color)
                        .frame(width: dotSize, height: dotSize)
                }
                .onAppear { isPulsing = true }

                Text(level.label)
                    .font(style == .compact ? VenuuTheme.badgeFont : VenuuTheme.footnoteLightFont)
                    .fontWeight(.semibold)
                    .foregroundStyle(level.color)

                if style == .standard, confidence != .none {
                    if confidence == .veryHigh {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(VenuuTheme.busynessColor(for: 2))
                    }
                    Text("• \(confidence.label)")
                        .font(VenuuTheme.badgeFont)
                        .foregroundStyle(confidenceColor)
                }
            }
            .padding(.horizontal, style == .compact ? 6 : 8)
            .padding(.vertical, style == .compact ? 3 : 5)
            .background(level.color.opacity(0.12))
            .clipShape(Capsule())
        } else {
            Text("No data")
                .font(VenuuTheme.badgeFont)
                .foregroundStyle(VenuuTheme.secondaryText)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.gray.opacity(0.10))
                .clipShape(Capsule())
        }
    }

    private var dotSize: CGFloat {
        style == .compact ? 6 : 8
    }

    private var confidenceColor: Color {
        switch confidence {
        case .veryHigh, .high: return VenuuTheme.busynessColor(for: 2)  // green
        case .medium:          return VenuuTheme.busynessColor(for: 3)  // yellow
        case .low, .estimated: return VenuuTheme.secondaryText
        case .none:            return VenuuTheme.secondaryText
        }
    }

    enum BadgeStyle {
        case standard
        case compact
    }
}
