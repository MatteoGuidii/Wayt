import SwiftUI

// MARK: - "Vee" — Venuu's Mascot

/// A friendly map-pin character drawn entirely with SwiftUI shapes.
/// The body is a single teardrop/pin silhouette — rounded top, pointed tail.
/// Use `expression` to switch faces for different onboarding pages.
struct VenuuMascot: View {

    enum Expression {
        case happy      // default smile
        case excited    // wide eyes, open mouth
        case wink       // one eye closed
        case looking    // eyes shifted to one side
    }

    var size: CGFloat = 160
    var expression: Expression = .happy
    var animated: Bool = true

    @State private var pulseScale: CGFloat = 1.0
    @State private var floatOffset: CGFloat = 0

    private var pinColor: Color { VenuuTheme.amber }
    private var accentColor: Color { Color(red: 0.04, green: 0.62, blue: 0.42) }  // deeper green for gradient

    var body: some View {
        ZStack {
            // Soft glow behind the mascot
            Circle()
                .fill(
                    RadialGradient(
                        colors: [pinColor.opacity(0.25), .clear],
                        center: .center,
                        startRadius: size * 0.1,
                        endRadius: size * 0.7
                    )
                )
                .frame(width: size * 1.4, height: size * 1.4)
                .scaleEffect(pulseScale)
                .offset(y: -size * 0.1)

            // The pin body
            pinBody
                .offset(y: floatOffset)
        }
        .frame(width: size * 1.5, height: size * 1.8)
        .onAppear {
            guard animated else { return }
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                pulseScale = 1.12
            }
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                floatOffset = -6
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

            // Outer pin shape (gradient fill)
            PinShape()
                .fill(
                    LinearGradient(
                        colors: [pinColor, accentColor],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size * 0.72, height: size * 1.05)
                .shadow(color: pinColor.opacity(0.35), radius: 12, y: 6)

            // Inner white face area
            Circle()
                .fill(Color.white.opacity(0.95))
                .frame(width: size * 0.50, height: size * 0.50)
                .offset(y: -size * 0.12)

            // Face
            faceView
                .offset(y: -size * 0.12)
        }
    }

    // MARK: - Face

    private var faceView: some View {
        VStack(spacing: size * 0.02) {
            // Eyes
            HStack(spacing: size * 0.10) {
                eyeView(isWinking: expression == .wink)
                eyeView(isWinking: false)
            }
            .offset(x: expression == .looking ? size * 0.03 : 0)

            // Mouth
            mouthView
                .offset(y: size * 0.01)
        }
        .offset(y: -size * 0.02)
    }

    private func eyeView(isWinking: Bool) -> some View {
        ZStack {
            if isWinking {
                WinkShape()
                    .stroke(Color(red: 0.25, green: 0.20, blue: 0.35), lineWidth: 2.5)
                    .frame(width: size * 0.08, height: size * 0.04)
            } else {
                // Eye white
                Ellipse()
                    .fill(Color.white)
                    .frame(
                        width: size * (expression == .excited ? 0.11 : 0.09),
                        height: size * (expression == .excited ? 0.13 : 0.11)
                    )

                // Pupil
                Circle()
                    .fill(Color(red: 0.25, green: 0.20, blue: 0.35))
                    .frame(width: size * 0.055, height: size * 0.055)
                    .offset(x: expression == .looking ? size * 0.02 : 0)

                // Eye shine
                Circle()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: size * 0.02, height: size * 0.02)
                    .offset(x: -size * 0.012, y: -size * 0.018)
            }
        }
    }

    private var mouthView: some View {
        Group {
            switch expression {
            case .happy, .wink, .looking:
                SmileShape()
                    .stroke(
                        Color(red: 0.25, green: 0.20, blue: 0.35),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                    )
                    .frame(width: size * 0.12, height: size * 0.06)
            case .excited:
                Ellipse()
                    .fill(Color(red: 0.25, green: 0.20, blue: 0.35))
                    .frame(width: size * 0.08, height: size * 0.06)
            }
        }
    }
}

// MARK: - Pin Silhouette Shape

/// A single continuous teardrop / map-pin path:
/// rounded top half (circular arc) tapering smoothly into a pointed bottom.
private struct PinShape: Shape {
    func path(in rect: CGRect) -> Path {
        // The head circle sits in the upper portion of the rect.
        // The tail tapers from the circle edges down to a point at the bottom.
        let headRadius = rect.width / 2
        let headCenter = CGPoint(x: rect.midX, y: rect.minY + headRadius)

        // Where the tangent lines leave the circle to form the tail.
        // Using an angle from vertical — wider angle = wider tail base.
        let tailAngle: CGFloat = .pi / 5  // 36° from vertical

        // Tangent points on the circle
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

        // Control points for the curved tail sides (slight outward bow)
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

        // Start at the left tangent point
        path.move(to: leftTangent)

        // Arc over the head (going clockwise from left tangent → top → right tangent)
        let startAngle = Angle(radians: .pi / 2 + tailAngle)
        let endAngle = Angle(radians: .pi / 2 - tailAngle)
        path.addArc(
            center: headCenter,
            radius: headRadius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: true
        )

        // Curved right side of tail → tip
        path.addQuadCurve(to: tip, control: rightControl)

        // Curved left side of tail → back to start
        path.addQuadCurve(to: leftTangent, control: leftControl)

        path.closeSubpath()
        return path
    }
}

// MARK: - Face Shapes

private struct SmileShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.midX, y: rect.maxY + rect.height * 0.3)
        )
        return path
    }
}

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
