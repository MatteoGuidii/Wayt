//
//  LoginView.swift
//  zyvo
//
//  Created by Matteo Guidi on 2025-11-12.
//

import SwiftUI

struct LoginView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: AuthManager
    @State private var email = ""
    @State private var password = ""
    @State private var statusMessage: String?
    @State private var isSubmitting = false
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
                        .textContentType(.password)
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

                Button(action: handleLogin) {
                    Group {
                        if isSubmitting {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                        } else {
                            Text("Log In")
                        }
                    }
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .foregroundStyle(.white)
                }
                .disabled(!isFormValid || isSubmitting)
                .padding(.horizontal, 32)

                Spacer()
            }
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthManager())
}

private extension LoginView {
    var isFormValid: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !password.isEmpty
    }

    func handleLogin() {
        guard !isSubmitting else { return }
        statusMessage = nil
        isSubmitting = true

        Task {
            do {
                let didSignIn = try await authManager.signIn(email: email, password: password)
                if !didSignIn {
                    await MainActor.run {
                        statusMessage = authManager.infoMessage ?? "Additional steps required."
                    }
                }
            } catch {
                await MainActor.run {
                    statusMessage = error.localizedDescription
                }
            }
            await MainActor.run {
                isSubmitting = false
                if authManager.isSignedIn {
                    dismiss()
                }
            }
        }
    }
}
