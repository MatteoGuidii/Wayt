import SwiftUI

struct RankUpCelebration: View {

    let rank: UserRank
    let onDismiss: () -> Void

    @State private var showContent = false
    @State private var dismissed = false
    @State private var particles: [ConfettiParticle] = []

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                    .onTapGesture {
                        guard !dismissed else { return }
                        dismissed = true
                        onDismiss()
                    }

                ForEach(particles) { particle in
                    Circle()
                        .fill(particle.color)
                        .frame(width: particle.size, height: particle.size)
                        .offset(x: particle.x, y: particle.y)
                        .opacity(particle.opacity)
                }

                if showContent {
                    VStack(spacing: 16) {
                        Image(systemName: rank.icon)
                            .font(.system(size: 64, weight: .bold))
                            .foregroundStyle(rank.color)
                            .shadow(color: rank.color.opacity(0.5), radius: 20)

                        Text("You're now a")
                            .font(WaytTheme.bodyFont)
                            .foregroundStyle(.white.opacity(0.8))

                        Text(rank.title)
                            .font(.system(size: 32, weight: .black, design: .rounded))
                            .foregroundStyle(.white)

                        Text(rank.subtitle)
                            .font(WaytTheme.subheadLightFont)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
                }
            }
            .onAppear {
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)

                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                    showContent = true
                }

                spawnConfetti(in: geo.size)

                DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                    guard !dismissed else { return }
                    dismissed = true
                    onDismiss()
                }
            }
        }
    }

    private func spawnConfetti(in size: CGSize) {
        let colors: [Color] = rank.progressBarColors + [rank.color, .white]
        let halfW = size.width / 2
        let halfH = size.height / 2

        particles = (0..<30).map { i in
            ConfettiParticle(
                id: UUID(),
                color: colors[i % colors.count],
                size: CGFloat.random(in: 6...12),
                x: CGFloat.random(in: -halfW...halfW),
                y: -halfH,
                opacity: 1.0
            )
        }

        withAnimation(.easeIn(duration: 4.0)) {
            for i in particles.indices {
                particles[i].y = CGFloat.random(in: -halfH...halfH)
                particles[i].x += CGFloat.random(in: -100...100)
                particles[i].opacity = 0.0
            }
        }
    }
}

private struct ConfettiParticle: Identifiable {
    let id: UUID
    let color: Color
    let size: CGFloat
    var x: CGFloat
    var y: CGFloat
    var opacity: Double
}
