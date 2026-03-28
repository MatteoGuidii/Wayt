import SwiftUI

/// The Wayt brand mark — a stylized W with integrated hourglass shape.
/// Draws the same geometry as the app icon: white strokes on a yellow→ochre
/// gradient rounded rectangle.
struct WaytLogomark: View {

    let size: CGFloat

    var body: some View {
        Canvas { context, canvasSize in
            let s = canvasSize.width
            let scale = s / 1024

            // Background rounded rect
            let cornerRadius = 224 * scale
            let bgRect = CGRect(origin: .zero, size: canvasSize)
            let bgPath = Path(roundedRect: bgRect, cornerRadius: cornerRadius, style: .continuous)

            context.fill(
                bgPath,
                with: .linearGradient(
                    Gradient(colors: [
                        Color(red: 1.0, green: 0.84, blue: 0.0),    // #FFD600
                        Color(red: 0.80, green: 0.48, blue: 0.0),   // #CC7A00
                    ]),
                    startPoint: CGPoint(x: s / 2, y: 0),
                    endPoint: CGPoint(x: s / 2, y: s)
                )
            )

            // All strokes: white, round cap
            let strokeWidth = 80 * scale
            let strokeStyle = StrokeStyle(lineWidth: strokeWidth, lineCap: .round)

            // Line segments in 1024×1024 coordinate space
            let lines: [(CGPoint, CGPoint)] = [
                // Outer W legs
                (CGPoint(x: 150, y: 200), CGPoint(x: 350, y: 824)),
                (CGPoint(x: 874, y: 200), CGPoint(x: 674, y: 824)),
                // Lower V
                (CGPoint(x: 350, y: 824), CGPoint(x: 512, y: 560)),
                (CGPoint(x: 674, y: 824), CGPoint(x: 512, y: 560)),
                // Upper triangle
                (CGPoint(x: 400, y: 336), CGPoint(x: 624, y: 336)),
                (CGPoint(x: 400, y: 336), CGPoint(x: 512, y: 560)),
                (CGPoint(x: 624, y: 336), CGPoint(x: 512, y: 560)),
            ]

            for (start, end) in lines {
                var path = Path()
                path.move(to: CGPoint(x: start.x * scale, y: start.y * scale))
                path.addLine(to: CGPoint(x: end.x * scale, y: end.y * scale))
                context.stroke(path, with: .color(.white), style: strokeStyle)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Wayt logo")
    }
}

#Preview("Logomark Sizes") {
    HStack(spacing: 24) {
        WaytLogomark(size: 100)
        WaytLogomark(size: 64)
        WaytLogomark(size: 48)
    }
    .padding()
}
