//
//  KeyboardInsetModifier.swift
//  zyvo
//
//  Created by Matteo Guidi on 2025-11-15.
//

#if canImport(UIKit)
import SwiftUI
import Combine
import UIKit

/// Adds a temporary bottom inset when the keyboard is visible so controls positioned
/// near the bottom (e.g., input toolbars) do not cover focused form fields.
private struct KeyboardInset: ViewModifier {
    let insetHeight: CGFloat
    @State private var keyboardVisible = false

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom) {
                Color.clear
                    .frame(height: keyboardVisible ? insetHeight : 0)
                    .allowsHitTesting(false)
            }
            .onReceive(keyboardWillShowPublisher) { duration in
                withAnimation(.easeInOut(duration: duration)) {
                    keyboardVisible = true
                }
            }
            .onReceive(keyboardWillHidePublisher) { duration in
                withAnimation(.easeInOut(duration: duration)) {
                    keyboardVisible = false
                }
            }
    }

    /// Extract the animation duration from the keyboard notification so the inset
    /// animates in sync with the keyboard.
    private func animationDuration(from notification: Notification) -> Double {
        notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
    }

    private var keyboardWillShowPublisher: AnyPublisher<Double, Never> {
        NotificationCenter.default
            .publisher(for: UIResponder.keyboardWillShowNotification)
            .map { animationDuration(from: $0) }
            .eraseToAnyPublisher()
    }

    private var keyboardWillHidePublisher: AnyPublisher<Double, Never> {
        NotificationCenter.default
            .publisher(for: UIResponder.keyboardWillHideNotification)
            .map { animationDuration(from: $0) }
            .eraseToAnyPublisher()
    }
}

extension View {
    /// Provides breathing room between the keyboard accessory buttons and the bottom-most field.
    func keyboardAccessoryPadding(_ insetHeight: CGFloat = 72) -> some View {
        modifier(KeyboardInset(insetHeight: insetHeight))
    }
}
#endif
