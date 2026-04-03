import SwiftUI

struct SignInFormView: View {
    @ObservedObject var viewModel: AuthFlowViewModel
    @FocusState private var focus: Field?

    private enum Field { case email, password }

    private var canSubmit: Bool {
        !viewModel.email.isEmpty && !viewModel.password.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sign In")
                .font(WaytTheme.heroFont)
                .foregroundStyle(WaytTheme.primaryText)

            if let error = viewModel.errorMessage {
                AuthErrorBanner(message: error)
            }
            if let info = viewModel.infoMessage {
                AuthInfoBanner(message: info)
            }

            AuthFieldView(
                label: "Email",
                placeholder: "you@example.com",
                text: $viewModel.email,
                keyboardType: .emailAddress,
                textContentType: .emailAddress,
                onSubmit: { focus = .password }
            )
            .focused($focus, equals: .email)

            AuthFieldView(
                label: "Password",
                placeholder: "Enter your password",
                text: $viewModel.password,
                isSecure: true,
                onSubmit: { if canSubmit { Task { await viewModel.signIn() } } }
            )
            .focused($focus, equals: .password)

            AuthPrimaryButton(title: "Sign In", isLoading: viewModel.isLoading) {
                Task { await viewModel.signIn() }
            }
            .disabled(!canSubmit || viewModel.isLoading)
            .opacity(canSubmit ? 1 : 0.6)
            .padding(.top, 8)

            HStack {
                Button("Forgot password?") {
                    viewModel.goToForgotPassword()
                }
                Spacer()
                Button("Create account") {
                    viewModel.goToSignUp()
                }
            }
            .font(WaytTheme.subtitleFont)
            .foregroundStyle(WaytTheme.mapsBlue)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }
}
