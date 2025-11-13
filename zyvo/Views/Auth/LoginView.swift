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
                        .textContentType(.password)
                        .padding()
                        .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .foregroundStyle(.white)
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
