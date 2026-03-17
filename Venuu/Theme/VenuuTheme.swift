import SwiftUI
import UIKit

// MARK: - Venuu Design System

enum VenuuTheme {

    // MARK: - Brand Colors

    /// Sky Punch — primary accent for buttons, CTAs, icons, highlights
    static let skyPunch = Color(red: 0.00, green: 0.70, blue: 0.95)   // #00B3F2

    /// Ultra Blue — gradient accent for mascot pin body
    static let ultraBlue = Color(red: 0.20, green: 0.20, blue: 1.00)   // #3333FF

    /// Maps blue — used for map controls (Apple Maps style)
    static let mapsBlue = Color(red: 0.00, green: 0.48, blue: 1.00) // #007AFF

    /// Dark ink — mascot face features (eyes, mouth)
    static let ink = Color(red: 0.25, green: 0.20, blue: 0.35)   // #403357

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

    // MARK: - Typography (Playful Rounded System)
    //
    // Every text element uses SF Rounded for the bold, playful Venuu personality.
    // Use these tokens instead of inline .font(.system(...)) calls.

    /// 32pt bold — brand display ("Venuu" logotype)
    static let displayFont     = Font.system(size: 32, weight: .bold, design: .rounded)

    /// 28pt bold — onboarding headlines
    static let heroFont        = Font.system(size: 28, weight: .bold, design: .rounded)

    /// 26pt black — screen titles, greetings
    static let largeTitleFont  = Font.system(size: 26, weight: .black, design: .rounded)

    /// 24pt bold — large numeric displays
    static let titleNumericFont = Font.system(size: 24, weight: .bold, design: .rounded)

    /// 22pt bold — large icons paired with text
    static let iconLargeFont   = Font.system(size: 22, weight: .bold, design: .rounded)

    /// 20pt bold — venue detail headlines, section titles
    static let headlineFont    = Font.system(size: 20, weight: .bold, design: .rounded)

    /// 18pt bold — medium headlines, auth titles, CTA buttons
    static let title3Font      = Font.system(size: 18, weight: .bold, design: .rounded)

    /// 17pt bold — prominent inline labels
    static let calloutBoldFont = Font.system(size: 17, weight: .bold, design: .rounded)

    /// 16pt black — section labels ("Area Vibe", "Go Now", "All Spots")
    static let sectionFont     = Font.system(size: 16, weight: .black, design: .rounded)

    /// 16pt bold — button text, emphasized body
    static let bodyBoldFont    = Font.system(size: 16, weight: .bold, design: .rounded)

    /// 16pt medium — standard body text
    static let bodyFont        = Font.system(size: 16, weight: .medium, design: .rounded)

    /// 15pt bold — card titles, venue names in lists
    static let cardTitleFont   = Font.system(size: 15, weight: .bold, design: .rounded)

    /// 15pt semibold — subtitle, secondary descriptions
    static let subtitleFont    = Font.system(size: 15, weight: .semibold, design: .rounded)

    /// 14pt bold — category labels, sub-card titles
    static let subheadFont     = Font.system(size: 14, weight: .bold, design: .rounded)

    /// 14pt semibold — secondary info
    static let subheadLightFont = Font.system(size: 14, weight: .semibold, design: .rounded)

    /// 13pt bold — counts, emphasized meta
    static let footnoteFont    = Font.system(size: 13, weight: .bold, design: .rounded)

    /// 13pt semibold — descriptions, lighter meta
    static let footnoteLightFont = Font.system(size: 13, weight: .semibold, design: .rounded)

    /// 12pt bold — chips, filter labels
    static let captionFont     = Font.system(size: 12, weight: .bold, design: .rounded)

    /// 12pt semibold — lighter captions, distances
    static let captionLightFont = Font.system(size: 12, weight: .semibold, design: .rounded)

    /// 11pt bold — badges, tiny counts
    static let badgeFont       = Font.system(size: 11, weight: .bold, design: .rounded)

    /// 10pt bold — micro labels
    static let microFont       = Font.system(size: 10, weight: .bold, design: .rounded)

    /// 9pt bold — bar chart labels, uppercase tags
    static let nanoFont        = Font.system(size: 9, weight: .bold, design: .rounded)

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
