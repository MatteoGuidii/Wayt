import SwiftUI

/// A friendly sign-up prompt shown when guests try to perform auth-gated actions.
/// Frames sign-up as a value exchange, not a gate.
struct AuthGateSheet: View {

    let onSignUp: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 5) {
            VenuuMascot(size: 90, expression: .looking)
                .padding(.top, 8)

            VStack(spacing: 12) {
                Text("Join the community")
                    .font(VenuuTheme.largeTitleFont)
                    .multilineTextAlignment(.center)

                Text("Create an account to share wait times\nwith the community")
                    .font(VenuuTheme.bodyFont)
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
                    onSignUp()
                }) {
                    Text("Create account")
                        .font(VenuuTheme.title3Font)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(VenuuTheme.skyPunch)
                        .clipShape(Capsule())
                        .shadow(color: VenuuTheme.skyPunch.opacity(0.3), radius: 10, y: 5)
                }

                Button("Maybe later") {
                    dismiss()
                }
                .font(VenuuTheme.calloutBoldFont)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
    }

    private func benefitRow(icon: String, text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(VenuuTheme.bodyBoldFont)
                .foregroundStyle(VenuuTheme.skyPunch)
                .frame(width: 28)

            Text(text)
                .font(VenuuTheme.subtitleFont)
                .foregroundStyle(.primary)

            Spacer()
        }
    }
}

#Preview("Auth Gate") {
    AuthGateSheet(onSignUp: {})
}
