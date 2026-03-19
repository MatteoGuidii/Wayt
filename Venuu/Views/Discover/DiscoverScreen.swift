import SwiftUI

struct DiscoverScreen: View {

    @StateObject private var viewModel = DiscoverViewModel()
    @EnvironmentObject private var locationService: LocationService
    @EnvironmentObject private var filterState: VenueFilterState
    @EnvironmentObject private var mapViewModel: MapViewModel
    @EnvironmentObject private var authState: AuthState
    @EnvironmentObject private var savedVenuesVM: SavedVenuesViewModel
    @State private var selectedVenue: Venue?
    @State private var isSavedExpanded: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    greetingHeader
                    vibePulseSection
                    categoryStrip
                    if authState.isSignedIn && !nearbySavedVenues.isEmpty {
                        savedVenuesSection
                    }
                    if !viewModel.sweetSpotVenues.isEmpty && showGoNow {
                        goNowSection
                    }
                    if !viewModel.popularVenues.isEmpty && showOnFire {
                        buzzingSection
                    }
                    allSpotsSection
                }
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .background(VenuuTheme.backgroundGradient)
        }
        .task {
            viewModel.filterState = filterState
            // Seed with existing map data
            if !mapViewModel.venues.isEmpty {
                viewModel.updateVenues(mapViewModel.venues, userLocation: locationService.userLocation)
            }
        }
        .onChange(of: mapViewModel.venues) { _, newVenues in
            viewModel.updateVenues(newVenues, userLocation: locationService.userLocation)
        }
        .sheet(item: $selectedVenue, onDismiss: {
            mapViewModel.refreshAfterReport()
        }) { venue in
            VenueDetailSheet(venue: venue)
                .presentationDetents([.large])
        }
    }

    // MARK: - Greeting Header

    private var greetingHeader: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.greeting)
                    .font(VenuuTheme.largeTitleFont)

                Text(viewModel.greetingSubtitle)
                    .font(VenuuTheme.subheadLightFont)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VenuuMascot(size: 80, expression: mascotExpression, animated: true)
                .offset(x: -10)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, -20)
    }

    /// Show "Go Now" when no busyness filter, or filtering empty/quiet/moderate
    private var showGoNow: Bool {
        guard let level = filterState.selectedBusynessLevel else { return true }
        return level.rawValue <= 3
    }

    /// Show "On Fire" when no busyness filter, or filtering busy/packed
    private var showOnFire: Bool {
        guard let level = filterState.selectedBusynessLevel else { return true }
        return level.rawValue >= 4
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

                if let level = filterState.selectedBusynessLevel {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            filterState.selectBusynessLevel(nil)
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

            if viewModel.venues.isEmpty && mapViewModel.isSearching {
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
                let isSelected = filterState.selectedBusynessLevel == level
                let isFiltering = filterState.selectedBusynessLevel != nil

                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        filterState.selectBusynessLevel(level)
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

    // MARK: - Saved Venues

    private var nearbySavedVenues: [Venue] {
        viewModel.venues.filter { savedVenuesVM.isSaved($0.id) }
    }

    private var savedVenuesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isSavedExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "bookmark.fill")
                        .font(VenuuTheme.footnoteFont)
                        .foregroundStyle(VenuuTheme.savedOrange)
                    Text("Saved Places")
                        .font(VenuuTheme.sectionFont)

                    Text("\(nearbySavedVenues.count)")
                        .font(VenuuTheme.badgeFont)
                        .foregroundStyle(VenuuTheme.savedOrange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(VenuuTheme.savedOrange.opacity(0.12))
                        .clipShape(Capsule())

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(VenuuTheme.footnoteFont)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isSavedExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)

            VStack(spacing: 8) {
                ForEach(nearbySavedVenues) { venue in
                    Button { selectedVenue = venue } label: {
                        VenueRow(venue: venue, userLocation: locationService.userLocation)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .frame(maxHeight: isSavedExpanded ? .none : 0, alignment: .top)
            .clipped()
            .opacity(isSavedExpanded ? 1 : 0)
        }
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
        let isSelected = filterState.selectedCategory == category
        let count = viewModel.categoryCounts[category] ?? 0

        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                if filterState.selectedCategory == category {
                    filterState.selectCategory(nil)
                } else {
                    filterState.selectCategory(category)
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
                    ? VenuuTheme.skyPunch
                    : VenuuTheme.cardBackground
            )
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(
                        isSelected ? VenuuTheme.skyPunch : Color.primary.opacity(0.08),
                        lineWidth: isSelected ? 0 : 1.5
                    )
            )
            .shadow(
                color: isSelected ? VenuuTheme.skyPunch.opacity(0.3) : .black.opacity(0.04),
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

                Text("\(viewModel.sweetSpotVenues.count) venues")
                    .font(VenuuTheme.badgeFont)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(.systemGray6))
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
                .lineLimit(2)
                .foregroundStyle(.primary)

            if let busyness = venue.busyness {
                Text(busyness.description)
                    .font(VenuuTheme.badgeFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .frame(width: 170, height: 120, alignment: .topLeading)
        .background(VenuuTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
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

                Text("\(viewModel.popularVenues.count) venues")
                    .font(VenuuTheme.badgeFont)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(.systemGray6))
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

                if mapViewModel.isSearching {
                    ProgressView()
                        .scaleEffect(0.8)
                }

                if filterState.selectedCategory != nil || filterState.selectedBusynessLevel != nil {
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            filterState.selectCategory(nil)
                            filterState.selectBusynessLevel(nil)
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

            if viewModel.filteredVenues.isEmpty && !mapViewModel.isSearching {
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

                if !viewModel.filteredVenues.isEmpty && !mapViewModel.isSearching && !mapViewModel.isExpandingSearch {
                    seeMoreButton
                }

                if mapViewModel.isExpandingSearch {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
            }
        }
    }

    private var seeMoreButton: some View {
        Button {
            mapViewModel.expandSearch()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus.magnifyingglass")
                    .font(VenuuTheme.footnoteFont)
                Text("See more venues")
                    .font(VenuuTheme.subheadFont)
            }
            .foregroundStyle(VenuuTheme.mapsBlue)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(VenuuTheme.mapsBlue.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(VenuuTheme.mapsBlue.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 4)
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
