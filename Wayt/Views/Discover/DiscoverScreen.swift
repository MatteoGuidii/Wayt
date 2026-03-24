import MapKit
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
            .background(WaytTheme.backgroundGradient)
            .foregroundStyle(WaytTheme.primaryText)
        }
        .task {
            viewModel.filterState = filterState
            // Trigger initial search if Map hasn't been visited yet
            if mapViewModel.venues.isEmpty {
                let region = locationService.userLocation != nil
                    ? locationService.region
                    : MKCoordinateRegion.defaultRegion
                mapViewModel.ensureInitialSearch(region: region)
            }
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
                    .font(WaytTheme.largeTitleFont)

                Text(viewModel.greetingSubtitle)
                    .font(WaytTheme.subheadLightFont)
                    .foregroundStyle(WaytTheme.secondaryText)
            }

            Spacer()

            WaytMascot(size: 80, expression: mascotExpression, animated: true)
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

    private var mascotExpression: WaytMascot.Expression {
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
                    .font(WaytTheme.footnoteFont)
                    .foregroundStyle(WaytTheme.skyPunch)
                Text("Area Vibe")
                    .font(WaytTheme.sectionFont)

                Spacer()

                if let level = filterState.selectedBusynessLevel {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            filterState.selectBusynessLevel(nil)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(level.label)
                                .font(WaytTheme.badgeFont)
                            Image(systemName: "xmark")
                                .font(WaytTheme.nanoFont)
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
                            .font(WaytTheme.footnoteFont)
                            .foregroundStyle(isSelected ? level.color : (isFiltering ? .secondary : level.color))

                        Text(level.label)
                            .font(WaytTheme.nanoFont)
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
        .background(WaytTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: WaytTheme.cardShadow, radius: 8, x: 0, y: 4)
        .padding(.horizontal, 16)
    }

    private var emptyVibeState: some View {
        VStack(spacing: 8) {
            WaytMascot(size: 48, expression: .looking, animated: false)
            Text("Scanning your area...")
                .font(WaytTheme.footnoteLightFont)
                .foregroundStyle(WaytTheme.secondaryText)
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
                        .font(WaytTheme.footnoteFont)
                        .foregroundStyle(WaytTheme.savedOrange)
                    Text("Saved Places")
                        .font(WaytTheme.sectionFont)

                    Text("\(nearbySavedVenues.count)")
                        .font(WaytTheme.badgeFont)
                        .foregroundStyle(WaytTheme.savedOrange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(WaytTheme.savedOrange.opacity(0.12))
                        .clipShape(Capsule())

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(WaytTheme.footnoteFont)
                        .foregroundStyle(WaytTheme.secondaryText)
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
                    .font(WaytTheme.subheadFont)
                    .foregroundStyle(isSelected ? .white : category.color)

                Text(category.shortName)
                    .font(WaytTheme.footnoteFont)
                    .foregroundStyle(isSelected ? .white : .primary)

                Text("\(count)")
                    .font(WaytTheme.badgeFont)
                    .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                isSelected
                    ? WaytTheme.skyPunch
                    : WaytTheme.cardBackground
            )
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(
                        isSelected ? WaytTheme.skyPunch : Color.primary.opacity(0.08),
                        lineWidth: isSelected ? 0 : 1.5
                    )
            )
            .shadow(
                color: isSelected ? WaytTheme.skyPunch.opacity(0.3) : .black.opacity(0.04),
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
                    .font(WaytTheme.subheadFont)
                Text("Go Now")
                    .font(WaytTheme.sectionFont)

                Spacer()

                Text("\(viewModel.sweetSpotVenues.count) venues")
                    .font(WaytTheme.badgeFont)
                    .foregroundStyle(WaytTheme.secondaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(WaytTheme.cardBackground)
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
                    PinShape()
                        .fill(venue.category.color.opacity(0.15))
                        .frame(width: 36, height: 42)
                    Image(systemName: venue.category.icon)
                        .font(WaytTheme.cardTitleFont)
                        .foregroundStyle(venue.category.color)
                        .offset(y: -2)
                }

                Spacer()

                if let busyness = venue.busyness {
                    Text(busyness.label)
                        .font(WaytTheme.microFont)
                        .foregroundStyle(busyness.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(busyness.color.opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            Text(venue.name)
                .font(WaytTheme.subheadFont)
                .lineLimit(2)
                .foregroundStyle(.primary)

            if let busyness = venue.busyness {
                Text(busyness.description)
                    .font(WaytTheme.badgeFont)
                    .foregroundStyle(WaytTheme.secondaryText)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .frame(width: 170, height: 120, alignment: .topLeading)
        .background(
            ZStack {
                WaytTheme.cardBackground
                LinearGradient(
                    colors: [
                        (venue.busyness?.color ?? .clear).opacity(0.04),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .busynessGlow(venue.busyness?.color)
    }

    // MARK: - Buzzing (On Fire)

    private var buzzingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("\u{1F525}")
                    .font(WaytTheme.subheadFont)
                Text("On Fire")
                    .font(WaytTheme.sectionFont)

                Spacer()

                Text("\(viewModel.popularVenues.count) venues")
                    .font(WaytTheme.badgeFont)
                    .foregroundStyle(WaytTheme.secondaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(WaytTheme.cardBackground)
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
                        .font(WaytTheme.footnoteFont)
                        .foregroundStyle(WaytTheme.skyPunch)
                    Text("All Spots")
                        .font(WaytTheme.sectionFont)
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
                            .font(WaytTheme.captionFont)
                            .foregroundStyle(WaytTheme.skyPunch)
                    }
                }
            }
            .padding(.horizontal, 20)

            if !viewModel.filteredVenues.isEmpty {
                Text("\(viewModel.filteredVenues.count) spots found")
                    .font(WaytTheme.captionLightFont)
                    .foregroundStyle(WaytTheme.secondaryText)
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
                    .font(WaytTheme.footnoteFont)
                Text("See more venues")
                    .font(WaytTheme.subheadFont)
            }
            .foregroundStyle(WaytTheme.mapsBlue)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(WaytTheme.mapsBlue.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(WaytTheme.mapsBlue.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    private var emptyNearbyState: some View {
        VStack(spacing: 12) {
            WaytMascot(size: 56, expression: .looking, animated: true)

            Text("Nothing here yet")
                .font(WaytTheme.bodyBoldFont)

            Text("Try a different filter or explore a new area")
                .font(WaytTheme.footnoteLightFont)
                .foregroundStyle(WaytTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}
