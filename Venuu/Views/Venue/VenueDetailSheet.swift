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

    private init() {}

    func scene(for coordinate: CLLocationCoordinate2D) -> MKLookAroundScene? {
        cache[key(for: coordinate)]
    }

    func isKnownMiss(for coordinate: CLLocationCoordinate2D) -> Bool {
        misses.contains(key(for: coordinate))
    }

    func store(_ scene: MKLookAroundScene, for coordinate: CLLocationCoordinate2D) {
        if cache.count >= maxEntries {
            // Evict ~25% of entries
            let keysToRemove = Array(cache.keys.prefix(maxEntries / 4))
            keysToRemove.forEach { cache.removeValue(forKey: $0) }
        }
        cache[key(for: coordinate)] = scene
    }

    func storeMiss(for coordinate: CLLocationCoordinate2D) {
        misses.insert(key(for: coordinate))
    }

    private func key(for coordinate: CLLocationCoordinate2D) -> String {
        String(format: "%.5f,%.5f", coordinate.latitude, coordinate.longitude)
    }
}

// MARK: - Venue Detail Sheet

struct VenueDetailSheet: View {

    let venue: Venue
    @StateObject private var viewModel: VenueDetailViewModel
    @EnvironmentObject private var authState: AuthState
    @EnvironmentObject private var locationService: LocationService
    @EnvironmentObject private var savedVenuesVM: SavedVenuesViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showAuthGate = false
    @State private var lookAroundScene: MKLookAroundScene?
    @State private var isLoadingLookAround = true
    @State private var showFullLookAround = false

    init(venue: Venue) {
        self.venue = venue
        _viewModel = StateObject(wrappedValue: VenueDetailViewModel(venue: venue))
        // Instantly populate from cache if available (before body is rendered)
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
                VStack(alignment: .leading, spacing: 20) {
                    headerSection
                        .padding(.top, -8)
                    lookAroundSection
                    busynessSection
                    actionsSection
                    reportButton
                    recentReportsSection
                }
                .padding(VenuuTheme.cardPadding)
            }
            .background(VenuuTheme.backgroundGradient)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        if authState.isSignedIn {
                            Task { await savedVenuesVM.toggleSave(for: venue) }
                        } else {
                            showAuthGate = true
                        }
                    } label: {
                        Image(systemName: savedVenuesVM.isSaved(venue.id) ? "bookmark.fill" : "bookmark")
                            .foregroundStyle(savedVenuesVM.isSaved(venue.id) ? VenuuTheme.savedOrange : VenuuTheme.mapsBlue)
                            .font(.title3)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(VenuuTheme.mapsBlue)
                            .font(.title3)
                    }
                }
            }
        }
        .task {
            // Proximity is synchronous — run immediately
            viewModel.updateProximity(userLocation: locationService.userLocation)

            // Fire reports + LookAround in parallel
            async let reportsTask: () = viewModel.loadReports()
            async let lookAroundTask: () = fetchLookAroundScene()
            _ = await (reportsTask, lookAroundTask)
        }
        .onChange(of: locationService.userLocation) { _, newLocation in
            viewModel.updateProximity(userLocation: newLocation)
        }
        .sheet(isPresented: $viewModel.showReportSheet) {
            ReportSheet(venue: venue) { level, wait in
                Task { await viewModel.submitReport(level: level, waitMinutes: wait) }
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showAuthGate) {
            AuthGateSheet {
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
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(venue.category.color.opacity(0.15))
                        .frame(width: 48, height: 48)
                    Image(systemName: venue.category.icon)
                        .font(VenuuTheme.headlineFont)
                        .foregroundStyle(venue.category.color)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(venue.name)
                        .font(VenuuTheme.headlineFont)
                        .lineLimit(2)

                    Text(venue.category.displayName)
                        .font(VenuuTheme.captionFont)
                        .foregroundStyle(.secondary)
                }
            }

            if let address = venue.address {
                Label(address, systemImage: "mappin")
                    .font(VenuuTheme.captionFont)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Look Around

    @ViewBuilder
    private var lookAroundSection: some View {
        if let scene = lookAroundScene {
            ZStack {
                LookAroundPreview(initialScene: scene)
                    .allowsHitTesting(false)
            }
            .frame(height: 160)
            .clipShape(RoundedRectangle(cornerRadius: VenuuTheme.cornerRadius, style: .continuous))
            .overlay {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { showFullLookAround = true }
            }
        } else if isLoadingLookAround {
            RoundedRectangle(cornerRadius: VenuuTheme.cornerRadius, style: .continuous)
                .fill(Color(.tertiarySystemBackground))
                .frame(height: 160)
                .overlay {
                    ProgressView()
                        .tint(.secondary)
                }
        }
    }

    private func fetchLookAroundScene() async {
        let cache = LookAroundCache.shared
        let coordinate = venue.coordinate

        // Already populated from cache in init
        if lookAroundScene != nil || cache.isKnownMiss(for: coordinate) {
            isLoadingLookAround = false
            return
        }

        let request = MKLookAroundSceneRequest(coordinate: coordinate)
        if let scene = try? await request.scene {
            lookAroundScene = scene
            cache.store(scene, for: coordinate)
        } else {
            cache.storeMiss(for: coordinate)
        }
        isLoadingLookAround = false
    }

    // MARK: - Busyness

    private var busynessSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Current Busyness")
                .font(VenuuTheme.subtitleFont)

            HStack(spacing: 16) {
                // Large busyness indicator
                VStack(spacing: 4) {
                    Image(systemName: viewModel.estimate.level.icon)
                        .font(VenuuTheme.displayFont)
                        .foregroundStyle(viewModel.estimate.level.color)

                    Text(viewModel.estimate.level.label)
                        .font(VenuuTheme.bodyBoldFont)
                        .foregroundStyle(viewModel.estimate.level.color)
                }
                .frame(width: 80)

                VStack(alignment: .leading, spacing: 6) {
                    Text(viewModel.estimate.level.description)
                        .font(VenuuTheme.bodyFont)

                    BusynessBadge(
                        level: viewModel.estimate.level,
                        confidence: viewModel.estimate.confidence
                    )

                    if let wait = viewModel.estimate.waitMinutes {
                        Label("~\(wait) min wait", systemImage: "clock")
                            .font(VenuuTheme.captionFont)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .venuuCard()
        }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        HStack(spacing: 12) {
            if let phone = venue.phoneNumber {
                actionButton(icon: "phone.fill", label: "Call") {
                    if let url = URL(string: "tel:\(phone)") {
                        UIApplication.shared.open(url)
                    }
                }
            }

            actionButton(icon: "arrow.triangle.turn.up.right.diamond.fill", label: "Directions") {
                venue.mapItem.openInMaps(launchOptions: [
                    MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault
                ])
            }

            if let url = venue.url {
                actionButton(icon: "safari.fill", label: "Website") {
                    UIApplication.shared.open(url)
                }
            }

            actionButton(
                icon: savedVenuesVM.isSaved(venue.id) ? "bookmark.fill" : "bookmark",
                label: savedVenuesVM.isSaved(venue.id) ? "Saved" : "Save",
                tint: savedVenuesVM.isSaved(venue.id) ? VenuuTheme.savedOrange : nil
            ) {
                if authState.isSignedIn {
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
                    .font(VenuuTheme.headlineFont)
                Text(label)
                    .font(VenuuTheme.badgeFont)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color(.tertiarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .tint(tint ?? VenuuTheme.mapsBlue)
    }

    // MARK: - Report Button

    private var reportButton: some View {
        VStack(spacing: 6) {
            if viewModel.isWithinReportRange {
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
                    .font(VenuuTheme.bodyBoldFont)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(viewModel.reportSubmitted ? .green : VenuuTheme.mapsBlue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            } else {
                Label("Get closer to report", systemImage: "location.fill")
                    .font(VenuuTheme.bodyBoldFont)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(.systemGray4))
                    .foregroundStyle(.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                if let distance = viewModel.distanceToVenue(from: locationService.userLocation) {
                    Text("You're \(Int(distance))m away - must be within \(Int(AppConstants.reportProximityRadius))m")
                        .font(VenuuTheme.captionFont)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Recent Reports

    private var recentReportsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !viewModel.recentReports.isEmpty {
                Text("Recent Reports")
                    .font(VenuuTheme.subtitleFont)

                ForEach(viewModel.recentReports.prefix(5)) { report in
                    HStack {
                        BusynessBadge(
                            level: report.busynessLevel,
                            confidence: .high,
                            style: .compact
                        )

                        Spacer()

                        Text(report.timestamp, style: .relative)
                            .font(VenuuTheme.badgeFont)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            } else if viewModel.isLoadingReports {
                HStack {
                    ProgressView()
                    Text("Loading reports...")
                        .font(VenuuTheme.captionFont)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
