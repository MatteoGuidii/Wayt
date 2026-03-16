import SwiftUI

// MARK: - Venuu Design System

enum VenuuTheme {

    // MARK: - Brand Colors

    /// Copper Ember — primary accent for buttons, CTAs, icons, highlights
    static let amber = Color(red: 0.78, green: 0.49, blue: 0.29)   // #C67D4B

    /// Maps blue — used for map controls (Apple Maps style)
    static let mapsBlue = Color(red: 0.00, green: 0.48, blue: 1.00) // #007AFF

    // MARK: - Backgrounds

    /// Warm gradient for auth/onboarding screens
    static let backgroundGradient = LinearGradient(
        colors: [
            Color(red: 0.99, green: 0.96, blue: 0.94),  // warm cream
            Color(red: 0.98, green: 0.94, blue: 0.91),  // soft copper tint
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let cardBackground = Color(UIColor.systemBackground)

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
