import SwiftUI
import Amplify
import Authenticator

struct AuthRootView: View {

    @State private var keyboardVisible = false

    var body: some View {
        ZStack {
            VenuuTheme.backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

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
        VStack(spacing: 10) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 44))
                .foregroundStyle(.white)

            Text("Venuu")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("See how busy places are, right now.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .padding(.top, 32)
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
