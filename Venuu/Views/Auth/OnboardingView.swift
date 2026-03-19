import SwiftUI

// MARK: - Onboarding (Welcome Flow)

/// Waze-inspired onboarding with swipeable pages, mascot illustrations,
/// and "Get Started" / "I already have an account" CTAs.
struct OnboardingView: View {

    let onGetStarted: () -> Void
    let onLogIn: () -> Void

    @State private var currentPage = 0
    @State private var appeared = false

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            expression: .looking,
            headline: "Know before you go",
            subtitle: "See how busy any venue is — right now. No more guessing, no more wasted trips.",
            accentIcon: "eye.fill"
        ),
        OnboardingPage(
            expression: .excited,
            headline: "Real-time crowd intel",
            subtitle: "Live busyness levels from real people on the ground. Updated every few minutes.",
            accentIcon: "waveform.path.ecg"
        ),
        OnboardingPage(
            expression: .proud,
            headline: "Help your community",
            subtitle: "Drop a quick report when you're at a venue. It takes 5 seconds and helps everyone.",
            accentIcon: "hand.thumbsup.fill"
        ),
    ]

    var body: some View {
        ZStack {
            // Animated background
            backgroundView

            VStack(spacing: 0) {
                Spacer()
                    .frame(height: 60)

                // Swipeable pages
                TabView(selection: $currentPage) {
                    ForEach(pages.indices, id: \.self) { index in
                        pageView(pages[index])
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(maxHeight: .infinity)

                // Page indicator
                pageIndicator
                    .padding(.bottom, 32)

                // CTAs
                ctaButtons
                    .padding(.horizontal, 32)
                    .padding(.bottom, 16)

                // Terms
                termsText
                    .padding(.bottom, 32)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                appeared = true
            }
        }
    }

    // MARK: - Background

    private var backgroundView: some View {
        ZStack {
            VenuuTheme.backgroundGradient
                .ignoresSafeArea()

            // Decorative floating circles
            Circle()
                .fill(VenuuTheme.skyPunch.opacity(0.10))
                .frame(width: 300, height: 300)
                .offset(x: -120, y: -280)
                .blur(radius: 40)

            Circle()
                .fill(VenuuTheme.skyPunch.opacity(0.06))
                .frame(width: 250, height: 250)
                .offset(x: 150, y: 200)
                .blur(radius: 40)
        }
    }

    // MARK: - Page Content

    private func pageView(_ page: OnboardingPage) -> some View {
        VStack(spacing: 24) {
            Spacer()

            // Mascot
            ZStack {
                VenuuMascot(size: 140, expression: page.expression)

                // Small floating icon badge
                Image(systemName: page.accentIcon)
                    .font(VenuuTheme.iconLargeFont)
                    .foregroundStyle(VenuuTheme.skyPunch)
                    .padding(12)
                    .background(
                        Circle()
                            .fill(.ultraThinMaterial)
                            .shadow(color: VenuuTheme.skyPunch.opacity(0.2), radius: 8, y: 2)
                    )
                    .offset(x: 65, y: -50)
            }

            VStack(spacing: 12) {
                Text(page.headline)
                    .font(VenuuTheme.heroFont)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)

                Text(page.subtitle)
                    .font(VenuuTheme.bodyFont)
                    .foregroundStyle(VenuuTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 24)
            }

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Page Indicator

    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(pages.indices, id: \.self) { index in
                Capsule()
                    .fill(index == currentPage ? VenuuTheme.skyPunch : Color.gray.opacity(0.3))
                    .frame(width: index == currentPage ? 24 : 8, height: 8)
                    .animation(.spring(response: 0.35), value: currentPage)
            }
        }
    }

    // MARK: - CTA Buttons

    private var ctaButtons: some View {
        VStack(spacing: 14) {
            // Primary CTA
            Button(action: onGetStarted) {
                Text("Get started")
                    .font(VenuuTheme.title3Font)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(VenuuTheme.skyPunch)
                    .clipShape(Capsule())
                    .shadow(color: VenuuTheme.skyPunch.opacity(0.35), radius: 12, y: 6)
            }
            .scaleEffect(appeared ? 1 : 0.9)
            .opacity(appeared ? 1 : 0)

            // Secondary CTA
            Button(action: onLogIn) {
                Text("I already have an account")
                    .font(VenuuTheme.bodyFont)
                    .foregroundStyle(VenuuTheme.skyPunch)
            }
            .opacity(appeared ? 1 : 0)
        }
    }

    // MARK: - Terms

    private var termsText: some View {
        Text("By continuing you agree to Venuu's\nTerms of Service and Privacy Policy")
            .font(VenuuTheme.captionLightFont)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
    }
}

// MARK: - Page Model

private struct OnboardingPage {
    let expression: VenuuMascot.Expression
    let headline: String
    let subtitle: String
    let accentIcon: String
}

#Preview("Onboarding") {
    OnboardingView(onGetStarted: {}, onLogIn: {})
}
