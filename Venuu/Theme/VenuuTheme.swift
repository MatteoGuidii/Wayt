import SwiftUI
import UIKit

// MARK: - Venuu Design System

enum VenuuTheme {

    // MARK: - Dark Mode Helper

    /// Returns an adaptive Color that resolves to `light` or `dark` based on the current appearance.
    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

    // MARK: - Brand Colors

    /// Sky Punch — primary accent for buttons, CTAs, icons, highlights
    static let skyPunch = adaptive(
        light: UIColor(red: 0.00, green: 0.70, blue: 0.95, alpha: 1),  // #00B3F2
        dark:  UIColor(red: 0.22, green: 0.48, blue: 0.65, alpha: 1)   // muted sky blue, easier on eyes
    )

    /// Ultra Blue — gradient accent for mascot pin body
    static let ultraBlue = adaptive(
        light: UIColor(red: 0.20, green: 0.20, blue: 1.00, alpha: 1),  // #3333FF
        dark:  UIColor(red: 0.18, green: 0.18, blue: 0.45, alpha: 1)   // muted indigo
    )

    /// Maps blue — used for map controls (Apple Maps style)
    static let mapsBlue = adaptive(
        light: UIColor(red: 0.00, green: 0.48, blue: 1.00, alpha: 1),  // #007AFF
        dark:  UIColor(red: 0.25, green: 0.48, blue: 0.72, alpha: 1)   // softer maps blue
    )

    /// Dark ink — mascot face features (eyes, mouth); same in both modes so face is always visible
    static let ink = adaptive(
        light: UIColor(red: 0.25, green: 0.20, blue: 0.35, alpha: 1),  // #403357
        dark:  UIColor(red: 0.25, green: 0.20, blue: 0.35, alpha: 1)   // same — stays dark on white face
    )

    /// Mascot outline strokes — black in both modes to preserve mascot identity
    static let mascotOutline = adaptive(
        light: .black,
        dark:  .black
    )

    /// Mascot face oval fill — white in both modes (mascot identity)
    static let mascotFace = adaptive(
        light: UIColor(white: 1.0, alpha: 0.95),
        dark:  UIColor(white: 1.0, alpha: 0.95)
    )

    /// Saved/bookmark accent — matches busyness "Busy" orange
    static let savedOrange = Color(red: 0.95, green: 0.50, blue: 0.15) // #F28026

    // MARK: - Text Colors

    /// Primary text — pure black in light, softened white in dark to reduce glare
    static let primaryText = adaptive(
        light: UIColor.label,
        dark:  UIColor(white: 0.80, alpha: 1)
    )

    /// Accessible secondary text — darker than .secondary for better readability
    static let secondaryText = adaptive(
        light: UIColor(white: 0, alpha: 0.72),
        dark:  UIColor(white: 0.88, alpha: 0.60)
    )

    // MARK: - Backgrounds

    /// Cool ice-blue gradient for auth/onboarding screens; deep navy with subtle blue in dark mode
    static let backgroundGradient = LinearGradient(
        colors: [
            adaptive(
                light: UIColor(red: 0.93, green: 0.97, blue: 0.99, alpha: 1),  // icy white #EEF7FC
                dark:  UIColor(red: 0.075, green: 0.082, blue: 0.12, alpha: 1) // deep navy with blue tint
            ),
            adaptive(
                light: UIColor(red: 0.88, green: 0.94, blue: 0.98, alpha: 1),  // faint sky #E0F0FA
                dark:  UIColor(red: 0.055, green: 0.058, blue: 0.082, alpha: 1) // deep dark blue-black
            ),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let cardBackground = adaptive(
        light: .systemBackground,
        dark:  UIColor(red: 0.10, green: 0.105, blue: 0.14, alpha: 1)  // subtle navy, blends with background
    )

    /// Adaptive shadow for cards — subtle in light, stronger in dark
    static let cardShadow = adaptive(
        light: UIColor(red: 0, green: 0, blue: 0, alpha: 0.08),
        dark:  UIColor(red: 0, green: 0, blue: 0, alpha: 0.35)
    )

    /// Signal pulse banner base color
    static let signalPulseBase = adaptive(
        light: UIColor(red: 0.06, green: 0.06, blue: 0.12, alpha: 1),
        dark:  UIColor(red: 0.10, green: 0.10, blue: 0.16, alpha: 1)
    )

    /// Avatar outer ring
    static let avatarRing = adaptive(
        light: UIColor(red: 0.93, green: 0.97, blue: 0.99, alpha: 1),
        dark:  UIColor(red: 0.18, green: 0.19, blue: 0.24, alpha: 1)
    )

    /// Avatar inner circle / camera badge background
    static let avatarBackground = adaptive(
        light: .white,
        dark:  UIColor(red: 0.15, green: 0.16, blue: 0.20, alpha: 1)
    )

    /// Auth field background
    static let fieldBackground = adaptive(
        light: UIColor(red: 1, green: 1, blue: 1, alpha: 0.92),
        dark:  UIColor(red: 0.18, green: 0.18, blue: 0.22, alpha: 0.92)
    )

    // MARK: - Busyness Colors (green → red spectrum)

    static func busynessColor(for level: Int) -> Color {
        switch level {
        case 1: return Color(red: 0.55, green: 0.80, blue: 0.25) // lime #8CD13B
        case 2: return Color(red: 42/255.0, green: 157/255.0, blue: 92/255.0) // green #2A9D5C
        case 3: return Color(red: 0.95, green: 0.75, blue: 0.10) // yellow #F2C01A
        case 4: return Color(red: 0.95, green: 0.50, blue: 0.15) // orange #F28026
        case 5: return Color(red: 0.90, green: 0.22, blue: 0.20) // red #E63A38
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

    /// 14pt semibold — descriptions, lighter meta
    static let footnoteLightFont = Font.system(size: 14, weight: .semibold, design: .rounded)

    /// 13pt bold — chips, filter labels
    static let captionFont     = Font.system(size: 13, weight: .bold, design: .rounded)

    /// 13pt semibold — lighter captions, distances
    static let captionLightFont = Font.system(size: 13, weight: .semibold, design: .rounded)

    /// 12pt bold — badges, tiny counts
    static let badgeFont       = Font.system(size: 12, weight: .bold, design: .rounded)

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
            .shadow(color: VenuuTheme.cardShadow, radius: 8, x: 0, y: 4)
    }
}

extension View {
    func venuuCard() -> some View {
        modifier(VenuuCardModifier())
    }

    /// Replaces generic black shadow with a busyness-colored glow.
    /// Reduced intensity so colored cards blend with dark backgrounds.
    func busynessGlow(_ color: Color?, radius: CGFloat = 10, y: CGFloat = 5) -> some View {
        self.shadow(
            color: (color ?? .gray).opacity(0.10),
            radius: radius,
            x: 0,
            y: y
        )
    }
}

// MARK: - Pin Shape (Venuu brand icon container)

/// Teardrop / map-pin silhouette — rounded top half tapering to a point.
/// Shared brand shape echoing the Venuu mascot.
struct PinShape: Shape {
    func path(in rect: CGRect) -> Path {
        let headRadius = rect.width / 2
        let headCenter = CGPoint(x: rect.midX, y: rect.minY + headRadius)
        let tailAngle: CGFloat = .pi / 5

        let leftTangent = CGPoint(
            x: headCenter.x - headRadius * sin(tailAngle),
            y: headCenter.y + headRadius * cos(tailAngle)
        )
        let rightTangent = CGPoint(
            x: headCenter.x + headRadius * sin(tailAngle),
            y: headCenter.y + headRadius * cos(tailAngle)
        )

        let tip = CGPoint(x: rect.midX, y: rect.maxY)
        let curveStrength: CGFloat = 0.12
        let leftControl = CGPoint(
            x: leftTangent.x - rect.width * curveStrength,
            y: (leftTangent.y + rect.maxY) / 2
        )
        let rightControl = CGPoint(
            x: rightTangent.x + rect.width * curveStrength,
            y: (rightTangent.y + rect.maxY) / 2
        )

        var path = Path()
        path.move(to: leftTangent)
        path.addArc(
            center: headCenter,
            radius: headRadius,
            startAngle: Angle(radians: .pi / 2 + tailAngle),
            endAngle: Angle(radians: .pi / 2 - tailAngle),
            clockwise: true
        )
        path.addQuadCurve(to: tip, control: rightControl)
        path.addQuadCurve(to: leftTangent, control: leftControl)
        path.closeSubpath()
        return path
    }
}
