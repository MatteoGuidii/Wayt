import SwiftUI

/// A friendly sign-up prompt shown when guests try to perform auth-gated actions.
/// Frames sign-up as a value exchange, not a gate.
struct AuthGateSheet: View {

    let onSignUp: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 14) {
            VenuuMascot(size: 90, expression: .looking)
                .padding(.top, 16)

            VStack(spacing: 12) {
                Text("Join the community")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)

                Text("Create an account to share wait times\nwith the community")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            VStack(spacing: 8) {
                benefitRow(icon: "megaphone.fill", text: "Report how busy places are")
                benefitRow(icon: "star.fill", text: "Save your favorite venues")
                benefitRow(icon: "chart.bar.fill", text: "Track your contributions")
            }
            .padding(.horizontal, 32)

            Spacer()

            VStack(spacing: 10) {
                Button(action: {
                    dismiss()
                    // Small delay so dismiss animation completes before navigating
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        onSignUp()
                    }
                }) {
                    Text("Create account")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [VenuuTheme.primaryPurple, VenuuTheme.primaryBlue],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(Capsule())
                        .shadow(color: VenuuTheme.primaryPurple.opacity(0.3), radius: 10, y: 5)
                }

                Button("Maybe later") {
                    dismiss()
                }
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
    }

    private func benefitRow(icon: String, text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(VenuuTheme.primaryPurple)
                .frame(width: 28)

            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(.primary)

            Spacer()
        }
    }
}
