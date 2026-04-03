import SwiftUI

struct ConfirmResetPasswordFormView: View {
    @ObservedObject var viewModel: AuthFlowViewModel
    @FocusState private var focus: Field?

    private enum Field { case code, newPassword, confirmPassword }

    private var passwordHint: String? {
        guard !viewModel.newPassword.isEmpty, viewModel.newPassword.count < 8 else { return nil }
        return "At least 8 characters"
    }

    private var confirmHint: String? {
        guard !viewModel.confirmNewPassword.isEmpty,
              !viewModel.newPassword.isEmpty,
              viewModel.newPassword != viewModel.confirmNewPassword else { return nil }
        return "Passwords don't match"
    }

    private var canSubmit: Bool {
        viewModel.code.count == 6
            && viewModel.newPassword.count >= 8
            && viewModel.newPassword == viewModel.confirmNewPassword
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Set New Password")
                .font(WaytTheme.heroFont)
                .foregroundStyle(WaytTheme.primaryText)

            if let error = viewModel.errorMessage {
                AuthErrorBanner(message: error)
            }
            if let info = viewModel.infoMessage {
                AuthInfoBanner(message: info)
            }

            AuthFieldView(
                label: "Reset Code",
                placeholder: "123456",
                text: $viewModel.code,
                keyboardType: .numberPad
            )
            .focused($focus, equals: .code)
            .onChange(of: viewModel.code) { _, newValue in
                if newValue.count > 6 {
                    viewModel.code = String(newValue.prefix(6))
                }
            }

            AuthFieldView(
                label: "New Password",
                placeholder: "Enter a new password",
                text: $viewModel.newPassword,
                isSecure: true,
                hint: passwordHint,
                onSubmit: { focus = .confirmPassword }
            )
            .focused($focus, equals: .newPassword)

            AuthFieldView(
                label: "Confirm Password",
                placeholder: "Re-enter your new password",
                text: $viewModel.confirmNewPassword,
                isSecure: true,
                hint: confirmHint,
                onSubmit: { if canSubmit { Task { await viewModel.confirmResetPassword() } } }
            )
            .focused($focus, equals: .confirmPassword)

            AuthPrimaryButton(title: "Update Password", isLoading: viewModel.isLoading) {
                Task { await viewModel.confirmResetPassword() }
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
    }
}
