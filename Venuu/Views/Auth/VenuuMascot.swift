import SwiftUI

// MARK: - "Vee" — Venuu's Mascot

/// A friendly map-pin character drawn entirely with SwiftUI shapes.
/// Use `style` to switch between expressions for different onboarding pages.
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

    private var pinColor: Color { VenuuTheme.primaryPurple }
    private var accentColor: Color { VenuuTheme.primaryBlue }

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

            // The pin body
            pinBody
                .offset(y: floatOffset)
        }
        .frame(width: size * 1.5, height: size * 1.5)
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
            // Shadow under pin
            Ellipse()
                .fill(Color.black.opacity(0.10))
                .frame(width: size * 0.45, height: size * 0.10)
                .offset(y: size * 0.52)
                .blur(radius: 4)

            // Pin tail (triangle pointing down)
            pinTail
                .offset(y: size * 0.22)

            // Main circle head
            Circle()
                .fill(
                    LinearGradient(
                        colors: [pinColor, accentColor],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size * 0.65, height: size * 0.65)
                .shadow(color: pinColor.opacity(0.35), radius: 12, y: 4)

            // Inner white circle (face area)
            Circle()
                .fill(Color.white.opacity(0.95))
                .frame(width: size * 0.50, height: size * 0.50)

            // Face
            faceView
        }
    }

    // MARK: - Pin Tail

    private var pinTail: some View {
        Triangle()
            .fill(
                LinearGradient(
                    colors: [accentColor, pinColor.opacity(0.8)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: size * 0.22, height: size * 0.28)
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
                // Wink — a curved line
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
                    .stroke(Color(red: 0.25, green: 0.20, blue: 0.35), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .frame(width: size * 0.12, height: size * 0.06)
            case .excited:
                Ellipse()
                    .fill(Color(red: 0.25, green: 0.20, blue: 0.35))
                    .frame(width: size * 0.08, height: size * 0.06)
            }
        }
    }
}

// MARK: - Custom Shapes

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

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
