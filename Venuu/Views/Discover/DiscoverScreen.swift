import SwiftUI

struct DiscoverScreen: View {

    @StateObject private var viewModel = DiscoverViewModel()
    @EnvironmentObject private var locationService: LocationService
    @State private var selectedVenue: Venue?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    greetingHeader
                    vibePulseSection
                    categoryStrip
                    if !viewModel.sweetSpotVenues.isEmpty && viewModel.selectedBusynessLevel == nil {
                        goNowSection
                    }
                    if !viewModel.popularVenues.isEmpty && viewModel.selectedBusynessLevel == nil {
                        buzzingSection
                    }
                    allSpotsSection
                }
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .background(Color(.systemGroupedBackground))
            .refreshable {
                await viewModel.loadVenues(near: locationService.userLocation)
            }
        }
        .task {
            guard viewModel.venues.isEmpty else { return }
            await viewModel.loadVenues(near: locationService.userLocation)
        }
        .onChange(of: locationService.userLocation) { _, newLocation in
            guard viewModel.venues.isEmpty, newLocation != nil else { return }
            Task {
                await viewModel.loadVenues(near: newLocation)
            }
        }
        .sheet(item: $selectedVenue) { venue in
            VenueDetailSheet(venue: venue)
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Greeting Header

    private var greetingHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.greeting)
                    .font(VenuuTheme.largeTitleFont)

                Text(viewModel.greetingSubtitle)
                    .font(VenuuTheme.subheadLightFont)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VenuuMascot(size: 50, expression: mascotExpression, animated: true)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var mascotExpression: VenuuMascot.Expression {
        guard let mood = viewModel.areaMood else { return .looking }
        switch mood {
        case .empty:    return .looking
        case .quiet:    return .happy
        case .moderate: return .cheerful
        case .busy:     return .excited
        case .packed:   return .wink
        }
    }

    // MARK: - Vibe Pulse (Tappable)

    private var vibePulseSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "waveform.path")
                    .font(VenuuTheme.footnoteFont)
                    .foregroundStyle(VenuuTheme.skyPunch)
                Text("Area Vibe")
                    .font(VenuuTheme.sectionFont)

                Spacer()

                if let level = viewModel.selectedBusynessLevel {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            viewModel.selectBusynessLevel(nil)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(level.label)
                                .font(VenuuTheme.badgeFont)
                            Image(systemName: "xmark")
                                .font(VenuuTheme.nanoFont)
                        }
                        .foregroundStyle(level.color)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(level.color.opacity(0.15))
                        .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, 20)

            if viewModel.venues.isEmpty && viewModel.isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                        .padding(.vertical, 20)
                    Spacer()
                }
            } else if viewModel.venues.isEmpty {
                emptyVibeState
            } else {
                vibeBarChart
            }
        }
    }

    private var vibeBarChart: some View {
        HStack(spacing: 6) {
            ForEach(BusynessLevel.allCases, id: \.self) { level in
                let count = viewModel.vibePulse[level.rawValue] ?? 0
                let maxCount = max(viewModel.vibePulse.values.max() ?? 1, 1)
                let fraction = Double(count) / Double(maxCount)
                let isSelected = viewModel.selectedBusynessLevel == level
                let isFiltering = viewModel.selectedBusynessLevel != nil

                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        viewModel.selectBusynessLevel(level)
                    }
                } label: {
                    VStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                LinearGradient(
                                    colors: [level.color.opacity(0.7), level.color],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(height: max(12, CGFloat(fraction) * 56))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(isSelected ? level.color : .clear, lineWidth: 2.5)
                            )
                            .opacity(isFiltering && !isSelected ? 0.3 : 1.0)
                            .animation(.spring(response: 0.5, dampingFraction: 0.7), value: count)

                        Text("\(count)")
                            .font(VenuuTheme.footnoteFont)
                            .foregroundStyle(isSelected ? level.color : (isFiltering ? .secondary : level.color))

                        Text(level.label)
                            .font(VenuuTheme.nanoFont)
                            .foregroundStyle(isSelected ? level.color : .secondary)
                            .textCase(.uppercase)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        isSelected
                            ? level.color.opacity(0.08)
                            : Color.clear
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(VenuuTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
        .padding(.horizontal, 16)
    }

    private var emptyVibeState: some View {
        VStack(spacing: 8) {
            VenuuMascot(size: 48, expression: .looking, animated: false)
            Text("Scanning your area...")
                .font(VenuuTheme.footnoteLightFont)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    // MARK: - Category Strip (Horizontal Pills)

    private var categoryStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(VenueCategory.allCases, id: \.self) { category in
                    categoryPill(category)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func categoryPill(_ category: VenueCategory) -> some View {
        let isSelected = viewModel.selectedCategory == category
        let count = viewModel.categoryCounts[category] ?? 0

        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                if viewModel.selectedCategory == category {
                    viewModel.selectCategory(nil)
                } else {
                    viewModel.selectCategory(category)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: category.icon)
                    .font(VenuuTheme.subheadFont)
                    .foregroundStyle(isSelected ? .white : category.color)

                Text(category.shortName)
                    .font(VenuuTheme.footnoteFont)
                    .foregroundStyle(isSelected ? .white : .primary)

                Text("\(count)")
                    .font(VenuuTheme.badgeFont)
                    .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                isSelected
                    ? category.color
                    : VenuuTheme.cardBackground
            )
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(
                        isSelected ? category.color : Color.primary.opacity(0.08),
                        lineWidth: isSelected ? 0 : 1.5
                    )
            )
            .shadow(
                color: isSelected ? category.color.opacity(0.3) : .black.opacity(0.04),
                radius: isSelected ? 6 : 3,
                x: 0,
                y: isSelected ? 3 : 1
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Go Now (was Sweet Spots)

    private var goNowSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("\u{1F7E2}")
                    .font(VenuuTheme.subheadFont)
                Text("Go Now")
                    .font(VenuuTheme.sectionFont)

                Spacer()

                Text("No wait")
                    .font(VenuuTheme.badgeFont)
                    .foregroundStyle(.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.12))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(viewModel.sweetSpotVenues) { venue in
                        Button { selectedVenue = venue } label: {
                            goNowCard(venue)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func goNowCard(_ venue: Venue) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(venue.category.color.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: venue.category.icon)
                        .font(VenuuTheme.cardTitleFont)
                        .foregroundStyle(venue.category.color)
                }

                Spacer()

                if let busyness = venue.busyness {
                    Text(busyness.label)
                        .font(VenuuTheme.microFont)
                        .foregroundStyle(busyness.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(busyness.color.opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            Text(venue.name)
                .font(VenuuTheme.subheadFont)
                .lineLimit(1)
                .foregroundStyle(.primary)

            if let busyness = venue.busyness {
                Text(busyness.description)
                    .font(VenuuTheme.badgeFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .frame(width: 170, alignment: .leading)
        .background(VenuuTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.green.opacity(0.2), lineWidth: 2)
        )
        .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 3)
    }

    // MARK: - Buzzing (On Fire)

    private var buzzingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("\u{1F525}")
                    .font(VenuuTheme.subheadFont)
                Text("On Fire")
                    .font(VenuuTheme.sectionFont)

                Spacer()

                Text("High energy")
                    .font(VenuuTheme.badgeFont)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(viewModel.popularVenues) { venue in
                        Button { selectedVenue = venue } label: {
                            VenueCard(venue: venue)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - All Spots

    private var allSpotsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(VenuuTheme.footnoteFont)
                        .foregroundStyle(VenuuTheme.skyPunch)
                    Text("All Spots")
                        .font(VenuuTheme.sectionFont)
                }

                Spacer()

                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                }

                if viewModel.selectedCategory != nil || viewModel.selectedBusynessLevel != nil {
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            viewModel.selectCategory(nil)
                            viewModel.selectBusynessLevel(nil)
                        }
                    } label: {
                        Text("Clear filters")
                            .font(VenuuTheme.captionFont)
                            .foregroundStyle(VenuuTheme.skyPunch)
                    }
                }
            }
            .padding(.horizontal, 20)

            if !viewModel.filteredVenues.isEmpty {
                Text("\(viewModel.filteredVenues.count) spots found")
                    .font(VenuuTheme.captionLightFont)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
            }

            if viewModel.filteredVenues.isEmpty && !viewModel.isLoading {
                emptyNearbyState
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.filteredVenues) { venue in
                        Button { selectedVenue = venue } label: {
                            VenueRow(venue: venue, userLocation: locationService.userLocation)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private var emptyNearbyState: some View {
        VStack(spacing: 12) {
            VenuuMascot(size: 56, expression: .looking, animated: true)

            Text("Nothing here yet")
                .font(VenuuTheme.bodyBoldFont)

            Text("Try a different filter or explore a new area")
                .font(VenuuTheme.footnoteLightFont)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}
