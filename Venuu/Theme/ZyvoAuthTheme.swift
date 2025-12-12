//
//  ZyvoAuthTheme.swift
//  Venuu
//
//  Created by Matteo Guidi on 2025-11-14.
//

import SwiftUI
import Authenticator

enum ZyvoAuthTheme {
    // MARK: - Colors

    static let backgroundGradient = LinearGradient(
        colors: [
            Color.purple.opacity(0.45),
            Color.blue.opacity(0.55)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - Authenticator Theme

    static let authenticatorTheme: AuthenticatorTheme = {
        var theme = AuthenticatorTheme()

        // Entire Authenticator background → fully transparent
        theme.colors.background.primary = .clear
        theme.components.authenticator.backgroundColor = .clear
        
        // Section backgrounds (Sign In, Confirm Sign Up, Forgot Password)
        theme.colors.background.secondary = .clear
        theme.colors.background.tertiary = .clear

        // Remove default tinting
        theme.colors.background.interactive = .clear
        theme.colors.border.primary = .clear
        theme.colors.border.interactive = .clear

        // Adjust spacing and container style
        theme.components.authenticator.spacing.vertical = 16
        theme.components.authenticator.cornerRadius = 0
        theme.components.field.padding = .init(
            top: 12,
            bottom: 12,
            trailing: 14,
            leading: 14
        )

        // Input fields
        theme.components.field.backgroundColor = Color.white.opacity(0.90)
        theme.components.field.cornerRadius = 12

        // Buttons
        theme.components.button.primary.cornerRadius = 18
        theme.components.button.primary.padding = 18
        
        return theme
    }()


    // MARK: - Header View

    static var headerView: some View {
        VStack(spacing: 12) {
            Text("Venuu")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Simplest way to get started. Sign in or create an account.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 24)
        }
        .padding(.top, 32)
        .padding(.bottom, 8)
    }
}
