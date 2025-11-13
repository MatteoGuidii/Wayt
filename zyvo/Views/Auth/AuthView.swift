//
//  AuthView.swift
//  zyvo
//
//  Created by Matteo Guidi on 2025-11-12.
//

import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var authManager: AuthManager
    @State private var destination: AuthDestination?

    var body: some View {
        Group {
            switch authManager.authState {
            case .signedIn(let username):
                WelcomeView(username: username) {
                    Task {
                        await authManager.signOut()
                    }
                }
            case .loading:
                gradientBackground {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                }
            case .signedOut:
                gradientBackground {
                    landingContent
                }
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
        .onChange(of: authManager.authState) { _, newValue in
            if case .signedIn = newValue {
                destination = nil
            }
        }
        .task {
            await authManager.refreshAuthState()
        }
    }
}

private extension AuthView {
    @ViewBuilder
    var landingContent: some View {
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

            if let message = authManager.infoMessage {
                Text(message)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 24)
            }

            Spacer()
        }
    }

    func gradientBackground<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            LinearGradient(
                colors: [.purple.opacity(0.3), .blue.opacity(0.3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            content()
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
        .environmentObject(AuthManager())
}
