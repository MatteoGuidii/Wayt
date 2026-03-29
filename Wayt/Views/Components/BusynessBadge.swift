import SwiftUI

/// Compact badge showing busyness level with color + label.
struct BusynessBadge: View {

    let level: BusynessLevel?
    let confidence: BusynessConfidence
    var style: BadgeStyle = .standard
    var isOpen: Bool? = nil

    @State private var isPulsing = false

    var body: some View {
        if isOpen == false {
            HStack(spacing: 4) {
                Circle()
                    .fill(Color.red)
                    .frame(width: dotSize, height: dotSize)
                Text("Closed")
                    .font(style == .compact ? WaytTheme.badgeFont : WaytTheme.footnoteLightFont)
                    .fontWeight(.semibold)
                    .foregroundStyle(.red)
            }
            .padding(.horizontal, style == .compact ? 6 : 8)
            .padding(.vertical, style == .compact ? 3 : 5)
            .background(Color.red.opacity(0.12))
            .clipShape(Capsule())
        } else if let level {
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
                    .font(style == .compact ? WaytTheme.badgeFont : .system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(level.color)

                if style == .standard, confidence != .none {
                    if confidence == .veryHigh {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(WaytTheme.busynessColor(for: 2))
                    }
                    Text("• \(confidence.label)")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(confidenceColor)
                }
            }
            .padding(.horizontal, style == .compact ? 6 : 8)
            .padding(.vertical, style == .compact ? 3 : 5)
            .background(level.color.opacity(0.12))
            .clipShape(Capsule())
        } else {
            Text("No data")
                .font(WaytTheme.badgeFont)
                .foregroundStyle(WaytTheme.secondaryText)
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
        WaytTheme.secondaryText
    }

    enum BadgeStyle {
        case standard
        case compact
    }
}
