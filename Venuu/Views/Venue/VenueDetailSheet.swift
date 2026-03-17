import SwiftUI
import MapKit

// MARK: - Venue Detail Sheet

struct VenueDetailSheet: View {

    let venue: Venue
    @StateObject private var viewModel: VenueDetailViewModel
    @EnvironmentObject private var authState: AuthState
    @Environment(\.dismiss) private var dismiss
    @State private var showAuthGate = false
    @State private var lookAroundScene: MKLookAroundScene?
    @State private var showFullLookAround = false

    init(venue: Venue) {
        self.venue = venue
        _viewModel = StateObject(wrappedValue: VenueDetailViewModel(venue: venue))
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
            await viewModel.loadReports()
            await fetchLookAroundScene()
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
        }
    }

    private func fetchLookAroundScene() async {
        let request = MKLookAroundSceneRequest(coordinate: venue.coordinate)
        lookAroundScene = try? await request.scene
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
                            .foregroundStyle(.orange)
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
        }
    }

    private func actionButton(
        icon: String,
        label: String,
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
        .tint(VenuuTheme.mapsBlue)
    }

    // MARK: - Report Button

    private var reportButton: some View {
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
