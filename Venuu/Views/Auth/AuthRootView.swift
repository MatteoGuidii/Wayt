import SwiftUI
import Amplify
import Authenticator

struct AuthRootView: View {

    enum AuthScreen {
        case onboarding
        case signUp
        case signIn
    }

    @State private var screen: AuthScreen = .onboarding
    @State private var keyboardVisible = false

    var body: some View {
        ZStack {
            switch screen {
            case .onboarding:
                OnboardingView(
                    onGetStarted: {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                            screen = .signUp
                        }
                    },
                    onLogIn: {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                            screen = .signIn
                        }
                    }
                )
                .transition(.opacity.combined(with: .move(edge: .leading)))

            case .signUp, .signIn:
                authenticatorView
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
    }

    // MARK: - Authenticator

    private var authenticatorView: some View {
        ZStack {
            VenuuTheme.backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Back button
                HStack {
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            screen = .onboarding
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Back")
                                .font(.system(size: 16, weight: .medium))
                        }
                        .foregroundStyle(.white.opacity(0.9))
                    }
                    .padding(.leading, 20)
                    .padding(.top, 8)

                    Spacer()
                }

                // Compact header with mascot
                headerView
                    .frame(maxHeight: keyboardVisible ? 0 : nil)
                    .clipped()
                    .opacity(keyboardVisible ? 0 : 1)
                    .animation(.easeOut(duration: 0.25), value: keyboardVisible)

                Authenticator { state in
                    MainTabView(
                        username: state.user.username,
                        onSignOut: {
                            Task { await state.signOut() }
                        }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
                .authenticatorTheme(Self.theme)
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
        ) { _ in
            keyboardVisible = true
        }
        .onReceive(
            NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
        ) { _ in
            keyboardVisible = false
        }
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(spacing: 8) {
            VenuuMascot(size: 80, expression: .happy, animated: false)

            Text("Venuu")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Know before you go.")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    // MARK: - Authenticator Theme

    private static let theme: AuthenticatorTheme = {
        var t = AuthenticatorTheme()

        // Transparent backgrounds so gradient shows through
        t.colors.background.primary   = .clear
        t.colors.background.secondary = .clear
        t.colors.background.tertiary  = .clear
        t.components.authenticator.backgroundColor = .clear

        // Input fields
        t.components.field.backgroundColor = Color.white.opacity(0.92)
        t.components.field.cornerRadius = 12

        // Buttons
        t.components.button.primary.cornerRadius = 16
        t.components.button.primary.padding = 16

        return t
    }()
}
