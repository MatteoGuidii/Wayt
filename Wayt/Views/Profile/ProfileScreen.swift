import Amplify
import AWSCognitoAuthPlugin
import os
import PhotosUI
import SwiftUI
import UIKit

struct ProfileScreen: View {

    @EnvironmentObject private var authState: AuthState
    @EnvironmentObject private var viewModel: ProfileViewModel
    @EnvironmentObject private var savedVenuesVM: SavedVenuesViewModel
    @EnvironmentObject private var tabSelection: TabSelection
    @EnvironmentObject private var mapViewModel: MapViewModel
    @State private var showEditSheet = false
    @State private var showPhotoPicker = false
    @State private var showImagePreview = false
    @State private var showFirstTimeNameSheet = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var pulsePhase: CGFloat = 0

    var body: some View {
        NavigationStack {
            if authState.isSignedIn {
                signedInContent
            } else {
                guestContent
            }
        }
        .foregroundStyle(WaytTheme.primaryText)
        .task(id: authState.username ?? "") {
            if authState.isSignedIn {
                async let profileLoad: () = viewModel.loadProfile()
                async let venuesLoad: () = savedVenuesVM.loadSavedVenues()
                _ = await (profileLoad, venuesLoad)
                if viewModel.showFirstTimeNamePrompt {
                    showFirstTimeNameSheet = true
                }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            ProfileEditSheet(isFirstTime: false)
                .environmentObject(viewModel)
                .environmentObject(authState)
        }
        .sheet(isPresented: $showFirstTimeNameSheet) {
            ProfileEditSheet(isFirstTime: true)
                .environmentObject(viewModel)
                .environmentObject(authState)
        }
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $selectedPhotoItem,
            matching: .images,
            photoLibrary: .shared()
        )
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            selectedPhotoItem = nil
            Task { await processAndUploadPhoto(newItem) }
        }
        .fullScreenCover(isPresented: $showImagePreview) {
            profileImagePreview
        }
    }

    // MARK: - Guest Content

    private var guestContent: some View {
        ZStack {
            WaytTheme.backgroundGradient
                .ignoresSafeArea()

            // Decorative floating circles
            floatingDecor

            ScrollView {
                VStack(spacing: 28) {
                    Spacer().frame(height: 20)

                    WaytLogomark(size: 100)

                    VStack(spacing: 8) {
                        Text("Join the community!")
                            .font(WaytTheme.largeTitleFont)

                        Text("Be part of the community that\nknows where to go.")
                            .font(WaytTheme.bodyFont)
                            .foregroundStyle(WaytTheme.secondaryText)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                    }

                    // Value props
                    VStack(spacing: 0) {
                        guestPerk(
                            icon: "megaphone.fill",
                            color: WaytTheme.skyPunch,
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
                    .background(WaytTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: WaytTheme.cardShadow, radius: 10, x: 0, y: 4)
                    .padding(.horizontal, 20)

                    // CTA
                    Button {
                        authState.requestSignIn()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "person.badge.plus")
                                .font(WaytTheme.bodyBoldFont)
                            Text("Get started")
                                .font(WaytTheme.calloutBoldFont)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [WaytTheme.skyPunch, WaytTheme.ultraBlue],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(Capsule())
                        .shadow(color: WaytTheme.skyPunch.opacity(0.35), radius: 12, y: 6)
                    }
                    .padding(.horizontal, 32)

                    Text("Version \(appVersion)")
                        .font(WaytTheme.captionFont)
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
                    .font(WaytTheme.bodyBoldFont)
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(WaytTheme.subheadFont)
                Text(subtitle)
                    .font(WaytTheme.captionLightFont)
                    .foregroundStyle(WaytTheme.secondaryText)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Signed-In Content

    private var signedInContent: some View {
        let displayName = viewModel.displayName ?? authState.displayName ?? "User"
        let rank = UserRank.from(reports: viewModel.totalReports)

        return ZStack {
            WaytTheme.backgroundGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    // Hero header
                    profileHero(displayName: displayName, rank: rank)

                    // Stats
                    statsStrip(rank: rank)

                    // Rank progress
                    rankCard(rank: rank)

                    // Saved venues
                    if !savedVenuesVM.savedVenues.isEmpty {
                        savedVenuesCard
                    }

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
    }

    // MARK: - Hero Header

    private func profileHero(displayName: String, rank: UserRank) -> some View {
        VStack(spacing: 0) {
            // Signal Pulse Banner
            ZStack {
                // Dark base with rank-tinted gradient
                LinearGradient(
                    colors: [
                        WaytTheme.signalPulseBase,
                        rank.color.opacity(0.35),
                        WaytTheme.signalPulseBase
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // Orbital contour lines (static)
                GeometryReader { geo in
                    let cx = geo.size.width * 0.5
                    let cy = geo.size.height + 20

                    ForEach(0..<3, id: \.self) { i in
                        let radius = CGFloat(i) * 44 + 40
                        Ellipse()
                            .stroke(
                                rank.color.opacity(0.14 + Double(i) * 0.04),
                                lineWidth: 1.2
                            )
                            .frame(
                                width: radius * 2.6 + 40,
                                height: radius * 1.2 + 20
                            )
                            .position(x: cx, y: cy)
                    }

                    Ellipse()
                        .stroke(rank.color.opacity(0.18), lineWidth: 1.0)
                        .frame(width: geo.size.width * 0.85, height: 90)
                        .rotationEffect(.degrees(-25))
                        .position(x: cx, y: cy - 35)

                    // Pulsing signal rings — driven by repeating animation
                    ForEach(0..<2, id: \.self) { i in
                        let ringPhase = (pulsePhase + CGFloat(i) * 0.5)
                            .truncatingRemainder(dividingBy: 1.0)
                        let ringSize = 40 + ringPhase * max(geo.size.width, geo.size.height) * 0.8

                        Circle()
                            .stroke(
                                rank.color.opacity(0.4 * (1 - ringPhase)),
                                lineWidth: 1.5 - ringPhase
                            )
                            .frame(width: ringSize, height: ringSize)
                            .position(x: cx, y: cy)
                    }
                }
            }
            .frame(height: 140)
            .onAppear {
                withAnimation(.linear(duration: 5).repeatForever(autoreverses: false)) {
                    pulsePhase = 1.0
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(alignment: .bottom) {
                // Avatar floats half over the banner
                ZStack(alignment: .bottomTrailing) {
                    Button {
                        if viewModel.profileImageUrl != nil {
                            showImagePreview = true
                        } else {
                            showPhotoPicker = true
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(WaytTheme.avatarRing)
                                .frame(width: 100, height: 100)

                            Circle()
                                .fill(WaytTheme.avatarBackground)
                                .frame(width: 92, height: 92)
                                .shadow(color: WaytTheme.cardShadow, radius: 10, y: 4)

                            if let cachedData = viewModel.cachedImageData,
                               let uiImage = UIImage(data: cachedData) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 86, height: 86)
                                    .clipShape(Circle())
                            } else if let imageUrl = viewModel.profileImageUrl,
                               let url = URL(string: imageUrl) {
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 86, height: 86)
                                            .clipShape(Circle())
                                    default:
                                        Text(initials(for: displayName))
                                            .font(WaytTheme.largeTitleFont)
                                            .foregroundStyle(WaytTheme.skyPunch)
                                    }
                                }
                            } else {
                                Text(initials(for: displayName))
                                    .font(WaytTheme.largeTitleFont)
                                    .foregroundStyle(WaytTheme.skyPunch)
                            }
                        }
                        .overlay {
                            if viewModel.isSavingImage {
                                Circle()
                                    .fill(Color.black.opacity(0.4))
                                    .frame(width: 92, height: 92)
                                ProgressView()
                                    .tint(.white)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    // Camera badge
                    Button { showPhotoPicker = true } label: {
                        ZStack {
                            Circle()
                                .fill(WaytTheme.avatarBackground)
                                .frame(width: 34, height: 34)
                            Circle()
                                .fill(WaytTheme.skyPunch)
                                .frame(width: 30, height: 30)
                            Image(systemName: "camera.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .offset(x: 2, y: 2)
                    }
                    .buttonStyle(.plain)
                }
                .offset(y: 46)
            }

            // Name below avatar
            VStack(spacing: 4) {
                Spacer().frame(height: 50)

                HStack(spacing: 6) {
                    Image(systemName: rank.icon)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(rank.color)

                    Text(displayName)
                        .font(WaytTheme.headlineFont)

                    Button { showEditSheet = true } label: {
                        Image(systemName: "pencil.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(WaytTheme.secondaryText)
                    }
                }

                Text(rank.subtitle)
                    .font(WaytTheme.subheadLightFont)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    // MARK: - Stats Strip

    private func statsStrip(rank: UserRank) -> some View {
        HStack(spacing: 0) {
            // Reports
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "megaphone.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(WaytTheme.skyPunch)
                    Text("\(viewModel.totalReports)")
                        .font(WaytTheme.headlineFont)
                }
                Text("reports")
                    .font(WaytTheme.subheadLightFont)
            }
            .frame(maxWidth: .infinity)

            RoundedRectangle(cornerRadius: 1)
                .fill(Color(.separator).opacity(0.25))
                .frame(width: 1, height: 36)

            // Rank
            VStack(spacing: 4) {
                Text("Lv.\(rank.level)")
                    .font(WaytTheme.headlineFont)
                Text("rank")
                    .font(WaytTheme.subheadLightFont)
            }
            .frame(maxWidth: .infinity)

            RoundedRectangle(cornerRadius: 1)
                .fill(Color(.separator).opacity(0.25))
                .frame(width: 1, height: 36)

            // Joined
            VStack(spacing: 4) {
                Text(memberSinceShort)
                    .font(WaytTheme.headlineFont)
                Text("joined")
                    .font(WaytTheme.subheadLightFont)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 16)
        .background(WaytTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: WaytTheme.cardShadow, radius: 6, x: 0, y: 3)
        .padding(.horizontal, 16)
    }

    // MARK: - Rank Progress

    private func rankCard(rank: UserRank) -> some View {
        HStack(spacing: 14) {
            Image(systemName: rank.icon)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(rank.color)
                .frame(width: 48, height: 48)

            // Progress content
            VStack(alignment: .leading, spacing: 10) {
                // Current rank name + report count
                HStack {
                    Text(rank.title)
                        .font(WaytTheme.bodyBoldFont)
                        .foregroundStyle(rank.color)

                    Spacer()

                    if let next = rank.nextRank {
                        Text("\(viewModel.totalReports) of \(next.minReports)")
                            .font(WaytTheme.subheadFont)
                    }
                }

                if let next = rank.nextRank {
                    // Progress bar with rank icons at each end
                    HStack(spacing: 8) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(Color(.systemGray5))
                                    .frame(height: 8)

                                RoundedRectangle(cornerRadius: 5)
                                    .fill(
                                        LinearGradient(
                                            colors: rank.progressBarColors,
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(
                                        width: geo.size.width * rank.progress(reports: viewModel.totalReports),
                                        height: 8
                                    )
                            }
                        }
                        .frame(height: 8)

                        Image(systemName: next.icon)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(next.color.opacity(0.4))
                    }

                    Text("\(next.minReports - viewModel.totalReports) more reports to \(next.title)")
                        .font(WaytTheme.subheadLightFont)
                } else {
                    HStack(spacing: 5) {
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text("Highest rank reached")
                            .font(WaytTheme.captionFont)
                    }
                    .foregroundStyle(rank.color)
                }
            }
        }
        .padding(16)
        .background(WaytTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: WaytTheme.cardShadow, radius: 6, x: 0, y: 3)
        .padding(.horizontal, 16)
    }

    // MARK: - Saved Venues

    @State private var showAllSavedVenues = false

    private var savedVenuesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(WaytTheme.savedOrange)
                Text("Saved Venues")
                    .font(WaytTheme.bodyBoldFont)

                Spacer()

                Text("\(savedVenuesVM.savedVenues.count)")
                    .font(WaytTheme.badgeFont)
                    .foregroundStyle(WaytTheme.savedOrange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(WaytTheme.savedOrange.opacity(0.12))
                    .clipShape(Capsule())
            }

            ForEach(savedVenuesVM.savedVenues.prefix(5)) { venue in
                SavedVenueRow(venue: venue, onTap: {
                    navigateToSavedVenue(venue)
                }, onUnsave: {
                    Task { await savedVenuesVM.toggleSaveById(venue.venueId) }
                })
            }

            if savedVenuesVM.savedVenues.count > 5 {
                Button { showAllSavedVenues = true } label: {
                    HStack(spacing: 6) {
                        Text("See all \(savedVenuesVM.savedVenues.count) saved venues")
                            .font(WaytTheme.subheadFont)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(WaytTheme.mapsBlue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(WaytTheme.mapsBlue.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
        .padding(16)
        .background(WaytTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: WaytTheme.cardShadow, radius: 6, x: 0, y: 3)
        .padding(.horizontal, 16)
        .sheet(isPresented: $showAllSavedVenues) {
            SavedVenuesListView(onNavigate: { venue in
                navigateToSavedVenue(venue)
            })
                .environmentObject(savedVenuesVM)
        }
    }

    private func navigateToSavedVenue(_ venue: SavedVenue) {
        mapViewModel.navigateToCoordinate(venue.coordinate)
        tabSelection.selectedTab = .map
    }

    // MARK: - Quick Actions

    private var actionsCard: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "bell.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.orange)
                Text("Notifications")
                    .font(WaytTheme.subheadFont)
                Spacer()
                Text("Soon")
                    .font(WaytTheme.captionFont)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)

            Divider().padding(.leading, 40)

            HStack {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(WaytTheme.secondaryText)
                Text("Settings")
                    .font(WaytTheme.subheadFont)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
        }
        .background(WaytTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: WaytTheme.cardShadow, radius: 6, x: 0, y: 3)
        .padding(.horizontal, 16)
    }

    // MARK: - Footer

    private var footerCard: some View {
        VStack(spacing: 16) {
            Button {
                Task {
                    let result = await Amplify.Auth.signOut()
                    if let globalResult = result as? AWSCognitoSignOutResult,
                       case .failed = globalResult {
                        Log.auth.error("Sign-out failed")
                    } else {
                        viewModel.reset()
                        savedVenuesVM.reset()
                        authState.didSignOut()
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Sign Out")
                        .font(WaytTheme.subheadFont)
                }
                .foregroundStyle(.red.opacity(0.8))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(WaytTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: WaytTheme.cardShadow, radius: 6, x: 0, y: 3)
            }
            .padding(.horizontal, 16)

            Text("Wayt v\(appVersion)")
                .font(WaytTheme.captionLightFont)
                .foregroundStyle(.quaternary)
                .padding(.bottom, 8)
        }
    }

    // MARK: - Decorative

    private var floatingDecor: some View {
        GeometryReader { geo in
            Circle()
                .fill(WaytTheme.skyPunch.opacity(0.08))
                .frame(width: 200)
                .offset(x: geo.size.width - 80, y: -40)
            Circle()
                .fill(WaytTheme.ultraBlue.opacity(0.06))
                .frame(width: 140)
                .offset(x: -40, y: geo.size.height * 0.4)
            Circle()
                .fill(WaytTheme.skyPunch.opacity(0.05))
                .frame(width: 100)
                .offset(x: geo.size.width * 0.6, y: geo.size.height * 0.7)
        }
    }


    // MARK: - Image Preview

    private var profileImagePreview: some View {
        ZStack {
            Color.black.ignoresSafeArea()
                .onTapGesture { showImagePreview = false }

            if let cachedData = viewModel.cachedImageData,
               let uiImage = UIImage(data: cachedData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(Circle())
                    .padding(40)
            } else if let imageUrl = viewModel.profileImageUrl,
               let url = URL(string: imageUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(Circle())
                            .padding(40)
                    default:
                        ProgressView()
                            .tint(.white)
                    }
                }
            }

            // Close button
            VStack {
                HStack {
                    Spacer()
                    Button { showImagePreview = false } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(20)
                }
                Spacer()
            }
        }
    }

    // MARK: - Photo Processing

    private func processAndUploadPhoto(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let uiImage = UIImage(data: data) else { return }

        // Resize to max 400x400 on the main actor to keep UIKit drawing thread-safe
        let resized: UIImage = await MainActor.run {
            let size = uiImage.size
            let ratio = min(400 / size.width, 400 / size.height)
            if ratio < 1 {
                let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
                let renderer = UIGraphicsImageRenderer(size: newSize)
                return renderer.image { _ in
                    uiImage.draw(in: CGRect(origin: .zero, size: newSize))
                }
            } else {
                return uiImage
            }
        }

        guard let jpegData = resized.jpegData(compressionQuality: 0.7) else { return }
        _ = await viewModel.uploadProfileImage(jpegData)
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

    // Cached formatters to avoid re-creating on every render
    private static let isoFormatterFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM yyyy"
        return f
    }()

    private var memberSinceShort: String {
        let raw = viewModel.memberSince
        guard !raw.isEmpty else { return "--" }
        if let date = Self.isoFormatterFractional.date(from: raw) {
            return Self.displayFormatter.string(from: date)
        }
        if let date = Self.isoFormatter.date(from: raw) {
            return Self.displayFormatter.string(from: date)
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
        case .localGuide: return "A true Wayt expert"
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
        case .newbie:     return WaytTheme.rankGreen
        case .explorer:   return WaytTheme.skyPunch
        case .scout:      return WaytTheme.rankOrange
        case .localGuide: return WaytTheme.rankPurple
        case .legend:     return WaytTheme.rankGold
        }
    }

    var progressBarColors: [Color] {
        switch self {
        case .newbie:     return [color.opacity(0.4), color.opacity(0.6), color.opacity(0.5)]
        case .explorer:   return [WaytTheme.skyPunch.opacity(0.5), WaytTheme.skyPunch.opacity(0.7), WaytTheme.mapsBlue.opacity(0.6)]
        case .scout:      return [color.opacity(0.4), color.opacity(0.6), Color.red.opacity(0.45)]
        case .localGuide: return [color.opacity(0.4), color.opacity(0.55), Color.indigo.opacity(0.45)]
        case .legend:     return [color.opacity(0.5), Color.orange.opacity(0.5), Color.red.opacity(0.45)]
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
        .environmentObject(SavedVenuesViewModel())
        .environmentObject(TabSelection())
        .environmentObject(MapViewModel())
}

#Preview("Profile - Signed In") {
    let auth = AuthState()
    auth.didSignIn(username: "Matteo")
    return ProfileScreen()
        .environmentObject(auth)
        .environmentObject(ProfileViewModel())
        .environmentObject(SavedVenuesViewModel())
        .environmentObject(TabSelection())
        .environmentObject(MapViewModel())
}
