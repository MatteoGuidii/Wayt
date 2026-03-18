import SwiftUI
import Amplify
import AWSCognitoAuthPlugin

struct ProfileScreen: View {

    @EnvironmentObject private var authState: AuthState
    @EnvironmentObject private var viewModel: ProfileViewModel
    @State private var showSignOutConfirm = false
    @State private var mascotExpression: VenuuMascot.Expression = .happy

    var body: some View {
        NavigationStack {
            if authState.isSignedIn {
                signedInContent
            } else {
                guestContent
            }
        }
        .task(id: authState.username ?? "") {
            if authState.isSignedIn {
                await viewModel.loadProfile()
            }
        }
        .task { await cycleMascotExpression() }
    }

    // MARK: - Guest Content

    private var guestContent: some View {
        ZStack {
            VenuuTheme.backgroundGradient
                .ignoresSafeArea()

            // Decorative floating circles
            floatingDecor

            ScrollView {
                VStack(spacing: 28) {
                    Spacer().frame(height: 20)

                    VenuuMascot(size: 130, expression: mascotExpression, animated: true)

                    VStack(spacing: 8) {
                        Text("Join the crew!")
                            .font(VenuuTheme.largeTitleFont)

                        Text("Be part of the community that\nknows where to go.")
                            .font(VenuuTheme.bodyFont)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                    }

                    // Value props
                    VStack(spacing: 0) {
                        guestPerk(
                            icon: "megaphone.fill",
                            color: VenuuTheme.skyPunch,
                            title: "Share the vibe",
                            subtitle: "Report how busy places are"
                        )
                        Divider().padding(.leading, 60)
                        guestPerk(
                            icon: "star.fill",
                            color: .orange,
                            title: "Save your spots",
                            subtitle: "Bookmark favorite venues"
                        )
                        Divider().padding(.leading, 60)
                        guestPerk(
                            icon: "trophy.fill",
                            color: .purple,
                            title: "Level up",
                            subtitle: "Earn ranks as you contribute"
                        )
                    }
                    .padding(.vertical, 4)
                    .background(VenuuTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4)
                    .padding(.horizontal, 20)

                    // CTA
                    Button {
                        authState.requestSignIn()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "person.badge.plus")
                                .font(VenuuTheme.bodyBoldFont)
                            Text("Get started")
                                .font(VenuuTheme.calloutBoldFont)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [VenuuTheme.skyPunch, VenuuTheme.ultraBlue],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(Capsule())
                        .shadow(color: VenuuTheme.skyPunch.opacity(0.35), radius: 12, y: 6)
                    }
                    .padding(.horizontal, 32)

                    Text("Version \(appVersion)")
                        .font(VenuuTheme.captionFont)
                        .foregroundStyle(.tertiary)
                        .padding(.bottom, 24)
                }
            }
            .scrollIndicators(.hidden)
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func guestPerk(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(VenuuTheme.bodyBoldFont)
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(VenuuTheme.subheadFont)
                Text(subtitle)
                    .font(VenuuTheme.captionLightFont)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Signed-In Content

    private var signedInContent: some View {
        let displayName = authState.username ?? "User"
        let rank = UserRank.from(reports: viewModel.totalReports)

        return ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    // Hero header
                    profileHero(displayName: displayName, rank: rank)

                    // Stats cards
                    statsRow(rank: rank)

                    // Rank progress
                    rankCard(rank: rank)

                    // Quick actions
                    actionsCard

                    // Footer
                    footerCard

                    Spacer().frame(height: 12)
                }
            }
            .scrollIndicators(.hidden)
        }
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Sign out of Venuu?",
            isPresented: $showSignOutConfirm,
            titleVisibility: .visible
        ) {
            Button("Sign Out", role: .destructive) {
                Task {
                    let result = await Amplify.Auth.signOut()
                    if let globalResult = result as? AWSCognitoSignOutResult,
                       case .failed = globalResult {
                        print("Sign-out failed")
                    } else {
                        viewModel.reset()
                        authState.didSignOut()
                    }
                }
            }
        }
    }

    // MARK: - Hero Header

    private func profileHero(displayName: String, rank: UserRank) -> some View {
        ZStack {
            // Gradient background
            LinearGradient(
                colors: [VenuuTheme.skyPunch, VenuuTheme.ultraBlue],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Decorative dots
            GeometryReader { geo in
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 120)
                    .offset(x: geo.size.width - 60, y: -30)
                Circle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 80)
                    .offset(x: -20, y: geo.size.height - 50)
            }
        }
        .frame(height: 200)
        .clipShape(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay(alignment: .bottom) {
            // Avatar + name overlay
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 72, height: 72)
                        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)

                    Text(initials(for: displayName))
                        .font(VenuuTheme.heroFont)
                        .foregroundStyle(VenuuTheme.skyPunch)
                }

                Text(displayName)
                    .font(VenuuTheme.title3Font)
                    .foregroundStyle(.white)

                HStack(spacing: 6) {
                    Image(systemName: rank.icon)
                        .font(VenuuTheme.captionFont)
                    Text(rank.title)
                        .font(VenuuTheme.captionFont)
                }
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.2))
                .clipShape(Capsule())
            }
            .padding(.bottom, 16)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    // MARK: - Stats Row

    private func statsRow(rank: UserRank) -> some View {
        HStack(spacing: 12) {
            statCard(
                value: "\(viewModel.totalReports)",
                label: "Reports",
                icon: "megaphone.fill",
                color: VenuuTheme.skyPunch
            )

            statCard(
                value: rank.title,
                label: "Rank",
                icon: rank.icon,
                color: rank.color
            )

            statCard(
                value: memberSinceShort,
                label: "Joined",
                icon: "calendar",
                color: .green
            )
        }
        .padding(.horizontal, 16)
    }

    private func statCard(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(VenuuTheme.subtitleFont)
                    .foregroundStyle(color)
            }

            Text(value)
                .font(VenuuTheme.bodyBoldFont)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(label)
                .font(VenuuTheme.captionLightFont)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(VenuuTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 3)
    }

    // MARK: - Rank Progress Card

    private func rankCard(rank: UserRank) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                VenuuMascot(size: 44, expression: mascotExpression, animated: true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(rank.title)
                        .font(VenuuTheme.sectionFont)
                    Text(rank.subtitle)
                        .font(VenuuTheme.captionLightFont)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("Lv.\(rank.level)")
                    .font(VenuuTheme.titleNumericFont)
                    .foregroundStyle(rank.color)
            }

            // Progress bar
            if let next = rank.nextRank {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("\(viewModel.totalReports) / \(next.minReports) reports")
                            .font(VenuuTheme.captionFont)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("Next: \(next.title)")
                            .font(VenuuTheme.captionFont)
                            .foregroundStyle(next.color)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(.systemGray5))
                                .frame(height: 10)

                            RoundedRectangle(cornerRadius: 6)
                                .fill(
                                    LinearGradient(
                                        colors: rank.progressBarColors,
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(
                                    width: geo.size.width * rank.progress(reports: viewModel.totalReports),
                                    height: 10
                                )
                        }
                    }
                    .frame(height: 10)
                }
            } else {
                Text("You've reached the highest rank!")
                    .font(VenuuTheme.captionFont)
                    .foregroundStyle(rank.color)
            }
        }
        .padding(16)
        .background(VenuuTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(rank.color.opacity(0.2), lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 3)
        .padding(.horizontal, 16)
    }

    // MARK: - Quick Actions

    private var actionsCard: some View {
        VStack(spacing: 0) {
            actionRow(
                icon: "megaphone.fill",
                color: VenuuTheme.skyPunch,
                title: "My Reports",
                subtitle: "\(viewModel.totalReports) submitted"
            )

            Divider().padding(.leading, 60)

            actionRow(
                icon: "bell.fill",
                color: .orange,
                title: "Notifications",
                subtitle: "Coming soon"
            )

            Divider().padding(.leading, 60)

            actionRow(
                icon: "gearshape.fill",
                color: .gray,
                title: "Settings",
                subtitle: "Account & preferences"
            )
        }
        .background(VenuuTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 3)
        .padding(.horizontal, 16)
    }

    private func actionRow(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(VenuuTheme.bodyBoldFont)
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(VenuuTheme.subheadFont)
                Text(subtitle)
                    .font(VenuuTheme.captionLightFont)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(VenuuTheme.captionFont)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Footer

    private var footerCard: some View {
        VStack(spacing: 12) {
            // Sign out
            Button {
                showSignOutConfirm = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(VenuuTheme.subtitleFont)
                    Text("Sign Out")
                        .font(VenuuTheme.subtitleFont)
                }
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.red.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(.horizontal, 16)

            HStack(spacing: 4) {
                Image(systemName: "info.circle")
                    .font(VenuuTheme.captionFont)
                Text("Venuu v\(appVersion)")
                    .font(VenuuTheme.captionFont)
            }
            .foregroundStyle(.tertiary)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Decorative

    private var floatingDecor: some View {
        GeometryReader { geo in
            Circle()
                .fill(VenuuTheme.skyPunch.opacity(0.08))
                .frame(width: 200)
                .offset(x: geo.size.width - 80, y: -40)
            Circle()
                .fill(VenuuTheme.ultraBlue.opacity(0.06))
                .frame(width: 140)
                .offset(x: -40, y: geo.size.height * 0.4)
            Circle()
                .fill(VenuuTheme.skyPunch.opacity(0.05))
                .frame(width: 100)
                .offset(x: geo.size.width * 0.6, y: geo.size.height * 0.7)
        }
    }

    // MARK: - Mascot Expression Cycle

    private static let expressionCycle: [VenuuMascot.Expression] = [
        .happy, .cheerful, .looking, .excited, .wink, .proud, .kind
    ]

    private func cycleMascotExpression() async {
        var index = 0
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { break }
            index = (index + 1) % Self.expressionCycle.count
            withAnimation(.easeInOut(duration: 0.5)) {
                mascotExpression = Self.expressionCycle[index]
            }
        }
    }

    // MARK: - Helpers

    private func initials(for name: String) -> String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var memberSinceShort: String {
        let raw = viewModel.memberSince
        guard !raw.isEmpty else { return "--" }
        // Try parsing ISO date, fall back to raw string
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) {
            let display = DateFormatter()
            display.dateFormat = "MMM yyyy"
            return display.string(from: date)
        }
        // Try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: raw) {
            let display = DateFormatter()
            display.dateFormat = "MMM yyyy"
            return display.string(from: date)
        }
        return String(raw.prefix(7))
    }
}

// MARK: - User Rank System

enum UserRank: Int, CaseIterable {
    case newbie = 1
    case explorer = 2
    case scout = 3
    case localGuide = 4
    case legend = 5

    var title: String {
        switch self {
        case .newbie:     return "Newbie"
        case .explorer:   return "Explorer"
        case .scout:      return "Scout"
        case .localGuide: return "Local Guide"
        case .legend:     return "Legend"
        }
    }

    var subtitle: String {
        switch self {
        case .newbie:     return "Just getting started"
        case .explorer:   return "Curious and on the move"
        case .scout:      return "The community counts on you"
        case .localGuide: return "A true venue expert"
        case .legend:     return "Hall of fame material"
        }
    }

    var icon: String {
        switch self {
        case .newbie:     return "leaf.fill"
        case .explorer:   return "binoculars.fill"
        case .scout:      return "flag.fill"
        case .localGuide: return "star.fill"
        case .legend:     return "trophy.fill"
        }
    }

    var color: Color {
        switch self {
        case .newbie:     return .green
        case .explorer:   return VenuuTheme.skyPunch
        case .scout:      return .orange
        case .localGuide: return .purple
        case .legend:     return Color(red: 1.0, green: 0.84, blue: 0.0)
        }
    }

    var progressBarColors: [Color] {
        switch self {
        case .newbie:     return [Color.green.opacity(0.6), .green, .mint]
        case .explorer:   return [.cyan, VenuuTheme.skyPunch, .blue]
        case .scout:      return [.yellow, .orange, .red]
        case .localGuide: return [.pink, .purple, .indigo]
        case .legend:     return [Color(red: 1.0, green: 0.84, blue: 0.0), .orange, .red]
        }
    }

    var level: Int { rawValue }

    var minReports: Int {
        switch self {
        case .newbie:     return 0
        case .explorer:   return 5
        case .scout:      return 15
        case .localGuide: return 30
        case .legend:     return 60
        }
    }

    var mascotExpression: VenuuMascot.Expression {
        switch self {
        case .newbie:     return .looking
        case .explorer:   return .happy
        case .scout:      return .cheerful
        case .localGuide: return .excited
        case .legend:     return .proud
        }
    }

    var nextRank: UserRank? {
        UserRank(rawValue: rawValue + 1)
    }

    func progress(reports: Int) -> CGFloat {
        guard let next = nextRank else { return 1.0 }
        let range = next.minReports - minReports
        guard range > 0 else { return 1.0 }
        let current = reports - minReports
        return min(1.0, max(0.0, CGFloat(current) / CGFloat(range)))
    }

    static func from(reports: Int) -> UserRank {
        for rank in Self.allCases.reversed() {
            if reports >= rank.minReports { return rank }
        }
        return .newbie
    }
}

// MARK: - Previews

#Preview("Profile - Guest") {
    ProfileScreen()
        .environmentObject(AuthState())
        .environmentObject(ProfileViewModel())
}

#Preview("Profile - Signed In") {
    let auth = AuthState()
    auth.didSignIn(username: "Matteo")
    return ProfileScreen()
        .environmentObject(auth)
        .environmentObject(ProfileViewModel())
}
