//
//  SignupView.swift
//  zyvo
//
//  Created by Matteo Guidi on 2025-11-12.
//

import SwiftUI
import Amplify

struct SignupView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: AuthManager
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var statusMessage: String?
    @State private var isSubmitting = false
    @State private var confirmationEmail: String?
    @State private var confirmationCode = ""
    @State private var isConfirming = false
    private let inputFieldBackground = Color.white.opacity(0.92)
    private let inputTextColor = Color.black.opacity(0.85)
    private let placeholderColor = Color.black.opacity(0.55)

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.purple.opacity(0.3), .blue.opacity(0.3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 32) {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Label("Close", systemImage: "xmark.circle.fill")
                            .font(.headline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.white.opacity(0.2), in: Capsule())
                            .foregroundStyle(.white)
                    }
                    .padding(.leading)

                    Spacer()
                }
                .padding(.top, 16)

                AuthHeaderView()

                VStack(spacing: 16) {
                    TextField("", text: $email, prompt: Text("Email").foregroundStyle(placeholderColor))
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .padding()
                        .foregroundStyle(inputTextColor)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(inputFieldBackground)
                                .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 6)
                        )

                    SecureField("", text: $password, prompt: Text("Password").foregroundStyle(placeholderColor))
                        .textContentType(.newPassword)
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .padding()
                        .foregroundStyle(inputTextColor)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(inputFieldBackground)
                                .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 6)
                        )

                    SecureField("", text: $confirmPassword, prompt: Text("Confirm Password").foregroundStyle(placeholderColor))
                        .textContentType(.newPassword)
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .padding()
                        .foregroundStyle(inputTextColor)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(inputFieldBackground)
                                .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 6)
                        )
                }
                .padding(.horizontal, 24)

                if let statusMessage {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Button(action: handleSignup) {
                    Group {
                        if isSubmitting {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.black)
                        } else {
                            Text("Create Account")
                        }
                    }
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .foregroundStyle(.black)
                }
                .disabled(!isFormValid || isSubmitting)
                .padding(.horizontal, 32)

                if let confirmationEmail {
                    confirmationSection(for: confirmationEmail)
                }

                Spacer()
            }
        }
    }
}

private extension SignupView {
    var isFormValid: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        password.count >= 6 &&
        password == confirmPassword
    }

    var isConfirmationValid: Bool {
        !(confirmationCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func handleSignup() {
        guard !isSubmitting else { return }
        statusMessage = nil
        isSubmitting = true

        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        Task {
            do {
                let result = try await authManager.signUp(email: normalizedEmail, password: password)
                await MainActor.run {
                    isSubmitting = false
                }

                switch result {
                case .signedIn:
                    await MainActor.run {
                        dismiss()
                    }
                case .confirmationRequired(let message):
                    await MainActor.run {
                        statusMessage = message
                        confirmationEmail = normalizedEmail
                        confirmationCode = ""
                    }
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                }

                if await handleExistingAccountFlow(email: normalizedEmail, error: error) {
                    return
                }

                await MainActor.run {
                    statusMessage = error.localizedDescription
                }
            }
        }
    }

    func handleConfirmation(for email: String) {
        guard !isConfirming, isConfirmationValid else { return }
        statusMessage = nil
        isConfirming = true

        Task {
            do {
                let didConfirm = try await authManager.confirmSignUp(email: email, code: confirmationCode)
                if didConfirm {
                    let didSignIn = try await authManager.signIn(email: email, password: password)
                    await MainActor.run {
                        isConfirming = false
                        if didSignIn {
                            dismiss()
                        } else {
                            statusMessage = authManager.infoMessage ?? "Confirmed. Please log in."
                        }
                    }
                } else {
                    await MainActor.run {
                        isConfirming = false
                        statusMessage = authManager.infoMessage ?? "Confirmation incomplete."
                    }
                }
            } catch {
                await MainActor.run {
                    isConfirming = false
                    statusMessage = error.localizedDescription
                }
            }
        }
    }

    @ViewBuilder
    func confirmationSection(for email: String) -> some View {
        VStack(spacing: 12) {
            Text("Enter the 6-digit code sent to \(email)")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.9))

            TextField("Confirmation Code", text: $confirmationCode)
                .keyboardType(.numberPad)
                .textInputAutocapitalization(.never)
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .padding()
                .foregroundStyle(inputTextColor)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(inputFieldBackground)
                        .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 6)
                )

            Button(action: { handleConfirmation(for: email) }) {
                Group {
                    if isConfirming {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    } else {
                        Text("Verify Code")
                    }
                }
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .foregroundStyle(.white)
            }
            .disabled(!isConfirmationValid || isConfirming)
        }
        .padding(.horizontal, 32)
    }

    func handleExistingAccountFlow(email: String, error: Error) async -> Bool {
        guard isUsernameExistsError(error) else { return false }

        do {
            let message = try await authManager.resendConfirmationCode(email: email)
            await MainActor.run {
                confirmationEmail = email
                confirmationCode = ""
                statusMessage = message
            }
        } catch {
            await MainActor.run {
                statusMessage = error.localizedDescription
            }
        }

        return true
    }

    func isUsernameExistsError(_ error: Error) -> Bool {
        guard let authError = error as? AuthError else { return false }
        if case let .service(message, _, _) = authError {
            return message.lowercased().contains("exist")
        }
        return false
    }
}

#Preview {
    SignupView()
        .environmentObject(AuthManager())
}
