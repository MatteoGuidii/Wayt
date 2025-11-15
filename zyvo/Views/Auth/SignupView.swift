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
    @FocusState private var focusedField: Field?

    var body: some View {
        AuthGradientBackground {
            ScrollView {
                VStack(spacing: 32) {
                    header

                    inputFields
                        .padding(.horizontal, 24)

                    if let statusMessage {
                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }

                    signupButton
                        .padding(.horizontal, 32)

                    if let confirmationEmail {
                        confirmationSection(for: confirmationEmail)
                    }

                    Color.clear
                        .frame(height: 80)
                }
                .padding(.top, 16)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

private extension SignupView {
    var header: some View {
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

                Spacer()
            }
            .padding(.horizontal)

            AuthHeaderView()
        }
    }

    var isFormValid: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        password.count >= 6 &&
        password == confirmPassword
    }

    var inputFields: some View {
        VStack(spacing: 16) {
            TextField("", text: $email, prompt: Text("Email").foregroundStyle(AuthTheme.placeholderColor))
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundStyle(AuthTheme.inputTextColor)
                .authInputFieldStyle()
                .submitLabel(.next)
                .focused($focusedField, equals: .email)
                .onSubmit {
                    focusedField = .password
                }

            SecureField("", text: $password, prompt: Text("Password").foregroundStyle(AuthTheme.placeholderColor))
                .textContentType(.newPassword)
                .textInputAutocapitalization(.never)
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundStyle(AuthTheme.inputTextColor)
                .authInputFieldStyle()
                .submitLabel(.next)
                .focused($focusedField, equals: .password)
                .onSubmit {
                    focusedField = .confirmPassword
                }

            SecureField("", text: $confirmPassword, prompt: Text("Confirm Password").foregroundStyle(AuthTheme.placeholderColor))
                .textContentType(.newPassword)
                .textInputAutocapitalization(.never)
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundStyle(AuthTheme.inputTextColor)
                .authInputFieldStyle()
                .submitLabel(.go)
                .focused($focusedField, equals: .confirmPassword)
                .onSubmit {
                    if isFormValid {
                        handleSignup()
                    }
                }
        }
    }

    var signupButton: some View {
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
            .background(AuthTheme.secondaryButtonBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .foregroundStyle(AuthTheme.secondaryButtonForeground)
        }
        .buttonStyle(.plain)
        .disabled(!isFormValid || isSubmitting)
        .animation(nil, value: isSubmitting)
        .animation(nil, value: isFormValid)
    }

    var isConfirmationValid: Bool {
        !(confirmationCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func handleSignup() {
        guard !isSubmitting else { return }
        statusMessage = nil
        isSubmitting = true
        focusedField = nil

        Task {
            do {
                let result = try await authManager.signUp(email: email, password: password)
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
                        confirmationEmail = email
                        confirmationCode = ""
                        focusedField = .confirmationCode
                    }
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                }

                if await handleExistingAccountFlow(email: email, error: error) {
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
        focusedField = nil

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
                .textContentType(.oneTimeCode)
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundStyle(AuthTheme.inputTextColor)
                .authInputFieldStyle()
                .submitLabel(.done)
                .focused($focusedField, equals: .confirmationCode)
                .onSubmit {
                    if isConfirmationValid {
                        handleConfirmation(for: email)
                    }
                }

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
                .background(AuthTheme.primaryButtonBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .foregroundStyle(AuthTheme.primaryButtonForeground)
            }
            .buttonStyle(.plain)
            .disabled(!isConfirmationValid || isConfirming)
            .animation(nil, value: isConfirming)
            .animation(nil, value: isConfirmationValid)
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
                focusedField = .confirmationCode
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

private enum Field: Hashable {
    case email
    case password
    case confirmPassword
    case confirmationCode
}

#Preview {
    SignupView()
        .environmentObject(AuthManager())
}
