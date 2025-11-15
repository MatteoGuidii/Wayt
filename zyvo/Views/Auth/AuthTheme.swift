//
//  AuthTheme.swift
//  zyvo
//
//  Created by Matteo Guidi on 2025-11-12.
//

import SwiftUI

enum AuthTheme {
    static let backgroundGradient = LinearGradient(
        colors: [.purple.opacity(0.3), .blue.opacity(0.3)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let inputFieldBackground = Color.white.opacity(0.92)
    static let inputBorderColor = Color.black.opacity(0.12)
    static let inputTextColor = Color.black.opacity(0.85)
    static let placeholderColor = Color.black.opacity(0.55)
    static let inputShadowColor = Color.black.opacity(0.08)

    static let primaryButtonBackground = Color.black.opacity(0.85)
    static let primaryButtonForeground = Color.white
    static let secondaryButtonBackground = Color.white.opacity(0.9)
    static let secondaryButtonForeground = Color.black
}

struct AuthGradientBackground<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            AuthTheme.backgroundGradient
                .ignoresSafeArea()
            content()
        }
    }
}

private struct AuthInputFieldModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AuthTheme.inputFieldBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(AuthTheme.inputBorderColor, lineWidth: 1)
            )
            .shadow(color: AuthTheme.inputShadowColor, radius: 10, x: 0, y: 6)
    }
}

extension View {
    func authInputFieldStyle() -> some View {
        modifier(AuthInputFieldModifier())
    }
}
