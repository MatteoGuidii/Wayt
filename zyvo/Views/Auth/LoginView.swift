//
//  LoginView.swift
//  zyvo
//
//  Created by Matteo Guidi on 2025-11-12.
//

import SwiftUI

struct LoginView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
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

                Button(action: {
                    // Handle login action
                }) {
                    Text("Log In")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 32)

                Spacer()
            }
        }
    }
}

#Preview {
    LoginView()
}
