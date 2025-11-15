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
                MainMapView(username: username) {
                    Task {
                        await authManager.signOut()
                    }
                }
            case .loading:
                AuthGradientBackground {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                }
            case .signedOut:
                AuthGradientBackground {
                    landingContent
                }
            }
        }
        .fullScreenCover(item: $destination) { destination in
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
                Button {
                    destination = .signup
                } label: {
                    Text("Sign Up")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(AuthTheme.secondaryButtonBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .foregroundStyle(AuthTheme.secondaryButtonForeground)
                }
                .buttonStyle(.plain)

                Button {
                    destination = .login
                } label: {
                    Text("Log In")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(AuthTheme.primaryButtonBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .foregroundStyle(AuthTheme.primaryButtonForeground)
                }
                .buttonStyle(.plain)
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
