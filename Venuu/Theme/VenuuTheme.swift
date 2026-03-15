import SwiftUI

// MARK: - Venuu Design System

enum VenuuTheme {

    // MARK: - Brand Colors

    static let amber = Color(red: 0.855, green: 0.635, blue: 0.235)  // #DAA23C — energy, action, CTAs
    static let steel = Color(red: 0.310, green: 0.325, blue: 0.400)  // #4F5366 — grounding, text, secondary

    // Legacy aliases — keep until full migration, then remove
    static let primaryPurple = amber
    static let primaryBlue   = steel

    // MARK: - Backgrounds

    /// Warm, bright background for auth/onboarding screens
    static let backgroundGradient = LinearGradient(
        colors: [
            Color(red: 0.996, green: 0.957, blue: 0.878),  // warm cream
            Color(red: 0.988, green: 0.925, blue: 0.820),  // soft honey
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let cardBackground = Color(.systemBackground)

    // MARK: - Busyness Colors (green → red spectrum)

    static func busynessColor(for level: Int) -> Color {
        switch level {
        case 1: return Color(red: 0.20, green: 0.78, blue: 0.35) // green
        case 2: return Color(red: 0.55, green: 0.80, blue: 0.25) // lime
        case 3: return Color(red: 0.95, green: 0.75, blue: 0.10) // yellow
        case 4: return Color(red: 0.95, green: 0.50, blue: 0.15) // orange
        case 5: return Color(red: 0.90, green: 0.22, blue: 0.20) // red
        default: return .gray
        }
    }

    // MARK: - Typography

    static let headlineFont = Font.system(size: 20, weight: .semibold, design: .rounded)
    static let bodyFont    = Font.system(size: 16, weight: .regular, design: .default)
    static let captionFont = Font.system(size: 13, weight: .medium, design: .default)
    static let badgeFont   = Font.system(size: 11, weight: .bold, design: .rounded)

    // MARK: - Dimensions

    static let cornerRadius: CGFloat = 14
    static let markerSize: CGFloat = 40
    static let cardPadding: CGFloat = 16
    static let chipHeight: CGFloat = 36
}

// MARK: - View Modifiers

struct VenuuCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(VenuuTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: VenuuTheme.cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
}

extension View {
    func venuuCard() -> some View {
        modifier(VenuuCardModifier())
    }
}
