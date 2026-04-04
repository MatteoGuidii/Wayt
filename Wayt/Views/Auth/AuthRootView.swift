import SwiftUI
import Amplify

struct AuthRootView: View {

    enum Screen {
        case onboarding
        case browsing     // guest mode — map is visible
        case authenticator
    }

    @EnvironmentObject private var authState: AuthState
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var screen: Screen = .onboarding
    /// Once true, MainTabView stays in the tree forever — auth overlays on top.
    @State private var hasEnteredBrowsing = false
    /// Once true, auth form stays in the tree so form state is never lost.
    @State private var hasShownAuthenticator = false

    var body: some View {
        ZStack {
            // MainTabView persists once entered — never destroyed by auth overlay
            if hasEnteredBrowsing {
                MainTabView()
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }

            // Onboarding — always in tree once created, hidden via opacity to avoid
            // destroying state if user swipes back quickly.
            if !hasCompletedOnboarding {
                OnboardingView(
                    onGetStarted: {
                        hasCompletedOnboarding = true
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                            hasEnteredBrowsing = true
                            screen = .browsing
                        }
                    },
                    onLogIn: {
                        hasShownAuthenticator = true
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                            screen = .authenticator
                        }
                    }
                )
                .zIndex(1)
                .opacity(screen == .onboarding ? 1 : 0)
                .allowsHitTesting(screen == .onboarding)
                .animation(.easeOut(duration: 0.3), value: screen)
            }

            if hasShownAuthenticator {
                authenticatorView
                    .zIndex(2)
                    .opacity(screen == .authenticator ? 1 : 0)
                    .allowsHitTesting(screen == .authenticator)
                    .accessibilityHidden(screen != .authenticator)
                    .animation(.easeOut(duration: 0.3), value: screen)
            }
        }
        .onChange(of: screen) { _, newScreen in
            if newScreen != .authenticator {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
        }
        .onAppear {
            // Skip onboarding if user already passed it or is signed in
            if authState.isSignedIn || hasCompletedOnboarding {
                hasEnteredBrowsing = true
                screen = .browsing
            }

            // Let any child trigger sign-in from guest mode
            authState.onRequestSignIn = { [self] in
                hasShownAuthenticator = true
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                    screen = .authenticator
                }
            }
        }
        .task {
            await authState.checkCurrentSession()
            if authState.isSignedIn {
                hasCompletedOnboarding = true
                hasEnteredBrowsing = true
                screen = .browsing
            }
        }
    }

    // MARK: - Authenticator

    private var authenticatorView: some View {
        ZStack {
            WaytTheme.backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Back button
                HStack {
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            hasEnteredBrowsing = true
                            screen = .browsing
                        }
                        authState.triggerVenueRestore()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                                .font(WaytTheme.bodyBoldFont)
                            Text("Back")
                                .font(WaytTheme.bodyFont)
                        }
                        .foregroundStyle(WaytTheme.mapsBlue.opacity(0.8))
                    }
                    .padding(.leading, 20)
                    .padding(.top, 8)

                    Spacer()
                }

                // Header collapses on keyboard via GeometryReader keyboard height
                AuthHeaderView()

                // Isolated container — never re-renders from parent state changes
                AuthFlowContainer(isVisible: screen == .authenticator, onSignedIn: { username in
                    authState.didSignIn(username: username)
                    hasCompletedOnboarding = true
                    hasEnteredBrowsing = true
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                        screen = .browsing
                    }
                    authState.triggerVenueRestore()
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
            WaytLogomark(size: 64)

            Text("Wayt")
                .font(WaytTheme.displayFont)
                .foregroundStyle(WaytTheme.primaryText)

            Text("Know before you go.")
                .font(WaytTheme.subtitleFont)
                .foregroundStyle(WaytTheme.secondaryText)
        }
        .padding(.top, 12)
        .padding(.bottom, 4)
        .frame(maxHeight: keyboardVisible ? 0 : nil)
        .clipped()
        .opacity(keyboardVisible ? 0 : 1)
        .animation(.easeOut(duration: 0.15), value: keyboardVisible)
        .onReceive(
            NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
        ) { _ in keyboardVisible = true }
        .onReceive(
            NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
        ) { _ in keyboardVisible = false }
    }
}

// MARK: - Auth Flow Container (isolated)

/// Wraps the custom auth forms in its own View struct so it is never
/// invalidated by unrelated state changes in the parent (keyboard, screen, etc.).
private struct AuthFlowContainer: View {
    var isVisible: Bool
    var onSignedIn: (String) -> Void

    @StateObject private var viewModel = AuthFlowViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                switch viewModel.step {
                case .signIn:
                    SignInFormView(viewModel: viewModel)
                case .signUp:
                    SignUpFormView(viewModel: viewModel)
                case .confirmSignUp:
                    ConfirmSignUpFormView(viewModel: viewModel)
                case .forgotPassword:
                    ForgotPasswordFormView(viewModel: viewModel)
                case .confirmResetPassword:
                    ConfirmResetPasswordFormView(viewModel: viewModel)
                }
                Spacer(minLength: 40)
            }
            .animation(.easeInOut(duration: 0.2), value: viewModel.step)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            viewModel.onSignedIn = onSignedIn
        }
        .onChange(of: isVisible) { _, visible in
            if visible { viewModel.reset() }
        }
    }
}

// MARK: - Preview

#Preview("Sign In Screen") {
    ZStack {
        WaytTheme.backgroundGradient
            .ignoresSafeArea()

        VStack(spacing: 0) {
            // Back button
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(WaytTheme.bodyBoldFont)
                    Text("Back")
                        .font(WaytTheme.bodyFont)
                }
                .foregroundStyle(WaytTheme.mapsBlue.opacity(0.8))
                .padding(.leading, 20)
                .padding(.top, 8)

                Spacer()
            }

            // Header
            VStack(spacing: 8) {
                WaytLogomark(size: 64)

                Text("Wayt")
                    .font(WaytTheme.displayFont)
                    .foregroundStyle(WaytTheme.primaryText)

                Text("Know before you go.")
                    .font(WaytTheme.subtitleFont)
                    .foregroundStyle(WaytTheme.secondaryText)
            }
            .padding(.top, 12)
            .padding(.bottom, 4)

            // Mock sign-in form
            VStack(alignment: .leading, spacing: 16) {
                Text("Sign In")
                    .font(WaytTheme.heroFont)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Email").font(WaytTheme.subtitleFont)
                    TextField("Enter your email", text: .constant(""))
                        .textFieldStyle(.plain)
                        .padding(14)
                        .background(WaytTheme.fieldBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Password").font(WaytTheme.subtitleFont)
                    SecureField("Enter your password", text: .constant(""))
                        .textFieldStyle(.plain)
                        .padding(14)
                        .background(WaytTheme.fieldBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button {} label: {
                    Text("Sign In")
                        .font(WaytTheme.calloutBoldFont)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(WaytTheme.mapsBlue)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding(.top, 8)

                HStack {
                    Text("Forgot password?")
                        .foregroundStyle(WaytTheme.mapsBlue)
                    Spacer()
                    Text("Create account")
                        .foregroundStyle(WaytTheme.mapsBlue)
                }
                .font(WaytTheme.subtitleFont)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            Spacer()
        }
    }
}
