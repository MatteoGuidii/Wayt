import Amplify
import Combine
import os
import SwiftUI

@MainActor
final class AuthFlowViewModel: ObservableObject {

    // MARK: - Step

    enum Step: Equatable {
        case signIn
        case signUp
        case confirmSignUp
        case forgotPassword
        case confirmResetPassword
    }

    // MARK: - Published State

    @Published var step: Step = .signIn

    @Published var email = ""
    @Published var password = ""
    @Published var confirmPassword = ""
    @Published var code = ""
    @Published var newPassword = ""
    @Published var confirmNewPassword = ""

    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var infoMessage: String?

    var onSignedIn: ((String) -> Void)?
    private(set) var pendingEmail = ""

    // MARK: - Validation

    private static let emailPredicate = NSPredicate(
        format: "SELF MATCHES %@",
        "[A-Z0-9a-z._%+\\-]+@[A-Za-z0-9.\\-]+\\.[A-Za-z]{2,}"
    )

    func isValidEmail(_ value: String) -> Bool {
        Self.emailPredicate.evaluate(with: value)
    }

    func isValidPassword(_ value: String) -> Bool {
        value.count >= 8
    }

    // MARK: - Navigation

    func reset() {
        step = .signIn
        email = ""
        password = ""
        confirmPassword = ""
        code = ""
        newPassword = ""
        confirmNewPassword = ""
        pendingEmail = ""
        clearMessages()
    }

    func goToSignIn() {
        step = .signIn
        clearMessages()
    }

    func goToSignUp() {
        step = .signUp
        clearMessages()
    }

    func goToForgotPassword() {
        step = .forgotPassword
        clearMessages()
    }

    // MARK: - Sign In

    func signIn() async {
        guard !email.isEmpty, !password.isEmpty else {
            errorMessage = "Please enter your email and password."
            return
        }

        isLoading = true
        defer { isLoading = false }
        clearMessages()

        let trimmedEmail = email.trimmedLowercased

        do {
            let result = try await Amplify.Auth.signIn(
                username: trimmedEmail,
                password: password
            )

            switch result.nextStep {
            case .done:
                let user = try await Amplify.Auth.getCurrentUser()
                completeSignIn(username: user.username)

            case .confirmSignUp:
                pendingEmail = trimmedEmail
                step = .confirmSignUp
                infoMessage = "Please confirm your email to continue."

            case .resetPassword:
                step = .forgotPassword
                infoMessage = "Your password needs to be reset."

            default:
                errorMessage = "Unexpected sign-in step. Please try again."
            }
        } catch {
            errorMessage = userFacingMessage(from: error)
        }
    }

    // MARK: - Sign Up

    func signUp() async {
        guard isValidEmail(email) else {
            errorMessage = "Please enter a valid email address."
            return
        }
        guard isValidPassword(password) else {
            errorMessage = "Password must be at least 8 characters."
            return
        }
        guard password == confirmPassword else {
            errorMessage = "Passwords don't match."
            return
        }

        isLoading = true
        defer { isLoading = false }
        clearMessages()

        let trimmedEmail = email.trimmedLowercased

        do {
            let result = try await Amplify.Auth.signUp(
                username: trimmedEmail,
                password: password,
                options: .init(userAttributes: [
                    AuthUserAttribute(.email, value: trimmedEmail)
                ])
            )

            pendingEmail = trimmedEmail

            switch result.nextStep {
            case .confirmUser:
                step = .confirmSignUp
                infoMessage = "We sent a 6-digit code to \(trimmedEmail)."

            case .done:
                // Auto-confirmed (unusual with email verification on)
                let user = try await Amplify.Auth.getCurrentUser()
                completeSignIn(username: user.username)

            default:
                errorMessage = "Unexpected sign-up step. Please try again."
            }
        } catch {
            errorMessage = userFacingMessage(from: error)
        }
    }

    // MARK: - Confirm Sign Up

    func confirmSignUp() async {
        guard code.count == 6 else {
            errorMessage = "Please enter the 6-digit code."
            return
        }

        isLoading = true
        defer { isLoading = false }
        clearMessages()

        do {
            let result = try await Amplify.Auth.confirmSignUp(
                for: pendingEmail,
                confirmationCode: code
            )

            switch result.nextStep {
            case .done, .completeAutoSignIn:
                // Auto sign-in with the password still held on the VM
                let signInResult = try await Amplify.Auth.signIn(
                    username: pendingEmail,
                    password: password
                )
                if case .done = signInResult.nextStep {
                    let user = try await Amplify.Auth.getCurrentUser()
                    completeSignIn(username: user.username)
                } else {
                    // Fallback — ask user to sign in manually
                    step = .signIn
                    infoMessage = "Account confirmed. Please sign in."
                }

            default:
                errorMessage = "Unexpected confirmation step. Please try again."
            }
        } catch {
            errorMessage = userFacingMessage(from: error)
        }
    }

    func resendCode() async {
        isLoading = true
        defer { isLoading = false }
        clearMessages()

        do {
            _ = try await Amplify.Auth.resendSignUpCode(for: pendingEmail)
            infoMessage = "A new code was sent to \(pendingEmail)."
        } catch {
            errorMessage = userFacingMessage(from: error)
        }
    }

    // MARK: - Forgot Password

    func sendResetCode() async {
        guard isValidEmail(email) else {
            errorMessage = "Please enter a valid email address."
            return
        }

        isLoading = true
        defer { isLoading = false }
        clearMessages()

        let trimmedEmail = email.trimmedLowercased

        do {
            let result = try await Amplify.Auth.resetPassword(for: trimmedEmail)
            pendingEmail = trimmedEmail

            switch result.nextStep {
            case .confirmResetPasswordWithCode:
                step = .confirmResetPassword
                infoMessage = "Check your email for a reset code."

            case .done:
                step = .signIn
                infoMessage = "Password reset. Please sign in."
            }
        } catch {
            errorMessage = userFacingMessage(from: error)
        }
    }

    func confirmResetPassword() async {
        guard code.count == 6 else {
            errorMessage = "Please enter the 6-digit reset code."
            return
        }
        guard isValidPassword(newPassword) else {
            errorMessage = "Password must be at least 8 characters."
            return
        }
        guard newPassword == confirmNewPassword else {
            errorMessage = "Passwords don't match."
            return
        }

        isLoading = true
        defer { isLoading = false }
        clearMessages()

        do {
            try await Amplify.Auth.confirmResetPassword(
                for: pendingEmail,
                with: newPassword,
                confirmationCode: code
            )
            // Pre-fill the sign-in password so user can just tap Sign In
            password = newPassword
            step = .signIn
            infoMessage = "Password updated. Please sign in."
        } catch {
            errorMessage = userFacingMessage(from: error)
        }
    }

    // MARK: - Helpers

    private func completeSignIn(username: String) {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        onSignedIn?(username)
    }

    private func clearMessages() {
        errorMessage = nil
        infoMessage = nil
    }

    private func userFacingMessage(from error: Error) -> String {
        Log.auth.error("Auth error: \(error.localizedDescription)")

        guard let authError = error as? AuthError else {
            return error.localizedDescription
        }

        switch authError {
        case .notAuthorized:
            return "Incorrect email or password."
        case .validation(_, let description, _, _):
            return description
        case .service(let description, _, _):
            return description
        default:
            return authError.errorDescription
        }
    }
}

// MARK: - String Helpers

private extension String {
    var trimmedLowercased: String {
        trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
