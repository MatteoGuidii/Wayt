import Combine
import Foundation
import Amplify

@MainActor
final class AuthManager: ObservableObject {
    enum AuthState: Equatable {
        case loading
        case signedOut
        case signedIn(username: String)
    }

    enum SignUpStatus {
        case signedIn
        case confirmationRequired(message: String)
    }

    @Published private(set) var authState: AuthState = .loading
    @Published var infoMessage: String?
    @Published var pendingConfirmationEmail: String?

    func refreshAuthState() async {
        do {
            let session = try await Amplify.Auth.fetchAuthSession()
            if session.isSignedIn {
                let user = try await Amplify.Auth.getCurrentUser()
                authState = .signedIn(username: user.username)
            } else {
                authState = .signedOut
            }
        } catch {
            infoMessage = error.localizedDescription
            authState = .signedOut
        }
    }

    func signUp(email: String, password: String) async throws -> SignUpStatus {
        let normalizedEmail = normalize(email)
        let attributes = [AuthUserAttribute(.email, value: normalizedEmail)]
        let options = AuthSignUpRequest.Options(userAttributes: attributes)

        let result = try await Amplify.Auth.signUp(
            username: normalizedEmail,
            password: password,
            options: options
        )

        switch result.nextStep {
        case .done:
            try await signIn(username: normalizedEmail, password: password)
            return .signedIn
        case .confirmUser(let details, _, _):
            pendingConfirmationEmail = normalizedEmail
            let message = confirmationMessage(for: details)
            infoMessage = message
            return .confirmationRequired(message: message)
        default:
            pendingConfirmationEmail = normalizedEmail
            let message = confirmationMessage(for: (nil as AuthCodeDeliveryDetails?))
            infoMessage = message
            return .confirmationRequired(message: message)
        }
    }

    func signIn(email: String, password: String) async throws -> Bool {
        let normalizedEmail = normalize(email)
        return try await signIn(username: normalizedEmail, password: password)
    }

    func confirmSignUp(email: String, code: String) async throws -> Bool {
        let normalizedEmail = normalize(email)
        let result = try await Amplify.Auth.confirmSignUp(for: normalizedEmail, confirmationCode: code)

        if result.isSignUpComplete {
            pendingConfirmationEmail = nil
            infoMessage = nil
        } else {
            infoMessage = "Confirmation incomplete. Please try again."
        }

        return result.isSignUpComplete
    }

    func resendConfirmationCode(email: String) async throws -> String {
        let normalizedEmail = normalize(email)
        let result = try await Amplify.Auth.resendSignUpCode(for: normalizedEmail)
        // Track pending email so UI can present confirmation field
        pendingConfirmationEmail = normalizedEmail
        let message = confirmationMessage(for: result)
        infoMessage = message
        return message
    }

    func signOut() async {
        _ = await Amplify.Auth.signOut()
        await refreshAuthState()
    }

    var currentUsername: String? {
        if case let .signedIn(username) = authState {
            return username
        }
        return nil
    }

    var isSignedIn: Bool {
        currentUsername != nil
    }

    @discardableResult
    private func signIn(username: String, password: String) async throws -> Bool {
        let result = try await Amplify.Auth.signIn(username: username, password: password)

        if result.isSignedIn {
            authState = .signedIn(username: username)
            infoMessage = nil
        } else {
            infoMessage = "Additional steps are required to finish signing in."
        }

        return result.isSignedIn
    }

    private func normalize(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func confirmationMessage(for details: AuthCodeDeliveryDetails?) -> String {
        if let details {
            let destination = details.destination
            let value = String(describing: destination)
            if !value.isEmpty {
                return "Please confirm the code sent to \(value)."
            }
        }
        return "Please confirm the verification code we just sent."
    }
}
