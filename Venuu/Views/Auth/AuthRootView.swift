import SwiftUI
import Amplify
import Authenticator

struct AuthRootView: View {

    enum Screen {
        case onboarding
        case browsing     // guest mode — map is visible
        case authenticator
    }

    @EnvironmentObject private var authState: AuthState
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var screen: Screen = .onboarding

    var body: some View {
        ZStack {
            switch screen {
            case .onboarding:
                OnboardingView(
                    onGetStarted: {
                        hasCompletedOnboarding = true
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                            screen = .browsing
                        }
                    },
                    onLogIn: {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                            screen = .authenticator
                        }
                    }
                )
                .transition(.opacity.combined(with: .move(edge: .leading)))

            case .browsing:
                MainTabView()
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))

            case .authenticator:
                authenticatorView
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .onAppear {
            // Skip onboarding if user already passed it or is signed in
            if authState.isSignedIn || hasCompletedOnboarding {
                screen = .browsing
            }

            // Let any child trigger sign-in from guest mode
            authState.onRequestSignIn = { [self] in
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                    screen = .authenticator
                }
            }
        }
        .task {
            await authState.checkCurrentSession()
            if authState.isSignedIn {
                hasCompletedOnboarding = true
                screen = .browsing
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
                            screen = .browsing
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Back")
                                .font(.system(size: 16, weight: .medium))
                        }
                        .foregroundStyle(VenuuTheme.mapsBlue.opacity(0.8))
                    }
                    .padding(.leading, 20)
                    .padding(.top, 8)

                    Spacer()
                }

                // Header collapses on keyboard via GeometryReader keyboard height
                AuthHeaderView()

                // Isolated Authenticator — never re-renders from parent state changes
                AuthenticatorContainer(onSignedIn: { username in
                    authState.didSignIn(username: username)
                    hasCompletedOnboarding = true
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                        screen = .browsing
                    }
                })
            }
        }
    }

}

// MARK: - Header (self-contained keyboard awareness)

/// Isolated view — owns its own keyboard state so parent never re-renders.
private struct AuthHeaderView: View {
    @State private var keyboardVisible = false

    var body: some View {
        VStack(spacing: 8) {
            VenuuMascot(size: 80, expression: .looking, animated: false)

            Text("Venuu")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(VenuuTheme.mapsBlue)

            Text("Know before you go.")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(VenuuTheme.mapsBlue.opacity(0.7))
        }
        .padding(.top, 12)
        .padding(.bottom, 4)
        .frame(maxHeight: keyboardVisible ? 0 : nil)
        .clipped()
        .opacity(keyboardVisible ? 0 : 1)
        .animation(.easeOut(duration: 0.2), value: keyboardVisible)
        .onReceive(
            NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
        ) { _ in keyboardVisible = true }
        .onReceive(
            NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
        ) { _ in keyboardVisible = false }
    }
}

// MARK: - Authenticator Container (isolated)

/// Wraps Amplify's Authenticator in its own View struct so it is never
/// invalidated by unrelated state changes in the parent (keyboard, screen, etc.).
private struct AuthenticatorContainer: View {
    var onSignedIn: (String) -> Void

    var body: some View {
        Authenticator { state in
            Color.clear
                .onAppear {
                    onSignedIn(state.user.username)
                }
        }
        .authenticatorTheme(Self.theme)
    }

    private static let theme: AuthenticatorTheme = {
        var t = AuthenticatorTheme()

        t.colors.background.primary   = .clear
        t.colors.background.secondary = .clear
        t.colors.background.tertiary  = .clear
        t.components.authenticator.backgroundColor = .clear

        t.components.field.backgroundColor = Color.white.opacity(0.92)
        t.components.field.cornerRadius = 12

        t.colors.background.interactive = VenuuTheme.skyPunch
        t.colors.foreground.interactive = VenuuTheme.skyPunch

        t.components.button.primary.cornerRadius = 16
        t.components.button.primary.padding = 16

        return t
    }()
}

// MARK: - Preview

#Preview("Sign In Screen") {
    ZStack {
        VenuuTheme.backgroundGradient
            .ignoresSafeArea()

        VStack(spacing: 0) {
            // Back button
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Back")
                        .font(.system(size: 16, weight: .medium))
                }
                .foregroundStyle(VenuuTheme.mapsBlue.opacity(0.8))
                .padding(.leading, 20)
                .padding(.top, 8)

                Spacer()
            }

            // Header
            VStack(spacing: 8) {
                VenuuMascot(size: 80, expression: .looking, animated: false)

                Text("Venuu")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(VenuuTheme.mapsBlue)

                Text("Know before you go.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(VenuuTheme.mapsBlue.opacity(0.7))
            }
            .padding(.top, 12)
            .padding(.bottom, 4)

            // Mock sign-in form
            VStack(alignment: .leading, spacing: 16) {
                Text("Sign In")
                    .font(.system(size: 28, weight: .bold))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Email").font(.system(size: 15, weight: .medium))
                    TextField("Enter your email", text: .constant(""))
                        .textFieldStyle(.plain)
                        .padding(14)
                        .background(Color.white.opacity(0.92))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Password").font(.system(size: 15, weight: .medium))
                    SecureField("Enter your password", text: .constant(""))
                        .textFieldStyle(.plain)
                        .padding(14)
                        .background(Color.white.opacity(0.92))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button {} label: {
                    Text("Sign In")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(VenuuTheme.skyPunch)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding(.top, 8)

                HStack {
                    Text("Forgot password?")
                        .foregroundStyle(VenuuTheme.skyPunch)
                    Spacer()
                    Text("Create account")
                        .foregroundStyle(VenuuTheme.skyPunch)
                }
                .font(.system(size: 15, weight: .medium))
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            Spacer()
        }
    }
}
