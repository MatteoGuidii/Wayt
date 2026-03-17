import SwiftUI

// MARK: - "Vee" — Venuu's Mascot

/// A friendly map-pin character drawn entirely with SwiftUI shapes.
/// Oval face, half-moon anime eyes, cat-like mouth, and a small antenna.
/// Use `expression` to switch faces for different onboarding pages.
struct VenuuMascot: View {

    enum Expression {
        case happy      // default cat smile
        case excited    // wide half-moons, open "D" mouth
        case wink       // one eye closed
        case looking    // eyes shifted to one side
        case proud      // closed-eye content smile (^ ^)
        case cheerful   // big open smile, half-moon happy eyes (:D)
        case kind       // soft eyes with warm wide smile
    }

    var size: CGFloat = 160
    var expression: Expression = .looking
    var animated: Bool = true

    @State private var pulseScale: CGFloat = 1.0
    @State private var floatOffset: CGFloat = 0
    @State private var antennaWobble: Double = 0

    private var pinColor: Color { VenuuTheme.skyPunch }
    private var accentColor: Color { VenuuTheme.ultraBlue }

    var body: some View {
        ZStack {
            // Soft glow behind the mascot
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [pinColor.opacity(0.25), .clear],
                        center: .center,
                        startRadius: size * 0.1,
                        endRadius: size * 0.7
                    )
                )
                .frame(width: size * 1.4, height: size * 1.2)
                .scaleEffect(pulseScale)
                .offset(y: -size * 0.1)

            // The pin body
            pinBody
                .offset(y: floatOffset)
        }
        .frame(width: size * 1.5, height: size * 1.9)
        .onAppear {
            guard animated else { return }
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                pulseScale = 1.12
            }
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                floatOffset = -6
            }
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                antennaWobble = 8
            }
        }
    }

    // MARK: - Pin Body

    private var pinBody: some View {
        ZStack {
            // Ground shadow
            Ellipse()
                .fill(Color.black.opacity(0.10))
                .frame(width: size * 0.40, height: size * 0.08)
                .offset(y: size * 0.72)
                .blur(radius: 5)

            // Outer pin shape (gradient fill + black border)
            PinShape()
                .fill(
                    LinearGradient(
                        colors: [pinColor, accentColor],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    PinShape()
                        .stroke(Color.black, lineWidth: 2.5)
                )
                .frame(width: size * 0.72, height: size * 1.05)
                .shadow(color: pinColor.opacity(0.35), radius: 12, y: 6)

            // Antenna
            antennaView
                .offset(y: -size * 0.48)

            // Inner oval face area (slightly squished)
            Ellipse()
                .fill(Color.white.opacity(0.95))
                .overlay(
                    Ellipse()
                        .stroke(Color.black, lineWidth: 2.0)
                )
                .frame(width: size * 0.52, height: size * 0.46)
                .offset(y: -size * 0.12)

            // Face
            faceView
                .offset(y: -size * 0.12)
        }
    }

    // MARK: - Antenna

    private var antennaView: some View {
        VStack(spacing: 0) {
            // Antenna ball
            Circle()
                .fill(pinColor)
                .overlay(
                    Circle()
                        .stroke(Color.black, lineWidth: 2.0)
                )
                .frame(width: size * 0.09, height: size * 0.09)

            // Antenna stick
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.black)
                .frame(width: size * 0.025, height: size * 0.10)
        }
        .rotationEffect(.degrees(antennaWobble), anchor: .bottom)
    }

    // MARK: - Face

    private var faceView: some View {
        VStack(spacing: expression == .proud ? size * 0.04 : size * 0.015) {
            // Eyes
            HStack(spacing: size * 0.10) {
                leftEyeView
                rightEyeView
            }
            .offset(x: expression == .looking ? size * 0.055 : size * 0.035)

            // Mouth — offset right and slightly up-tilted
            mouthView
                .offset(x: expression == .looking ? size * 0.045 : size * 0.025, y: size * 0.005)
                .rotationEffect(.degrees(expression == .looking ? -8 : -4))
        }
        .offset(y: size * 0.01)
    }

    private var leftEyeView: some View {
        ZStack {
            switch expression {
            case .wink:
                // Wink: cheeky curved line
                WinkShape()
                    .stroke(VenuuTheme.ink, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .frame(width: size * 0.07, height: size * 0.035)
                    .rotationEffect(.degrees(-8))
            case .proud:
                // Closed happy arc (^ shape)
                HappyClosedEyeShape()
                    .stroke(VenuuTheme.ink, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .frame(width: size * 0.065, height: size * 0.03)
            case .cheerful:
                // Half-moon happy eye
                HalfMoonEyeShape()
                    .fill(VenuuTheme.ink)
                    .frame(width: size * 0.06, height: size * 0.035)
            case .kind:
                // Soft larger eye with bigger shine
                kindEyeDot
            default:
                roundEyeDot
            }
        }
    }

    private var rightEyeView: some View {
        ZStack {
            switch expression {
            case .proud:
                HappyClosedEyeShape()
                    .stroke(VenuuTheme.ink, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .frame(width: size * 0.065, height: size * 0.03)
            case .cheerful:
                HalfMoonEyeShape()
                    .fill(VenuuTheme.ink)
                    .frame(width: size * 0.06, height: size * 0.035)
            case .kind:
                kindEyeDot
            default:
                roundEyeDot
            }
        }
    }

    /// Standard round eye with shine
    private var roundEyeDot: some View {
        ZStack {
            Circle()
                .fill(VenuuTheme.ink)
                .frame(
                    width: size * (expression == .excited ? 0.065 : 0.055),
                    height: size * (expression == .excited ? 0.065 : 0.055)
                )
                .offset(x: expression == .looking ? size * 0.015 : 0)
            Circle()
                .fill(Color.white.opacity(0.9))
                .frame(width: size * 0.018, height: size * 0.018)
                .offset(x: -size * 0.008, y: -size * 0.01)
        }
    }

    /// Kind expression: slightly larger, softer eye
    private var kindEyeDot: some View {
        ZStack {
            Circle()
                .fill(VenuuTheme.ink)
                .frame(width: size * 0.058, height: size * 0.058)
            Circle()
                .fill(Color.white.opacity(0.9))
                .frame(width: size * 0.022, height: size * 0.022)
                .offset(x: -size * 0.008, y: -size * 0.012)
        }
    }

    private var mouthView: some View {
        Group {
            switch expression {
            case .happy, .looking, .wink:
                // Gentle curved smile / smirk
                SmileShape()
                    .stroke(
                        VenuuTheme.ink,
                        style: StrokeStyle(lineWidth: 2.0, lineCap: .round)
                    )
                    .frame(width: size * 0.11, height: size * 0.045)
            case .excited:
                // Open "D" mouth
                DShapeMouth()
                    .fill(VenuuTheme.ink)
                    .frame(width: size * 0.09, height: size * 0.06)
            case .proud:
                // Content gentle smile — wider and softer
                SmileShape()
                    .stroke(
                        VenuuTheme.ink,
                        style: StrokeStyle(lineWidth: 2.2, lineCap: .round)
                    )
                    .frame(width: size * 0.13, height: size * 0.04)
            case .cheerful:
                // Big open "D" smile
                DShapeMouth()
                    .fill(VenuuTheme.ink)
                    .frame(width: size * 0.11, height: size * 0.07)
            case .kind:
                // Warm wide smile
                SmileShape()
                    .stroke(
                        VenuuTheme.ink,
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                    )
                    .frame(width: size * 0.14, height: size * 0.05)
            }
        }
    }
}

// MARK: - Pin Silhouette Shape

/// A single continuous teardrop / map-pin path:
/// rounded top half (circular arc) tapering smoothly into a pointed bottom.
private struct PinShape: Shape {
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

        let tipY = rect.maxY
        let tip = CGPoint(x: rect.midX, y: tipY)

        let curveStrength: CGFloat = 0.12
        let leftControl = CGPoint(
            x: leftTangent.x - rect.width * curveStrength,
            y: (leftTangent.y + tipY) / 2
        )
        let rightControl = CGPoint(
            x: rightTangent.x + rect.width * curveStrength,
            y: (rightTangent.y + tipY) / 2
        )

        var path = Path()
        path.move(to: leftTangent)
        let startAngle = Angle(radians: .pi / 2 + tailAngle)
        let endAngle = Angle(radians: .pi / 2 - tailAngle)
        path.addArc(
            center: headCenter,
            radius: headRadius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: true
        )
        path.addQuadCurve(to: tip, control: rightControl)
        path.addQuadCurve(to: leftTangent, control: leftControl)
        path.closeSubpath()
        return path
    }
}

// MARK: - Face Shapes

/// Happy closed eye — upward arc like ^ ^
private struct HappyClosedEyeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY),
            control: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.5)
        )
        return path
    }
}

/// Half-moon / anime-style eye — a filled upside-down arc
private struct HalfMoonEyeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY),
            control: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.3)
        )
        path.closeSubpath()
        return path
    }
}

/// Asymmetric smirk — right side lifts higher
private struct SmileShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        // Left side starts lower, right side ends higher = smirk
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.midX + rect.width * 0.1, y: rect.maxY)
        )
        return path
    }
}

/// Wink — a simple curved arc for a closed eye
private struct WinkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.midY),
            control: CGPoint(x: rect.midX, y: rect.maxY)
        )
        return path
    }
}

/// Cat-like :3 mouth — two small bumps side by side
private struct CatMouthShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midX = rect.midX
        let topY = rect.minY + rect.height * 0.3

        // Left bump
        path.move(to: CGPoint(x: rect.minX, y: topY))
        path.addQuadCurve(
            to: CGPoint(x: midX, y: topY),
            control: CGPoint(x: rect.minX + rect.width * 0.25, y: rect.maxY)
        )

        // Right bump
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: topY),
            control: CGPoint(x: midX + rect.width * 0.25, y: rect.maxY)
        )
        return path
    }
}

/// Open "D" shaped mouth for excited expression
private struct DShapeMouth: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.15, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.15, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.15, y: rect.minY),
            control: CGPoint(x: rect.midX, y: rect.maxY + rect.height * 0.2)
        )
        path.closeSubpath()
        return path
    }
}

#Preview("Mascot") {
    ScrollView {
        VStack(spacing: 20) {
            Text("Existing").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 40) {
                VStack {
                    VenuuMascot(size: 90, expression: .looking)
                    Text("looking").font(.caption2)
                }
                VStack {
                    VenuuMascot(size: 90, expression: .excited)
                    Text("excited").font(.caption2)
                }
            }
            HStack(spacing: 40) {
                VStack {
                    VenuuMascot(size: 90, expression: .happy)
                    Text("happy").font(.caption2)
                }
                VStack {
                    VenuuMascot(size: 90, expression: .wink)
                    Text("wink").font(.caption2)
                }
            }

            Divider().padding(.horizontal, 40)

            Text("New — pick for \"Help your community\"").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 30) {
                VStack {
                    VenuuMascot(size: 90, expression: .proud)
                    Text("proud").font(.caption2)
                }
                VStack {
                    VenuuMascot(size: 90, expression: .cheerful)
                    Text("cheerful").font(.caption2)
                }
                VStack {
                    VenuuMascot(size: 90, expression: .kind)
                    Text("kind").font(.caption2)
                }
            }
        }
        .padding()
    }
}
