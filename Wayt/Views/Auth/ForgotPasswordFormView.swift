import SwiftUI

struct ForgotPasswordFormView: View {
    @ObservedObject var viewModel: AuthFlowViewModel
    @FocusState private var emailFocused: Bool

    private var canSubmit: Bool {
        viewModel.isValidEmail(viewModel.email)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Reset Password")
                .font(WaytTheme.heroFont)
                .foregroundStyle(WaytTheme.primaryText)

            if let error = viewModel.errorMessage {
                AuthErrorBanner(message: error)
            }
            if let info = viewModel.infoMessage {
                AuthInfoBanner(message: info)
            }

            Text("Enter your email and we'll send you a code to reset your password.")
                .font(WaytTheme.bodyFont)
                .foregroundStyle(WaytTheme.secondaryText)

            AuthFieldView(
                label: "Email",
                placeholder: "you@example.com",
                text: $viewModel.email,
                keyboardType: .emailAddress,
                textContentType: .emailAddress,
                onSubmit: { if canSubmit { Task { await viewModel.sendResetCode() } } }
            )
            .focused($emailFocused)

            AuthPrimaryButton(title: "Send Reset Code", isLoading: viewModel.isLoading) {
                Task { await viewModel.sendResetCode() }
            }
            .disabled(!canSubmit || viewModel.isLoading)
            .opacity(canSubmit ? 1 : 0.6)
            .padding(.top, 8)

            Button("Back to sign in") {
                viewModel.goToSignIn()
            }
            .font(WaytTheme.subtitleFont)
            .foregroundStyle(WaytTheme.mapsBlue)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .onAppear { emailFocused = true }
    }
}
