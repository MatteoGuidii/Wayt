import SwiftUI

struct SignUpFormView: View {
    @ObservedObject var viewModel: AuthFlowViewModel
    @FocusState private var focus: Field?

    private enum Field { case email, password, confirmPassword }

    private var passwordHint: String? {
        guard !viewModel.password.isEmpty, viewModel.password.count < 8 else { return nil }
        return "At least 8 characters"
    }

    private var confirmHint: String? {
        guard !viewModel.confirmPassword.isEmpty,
              !viewModel.password.isEmpty,
              viewModel.password != viewModel.confirmPassword else { return nil }
        return "Passwords don't match"
    }

    private var canSubmit: Bool {
        viewModel.isValidEmail(viewModel.email)
            && viewModel.password.count >= 8
            && viewModel.password == viewModel.confirmPassword
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create Account")
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
                placeholder: "Enter a password",
                text: $viewModel.password,
                isSecure: true,
                hint: passwordHint,
                onSubmit: { focus = .confirmPassword }
            )
            .focused($focus, equals: .password)

            AuthFieldView(
                label: "Confirm Password",
                placeholder: "Re-enter your password",
                text: $viewModel.confirmPassword,
                isSecure: true,
                hint: confirmHint,
                onSubmit: { if canSubmit { Task { await viewModel.signUp() } } }
            )
            .focused($focus, equals: .confirmPassword)

            AuthPrimaryButton(title: "Create Account", isLoading: viewModel.isLoading) {
                Task { await viewModel.signUp() }
            }
            .disabled(!canSubmit || viewModel.isLoading)
            .opacity(canSubmit ? 1 : 0.6)
            .padding(.top, 8)

            Button("Already have an account? Sign in") {
                viewModel.goToSignIn()
            }
            .font(WaytTheme.subtitleFont)
            .foregroundStyle(WaytTheme.mapsBlue)
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }
}
