import SwiftUI

struct WelcomeView: View {
    let username: String
    let onSignOut: () -> Void

    var body: some View {
        LinearGradient(
            colors: [.purple.opacity(0.4), .blue.opacity(0.4)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        .overlay(content)
    }

    private var content: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("Hi, welcome to Zyvo")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)

            Text("Signed in as \(username)")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.85))

            Spacer()

            Button(action: onSignOut) {
                Text("Sign Out")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .foregroundStyle(.black)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
        .padding(.horizontal, 24)
    }
}

#Preview {
    WelcomeView(username: "matteo@example.com", onSignOut: {})
}
