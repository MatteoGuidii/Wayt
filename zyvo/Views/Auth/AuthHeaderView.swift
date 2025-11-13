import SwiftUI

struct AuthHeaderView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Zyvo")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Simplest way to get started. Sign in or create an account.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 24)
        }
    }
}

#Preview {
    ZStack {
        LinearGradient(
            colors: [.purple.opacity(0.3), .blue.opacity(0.3)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()

        AuthHeaderView()
    }
}
