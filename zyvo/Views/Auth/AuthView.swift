//
//  AuthView.swift
//  zyvo
//
//  Created by Matteo Guidi on 2025-11-12.
//

import SwiftUI

struct AuthView: View {
    @State private var destination: AuthDestination?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.purple.opacity(0.3), .blue.opacity(0.3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                AuthHeaderView()

                VStack(spacing: 16) {
                    Button("Sign Up") {
                        destination = .signup
                    }
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .foregroundStyle(.black)

                    Button("Log In") {
                        destination = .login
                    }
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
        .sheet(item: $destination) { destination in
            switch destination {
            case .signup:
                SignupView()
            case .login:
                LoginView()
            }
        }
    }
}

private enum AuthDestination: String, Identifiable {
    case login
    case signup

    var id: String { rawValue }
}

#Preview {
    AuthView()
}
