//
//  SignupView.swift
//  zyvo
//
//  Created by Matteo Guidi on 2025-11-12.
//

import SwiftUI

struct SignupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""

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
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.leading)

                    Spacer()
                }

                AuthHeaderView()

                VStack(spacing: 16) {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .padding()
                        .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .foregroundStyle(.white)

                    SecureField("Password", text: $password)
                        .textContentType(.newPassword)
                        .padding()
                        .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .foregroundStyle(.white)

                    SecureField("Confirm Password", text: $confirmPassword)
                        .textContentType(.newPassword)
                        .padding()
                        .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 24)

                Button(action: {
                    // Handle signup action
                }) {
                    Text("Create Account")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .foregroundStyle(.black)
                }
                .padding(.horizontal, 32)

                Spacer()
            }
        }
    }
}

#Preview {
    SignupView()
}
