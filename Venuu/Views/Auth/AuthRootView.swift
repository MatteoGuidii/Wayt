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
    @State private var screen: Screen = .onboarding
    @State private var keyboardVisible = false

    var body: some View {
        ZStack {
            switch screen {
            case .onboarding:
                OnboardingView(
                    onGetStarted: {
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
            // If user is already signed in (returning session), skip onboarding
            if authState.isSignedIn {
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
                        .foregroundStyle(VenuuTheme.steel.opacity(0.8))
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
                    // Amplify says we're signed in — update AuthState and go to map
                    Color.clear
                        .onAppear {
                            authState.didSignIn(username: state.user.username)
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                                screen = .browsing
                            }
                        }
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
                .foregroundStyle(VenuuTheme.steel)

            Text("Know before you go.")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(VenuuTheme.steel.opacity(0.7))
        }
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    // MARK: - Authenticator Theme

    private static let theme: AuthenticatorTheme = {
        var t = AuthenticatorTheme()

        t.colors.background.primary   = .clear
        t.colors.background.secondary = .clear
        t.colors.background.tertiary  = .clear
        t.components.authenticator.backgroundColor = .clear

        t.components.field.backgroundColor = Color.white.opacity(0.92)
        t.components.field.cornerRadius = 12

        t.components.button.primary.cornerRadius = 16
        t.components.button.primary.padding = 16

        return t
    }()
}
