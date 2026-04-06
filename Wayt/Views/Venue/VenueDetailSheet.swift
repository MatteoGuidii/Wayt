import SwiftUI
import MapKit

// MARK: - LookAround Cache

/// Caches MKLookAroundScene objects to avoid refetching on every sheet open.
/// Keyed by rounded coordinate string (5-decimal precision ≈ 1m).
@MainActor
final class LookAroundCache {

    static let shared = LookAroundCache()

    private var cache: [String: MKLookAroundScene] = [:]
    /// Coordinates that have no LookAround coverage — avoid re-requesting.
    private var misses = Set<String>()
    private let maxEntries = 80
    private let maxMisses = 200

    private init() {}

    func scene(for coordinate: CLLocationCoordinate2D) -> MKLookAroundScene? {
        cache[key(for: coordinate)]
    }

    func isKnownMiss(for coordinate: CLLocationCoordinate2D) -> Bool {
        misses.contains(key(for: coordinate))
    }

    func store(_ scene: MKLookAroundScene, for coordinate: CLLocationCoordinate2D) {
        if cache.count >= maxEntries {
            let keysToRemove = Array(cache.keys.prefix(maxEntries / 4))
            keysToRemove.forEach { cache.removeValue(forKey: $0) }
        }
        cache[key(for: coordinate)] = scene
    }

    func storeMiss(for coordinate: CLLocationCoordinate2D) {
        if misses.count >= maxMisses {
            misses.removeAll()
        }
        misses.insert(key(for: coordinate))
    }

    private static let posixLocale = Locale(identifier: "en_US_POSIX")

    private func key(for coordinate: CLLocationCoordinate2D) -> String {
        String(format: "%.5f,%.5f", locale: Self.posixLocale, coordinate.latitude, coordinate.longitude)
    }
}

// MARK: - Venue Detail Sheet

struct VenueDetailSheet: View {

    let venue: Venue
    @StateObject private var viewModel: VenueDetailViewModel
    @EnvironmentObject private var authState: AuthState
    @EnvironmentObject private var locationService: LocationService
    @EnvironmentObject private var savedVenuesVM: SavedVenuesViewModel
    @EnvironmentObject private var tabSelection: TabSelection
    @EnvironmentObject private var mapViewModel: MapViewModel
    @EnvironmentObject private var profileViewModel: ProfileViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showAuthGate = false
    @State private var lookAroundScene: MKLookAroundScene?
    @State private var isLoadingLookAround = true
    @State private var showFullLookAround = false
    @State private var showReviewsSheet = false
    @State private var busynessFlashOpacity: Double = 0
    @AppStorage("wayt_distanceUnit") private var distanceUnit: String = "km"
    @State private var sheetOpenTime = Date()
    @State private var didReport = false
    @State private var didSave = false
    @State private var didGetDirections = false

    init(venue: Venue) {
        self.venue = venue
        _viewModel = StateObject(wrappedValue: VenueDetailViewModel(venue: venue))
        if let cached = LookAroundCache.shared.scene(for: venue.coordinate) {
            _lookAroundScene = State(initialValue: cached)
            _isLoadingLookAround = State(initialValue: false)
        } else if LookAroundCache.shared.isKnownMiss(for: venue.coordinate) {
            _isLoadingLookAround = State(initialValue: false)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerSection
                        .padding(.top, -8)
                    atAGlanceSection
                    busynessHeroSection
                    actionsSection
                    lookAroundSection
                }
                .padding(WaytTheme.cardPadding)
            }
            .background(WaytTheme.backgroundGradient)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        if authState.isSignedIn {
                            didSave = true
                            Task { await savedVenuesVM.toggleSave(for: venue) }
                        } else {
                            showAuthGate = true
                        }
                    } label: {
                        Image(systemName: savedVenuesVM.isSaved(venue.id) ? "bookmark.fill" : "bookmark")
                            .foregroundStyle(savedVenuesVM.isSaved(venue.id) ? WaytTheme.savedOrange : WaytTheme.mapsBlue)
                            .font(.title3)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(WaytTheme.mapsBlue)
                            .font(.title3)
                    }
                }
            }
        }
        .task {
            sheetOpenTime = Date()
            let source: String = switch tabSelection.selectedTab {
            case .map: "map_marker"
            case .discover: "discover_list"
            default: "other"
            }
            await AnalyticsService.shared.track(
                .venueView,
                venueId: venue.id,
                venueName: venue.name,
                venueType: venue.category.rawValue,
                lat: venue.coordinate.latitude,
                lng: venue.coordinate.longitude,
                properties: [
                    "source": .string(source),
                    "isOpen": .bool(venue.isOpen ?? true),
                    "busynessLevel": .int(venue.busyness?.rawValue ?? 0),
                ]
            )
            viewModel.updateProximity(userLocation: locationService.userLocation)
            viewModel.checkCooldown(reportHistory: profileViewModel.reportHistory)
            async let reportsTask: () = viewModel.loadReports()
            async let lookAroundTask: () = fetchLookAroundScene()
            _ = await (reportsTask, lookAroundTask)
            // Sync fresh estimate back to map so marker color matches detail
            mapViewModel.syncBusynessFromDetail(venueId: venue.id, estimate: viewModel.estimate)
        }
        .onChange(of: locationService.userLocation) { _, newLocation in
            viewModel.updateProximity(userLocation: newLocation)
        }
        .onChange(of: mapViewModel.venues) { _, updatedVenues in
            guard let updated = updatedVenues.first(where: { $0.id == venue.id }),
                  (updated.busyness ?? viewModel.estimate.level) != viewModel.estimate.level
                    || updated.busynessConfidence != viewModel.estimate.confidence
                    || (updated.isOpen ?? viewModel.estimate.isOpen) != viewModel.estimate.isOpen
            else { return }
            viewModel.updateFromLiveRefresh(venue: updated)
        }
        .onChange(of: viewModel.busynessJustChanged) { _, justChanged in
            guard justChanged else { return }
            withAnimation(.easeIn(duration: 0.15)) {
                busynessFlashOpacity = 1
            }
            withAnimation(.easeOut(duration: 0.4).delay(0.15)) {
                busynessFlashOpacity = 0
            }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(600))
                viewModel.busynessJustChanged = false
            }
        }
        .sheet(isPresented: $viewModel.showReportSheet, onDismiss: {
            if !didReport {
                Task { await AnalyticsService.shared.track(.reportDismissed, venueId: venue.id, venueName: venue.name, venueType: venue.category.rawValue) }
            }
        }) {
            ReportSheet(venue: venue) { level, wait in
                didReport = true
                Task { await viewModel.submitReport(level: level, waitMinutes: wait) }
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showAuthGate) {
            AuthGateSheet {
                authState.pendingVenue = venue
                authState.pendingVenueTab = tabSelection.selectedTab
                authState.requestSignIn()
            }
            .presentationDetents([.medium, .large])
        }
        .fullScreenCover(isPresented: $showFullLookAround) {
            if let scene = lookAroundScene {
                LookAroundPreview(initialScene: scene, allowsNavigation: true)
                    .ignoresSafeArea()
            }
        }
        .onDisappear {
            let durationMs = Int(Date().timeIntervalSince(sheetOpenTime) * 1000)
            Task {
                await AnalyticsService.shared.track(
                    .venueViewEnd,
                    venueId: venue.id,
                    venueName: venue.name,
                    venueType: venue.category.rawValue,
                    properties: [
                        "durationMs": .int(durationMs),
                        "didReport": .bool(didReport),
                        "didSave": .bool(didSave),
                        "didGetDirections": .bool(didGetDirections),
                    ]
                )
            }
        }
    }

    // MARK: - Section 1: Identity Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(venue.category.color.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: venue.category.icon)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(venue.category.color)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(venue.name)
                        .font(WaytTheme.headlineFont)
                        .lineLimit(2)

                    Text(venue.primaryTypeDisplayName ?? viewModel.venueDetailsFull?.primaryTypeDisplayName ?? venue.category.displayName)
                        .font(WaytTheme.captionFont)
                        .foregroundStyle(WaytTheme.secondaryText)
                }
            }

            if let address = venue.address {
                Label(address, systemImage: "mappin")
                    .font(WaytTheme.captionFont)
                    .foregroundStyle(WaytTheme.secondaryText)
            }
        }
    }

    // MARK: - At a Glance (Rating | Price | Reviews)

    private var atAGlanceSection: some View {
        VenueAtAGlanceCard(
            rating: venue.rating ?? viewModel.venueDetailsFull?.rating,
            userRatingCount: venue.userRatingCount ?? viewModel.venueDetailsFull?.userRatingCount,
            priceLevel: venue.priceLevel ?? viewModel.venueDetailsFull?.priceLevel,
            priceRange: venue.priceRange ?? viewModel.venueDetailsFull?.priceRange
        ) {
            showReviewsSheet = true
        }
        .sheet(isPresented: $showReviewsSheet) {
            ReviewsSheet(
                reviews: viewModel.venueDetailsFull?.reviews ?? [],
                googleMapsUrl: viewModel.venueDetailsFull?.googleMapsUrl
            )
        }
    }

    // MARK: - Section 2: Busyness Hero Card

    private var busynessHeroSection: some View {
        VStack(spacing: 0) {
            // Hours status bar
            if let isOpen = viewModel.estimate.isOpen {
                HStack(spacing: 6) {
                    Circle()
                        .fill(isOpen ? Color.green : Color.red)
                        .frame(width: 7, height: 7)

                    Text(isOpen ? "Open" : "Closed")
                        .font(WaytTheme.badgeFont)
                        .foregroundStyle(isOpen ? .green : .red)

                    if let hours = viewModel.estimate.hoursToday {
                        Text("· \(hours)")
                            .font(WaytTheme.badgeFont)
                            .foregroundStyle(WaytTheme.secondaryText)
                            .lineLimit(1)
                    }

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background((isOpen ? Color.green : Color.red).opacity(0.06))
            }

            VStack(alignment: .leading, spacing: 14) {
                if viewModel.estimate.isOpen == false {
                    closedBusynessContent
                } else {
                    openBusynessContent
                }

                embeddedReportButton

                compactRecentReports
            }
            .padding(16)
        }
        .background {
            RoundedRectangle(cornerRadius: WaytTheme.cornerRadius, style: .continuous)
                .fill(busynessBackgroundFill)
        }
        .waytCard()
        .busynessGlow(viewModel.estimate.isOpen == false ? nil : viewModel.estimate.level.color)
        .overlay {
            RoundedRectangle(cornerRadius: WaytTheme.cornerRadius, style: .continuous)
                .fill(viewModel.estimate.level.color.opacity(0.18 * busynessFlashOpacity))
                .allowsHitTesting(false)
        }
    }

    private var busynessBackgroundFill: some ShapeStyle {
        if viewModel.estimate.isOpen == false {
            return AnyShapeStyle(Color.clear)
        }
        return AnyShapeStyle(viewModel.estimate.level.color.opacity(0.05))
    }

    private var closedBusynessContent: some View {
        HStack(spacing: 12) {
            Image(systemName: "door.left.hand.closed")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.secondary)

            Text("Currently closed")
                .font(WaytTheme.bodyFont)
                .foregroundStyle(WaytTheme.secondaryText)
        }
    }

    private var openBusynessContent: some View {
        VStack(spacing: 12) {
            // Large centered busyness display
            HStack(spacing: 14) {
                Image(systemName: viewModel.estimate.level.icon)
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .foregroundStyle(viewModel.estimate.level.color)

                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.estimate.level.label)
                        .font(WaytTheme.headlineFont)
                        .foregroundStyle(viewModel.estimate.level.color)

                }

                Spacer()
            }

            // Confidence + wait time row
            HStack(spacing: 12) {
                BusynessBadge(
                    level: viewModel.estimate.level,
                    confidence: viewModel.estimate.confidence
                )

                if let wait = viewModel.estimate.waitMinutes {
                    Label("~\(wait) min wait", systemImage: "clock")
                        .font(WaytTheme.captionFont)
                        .foregroundStyle(WaytTheme.secondaryText)
                }

                Spacer()
            }

            TimelineView(.periodic(from: .now, by: 30)) { _ in
                Text("Updated \(viewModel.lastEstimateTime.refreshRelativeTime)")
                    .font(WaytTheme.microFont)
                    .foregroundStyle(WaytTheme.secondaryText.opacity(0.7))
            }
        }
    }

    private var embeddedReportButton: some View {
        VStack(spacing: 6) {
            if let message = viewModel.rateLimitMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(WaytTheme.captionFont)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(Color.orange.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            if viewModel.estimate.isOpen == false {
                Label("Venue is closed", systemImage: "door.left.hand.closed")
                    .font(WaytTheme.bodyBoldFont)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(.systemGray4))
                    .foregroundStyle(WaytTheme.secondaryText)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else if viewModel.isOnCooldown {
                Label(
                    "Report again in \(formattedCooldown(viewModel.cooldownRemaining))",
                    systemImage: "clock.arrow.circlepath"
                )
                .font(WaytTheme.bodyBoldFont)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(.systemGray4))
                .foregroundStyle(WaytTheme.secondaryText)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else if viewModel.isWithinReportRange {
                Button {
                    if authState.isSignedIn {
                        viewModel.showReportSheet = true
                    } else {
                        showAuthGate = true
                    }
                } label: {
                    Label(
                        viewModel.reportSubmitted ? "Thanks! Report again?" : "How busy is it?",
                        systemImage: viewModel.reportSubmitted ? "checkmark.circle.fill" : "megaphone.fill"
                    )
                    .font(WaytTheme.bodyBoldFont)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(viewModel.reportSubmitted ? .green : WaytTheme.mapsBlue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            } else {
                Label("Get closer to report", systemImage: "location.fill")
                    .font(WaytTheme.bodyBoldFont)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(.systemGray4))
                    .foregroundStyle(WaytTheme.secondaryText)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                if let distance = viewModel.distanceToVenue(from: locationService.userLocation) {
                    Text("You're \(formattedShortDistance(distance)) away - must be within \(formattedShortDistance(AppConstants.reportProximityRadius))")
                        .font(WaytTheme.captionFont)
                        .foregroundStyle(WaytTheme.secondaryText)
                }
            }
        }
    }

    @ViewBuilder
    private var compactRecentReports: some View {
        if !viewModel.recentReports.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Divider()

                Text("Recent Reports")
                    .font(WaytTheme.captionFont)
                    .foregroundStyle(WaytTheme.secondaryText)

                ForEach(viewModel.recentReports.prefix(3)) { report in
                    HStack {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(report.busynessLevel.color)
                                .frame(width: 6, height: 6)
                            Text(report.busynessLevel.label)
                                .font(WaytTheme.badgeFont)
                                .foregroundStyle(report.busynessLevel.color)
                        }

                        Spacer()

                        Text(report.timestamp, style: .relative)
                            .font(WaytTheme.badgeFont)
                            .foregroundStyle(WaytTheme.secondaryText)
                    }
                }
            }
        } else if viewModel.isLoadingReports {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading reports...")
                    .font(WaytTheme.captionFont)
                    .foregroundStyle(WaytTheme.secondaryText)
            }
        }
    }

    // MARK: - Section 3: Quick Actions

    private var actionsSection: some View {
        HStack(spacing: 12) {
            if let phone = venue.phoneNumber {
                actionButton(icon: "phone.fill", label: "Call") {
                    Task { await AnalyticsService.shared.track(.callTap, venueId: venue.id, venueName: venue.name) }
                    if let url = URL(string: "tel:\(phone)") {
                        UIApplication.shared.open(url)
                    }
                }
            }

            actionButton(icon: "arrow.triangle.turn.up.right.diamond.fill", label: "Directions") {
                didGetDirections = true
                Task {
                    await AnalyticsService.shared.track(
                        .directionsTap, venueId: venue.id, venueName: venue.name,
                        venueType: venue.category.rawValue,
                        lat: locationService.userLocation?.coordinate.latitude,
                        lng: locationService.userLocation?.coordinate.longitude
                    )
                }
                venue.mapItem.openInMaps(launchOptions: [
                    MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault
                ])
            }

            if tabSelection.selectedTab != .map {
                actionButton(icon: "map.fill", label: "See on Map") {
                    dismiss()
                    if !mapViewModel.venues.contains(where: { $0.id == venue.id }) {
                        mapViewModel.venues.append(venue)
                    }
                    tabSelection.selectedTab = .map
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        mapViewModel.selectVenue(venue)
                    }
                }
            }

            if let url = venue.url {
                actionButton(icon: "safari.fill", label: "Website") {
                    Task { await AnalyticsService.shared.track(.websiteTap, venueId: venue.id, venueName: venue.name) }
                    UIApplication.shared.open(url)
                }
            }

            actionButton(
                icon: savedVenuesVM.isSaved(venue.id) ? "bookmark.fill" : "bookmark",
                label: savedVenuesVM.isSaved(venue.id) ? "Saved" : "Save",
                tint: savedVenuesVM.isSaved(venue.id) ? WaytTheme.savedOrange : nil
            ) {
                if authState.isSignedIn {
                    didSave = true
                    Task { await savedVenuesVM.toggleSave(for: venue) }
                } else {
                    showAuthGate = true
                }
            }
        }
    }

    private func actionButton(
        icon: String,
        label: String,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(WaytTheme.headlineFont)
                Text(label)
                    .font(WaytTheme.badgeFont)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color(.tertiarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .tint(tint ?? WaytTheme.mapsBlue)
    }

    // MARK: - Look Around

    @ViewBuilder
    private var lookAroundSection: some View {
        if let scene = lookAroundScene {
            ZStack {
                LookAroundPreview(initialScene: scene)
                    .allowsHitTesting(false)
            }
            .frame(height: 140)
            .clipShape(RoundedRectangle(cornerRadius: WaytTheme.cornerRadius, style: .continuous))
            .overlay {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { showFullLookAround = true }
            }
        } else if isLoadingLookAround {
            RoundedRectangle(cornerRadius: WaytTheme.cornerRadius, style: .continuous)
                .fill(Color(.tertiarySystemBackground))
                .frame(height: 140)
                .overlay {
                    ProgressView()
                        .tint(.secondary)
                }
        }
    }

    private func formattedShortDistance(_ meters: Double) -> String {
        if distanceUnit == "mi" {
            let feet = Int(meters * 3.28084)
            return "\(feet)ft"
        } else {
            return "\(Int(meters))m"
        }
    }

    private func formattedCooldown(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds))
        let mins = totalSeconds / 60
        let secs = totalSeconds % 60
        return mins > 0 ? "\(mins)m \(secs)s" : "\(secs)s"
    }

    private func fetchLookAroundScene() async {
        let cache = LookAroundCache.shared
        let coordinate = venue.coordinate

        if lookAroundScene != nil || cache.isKnownMiss(for: coordinate) {
            isLoadingLookAround = false
            return
        }

        let request = MKLookAroundSceneRequest(coordinate: coordinate)
        do {
            if let scene = try await request.scene {
                lookAroundScene = scene
                cache.store(scene, for: coordinate)
            } else {
                cache.storeMiss(for: coordinate)
            }
        } catch {
            // Transient error — don't cache so we can retry later
        }
        isLoadingLookAround = false
    }

}

// MARK: - Relative Time Formatting

private extension Date {
    var refreshRelativeTime: String {
        let seconds = Int(-timeIntervalSinceNow)
        guard seconds >= 60 else { return "just now" }
        let minutes = seconds / 60
        guard minutes < 60 else { return "\(minutes / 60)h ago" }
        return "\(minutes)m ago"
    }
}
