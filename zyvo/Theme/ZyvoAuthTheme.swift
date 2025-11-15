//
//  ZyvoAuthTheme.swift
//  zyvo
//
//  Created by Matteo Guidi on 2025-11-14.
//

import SwiftUI
import Authenticator

enum ZyvoAuthTheme {
    // MARK: - Colors
    
    static let backgroundGradient = LinearGradient(
        colors: [.purple.opacity(0.3), .blue.opacity(0.3)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    // MARK: - Authenticator Theme
    
    static func createCustomTheme() -> AuthenticatorTheme {
        let theme = AuthenticatorTheme()
        
        // Colors - these apply throughout the Authenticator
        theme.colors.background.primary = Color.clear
        theme.colors.background.interactive = Color.black.opacity(0.85)
        theme.colors.foreground.interactive = Color.white
        theme.colors.border.primary = Color.black.opacity(0.12)
        theme.colors.border.interactive = Color.black.opacity(0.12)
        
        // Authenticator container
        theme.components.authenticator.spacing.vertical = 24
        theme.components.authenticator.cornerRadius = 20
        theme.components.authenticator.backgroundColor = Color.clear
        theme.components.authenticator.padding = .init(
            top: 20,
            bottom: 20,
            trailing: 32,
            leading: 32
        )
        
        // Buttons
        theme.components.button.primary.cornerRadius = 18
        theme.components.button.primary.padding = 20
        theme.components.button.link.font = .subheadline
        
        // Input Fields
        theme.components.field.spacing.vertical = 16
        theme.components.field.cornerRadius = 16
        theme.components.field.backgroundColor = Color.white.opacity(0.92)
        theme.components.field.padding = .init(
            top: 14,
            bottom: 14,
            trailing: 18,
            leading: 18
        )
        
        return theme
    }
    
    // MARK: - Header View
    
    static var headerView: some View {
        VStack(spacing: 12) {
            Text("Zyvo")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            
            Text("Simplest way to get started. Sign in or create an account.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 24)
        }
        .padding(.top, 20)
    }
}
