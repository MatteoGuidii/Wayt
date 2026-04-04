import SwiftUI

struct ConfirmSignUpFormView: View {
    @ObservedObject var viewModel: AuthFlowViewModel
    @FocusState private var codeFocused: Bool

    private var canSubmit: Bool {
        viewModel.code.count == 6
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Confirm Your Email")
                .font(WaytTheme.heroFont)
                .foregroundStyle(WaytTheme.primaryText)

            if let error = viewModel.errorMessage {
                AuthErrorBanner(message: error)
            }
            if let info = viewModel.infoMessage {
                AuthInfoBanner(message: info)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Enter the 6-digit code sent to **\(viewModel.pendingEmail)**")
                    .font(WaytTheme.bodyFont)
                    .foregroundStyle(WaytTheme.secondaryText)

                Text("Don't see it? Check your spam or junk folder.")
                    .font(WaytTheme.subtitleFont)
                    .foregroundStyle(WaytTheme.secondaryText)
            }

            AuthFieldView(
                label: "Verification Code",
                placeholder: "123456",
                text: $viewModel.code,
                keyboardType: .numberPad,
                textContentType: .oneTimeCode
            )
            .focused($codeFocused)
            .onChange(of: viewModel.code) { _, newValue in
                if newValue.count > 6 {
                    viewModel.code = String(newValue.prefix(6))
                }
            }

            AuthPrimaryButton(title: "Confirm", isLoading: viewModel.isLoading) {
                Task { await viewModel.confirmSignUp() }
            }
            .disabled(!canSubmit || viewModel.isLoading)
            .opacity(canSubmit ? 1 : 0.6)
            .padding(.top, 8)

            HStack {
                Button("Resend code") {
                    Task { await viewModel.resendCode() }
                }
                Spacer()
                Button("Back to sign in") {
                    viewModel.goToSignIn()
                }
            }
            .font(WaytTheme.subtitleFont)
            .foregroundStyle(WaytTheme.mapsBlue)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                codeFocused = true
            }
        }
    }
}
