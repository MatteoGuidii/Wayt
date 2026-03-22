import SwiftUI

/// A friendly sign-up prompt shown when guests try to perform auth-gated actions.
/// Frames sign-up as a value exchange, not a gate.
struct AuthGateSheet: View {

    let onSignUp: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 5) {
            WaytMascot(size: 90, expression: .looking)
                .padding(.top, 8)

            VStack(spacing: 12) {
                Text("Join the community")
                    .font(WaytTheme.largeTitleFont)
                    .multilineTextAlignment(.center)

                Text("Create an account to share wait times\nwith the community")
                    .font(WaytTheme.bodyFont)
                    .foregroundStyle(WaytTheme.secondaryText)
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
                        .font(WaytTheme.title3Font)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(WaytTheme.skyPunch)
                        .clipShape(Capsule())
                        .shadow(color: WaytTheme.skyPunch.opacity(0.3), radius: 10, y: 5)
                }

                Button("Maybe later") {
                    dismiss()
                }
                .font(WaytTheme.calloutBoldFont)
                .foregroundStyle(WaytTheme.secondaryText)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
    }

    private func benefitRow(icon: String, text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(WaytTheme.bodyBoldFont)
                .foregroundStyle(WaytTheme.skyPunch)
                .frame(width: 28)

            Text(text)
                .font(WaytTheme.subtitleFont)
                .foregroundStyle(.primary)

            Spacer()
        }
    }
}

#Preview("Auth Gate") {
    AuthGateSheet(onSignUp: {})
}
