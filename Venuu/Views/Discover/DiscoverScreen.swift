import SwiftUI

struct DiscoverScreen: View {

    @StateObject private var viewModel = DiscoverViewModel()
    @EnvironmentObject private var locationService: LocationService

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Category chips
                    categoryFilter

                    // Popular Now (horizontal scroll)
                    if !viewModel.popularVenues.isEmpty {
                        popularSection
                    }

                    // Near You (list)
                    nearYouSection
                }
                .padding(.vertical, 8)
            }
            .navigationTitle("Discover")
            .refreshable {
                await viewModel.loadVenues(near: locationService.userLocation)
            }
        }
        .task {
            // Skip re-loading on tab return when venues already exist
            guard viewModel.venues.isEmpty else { return }
            await viewModel.loadVenues(near: locationService.userLocation)
        }
        .onChange(of: locationService.userLocation) { _, newLocation in
            guard viewModel.venues.isEmpty, newLocation != nil else { return }
            Task {
                await viewModel.loadVenues(near: newLocation)
            }
        }
    }

    // MARK: - Category Filter

    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryChip(label: "All", type: nil)
                ForEach(VenueCategory.allCases, id: \.self) { type in
                    categoryChip(label: type.displayName, type: type, icon: type.icon)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func categoryChip(
        label: String,
        type: VenueCategory?,
        icon: String? = nil
    ) -> some View {
        let isSelected = viewModel.selectedCategory == type
        return Button {
            viewModel.selectCategory(type)
        } label: {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                }
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
            }
            .padding(.horizontal, 14)
            .frame(height: VenuuTheme.chipHeight)
            .background(isSelected ? VenuuTheme.amber : Color(.tertiarySystemBackground))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
    }

    // MARK: - Popular Now

    private var popularSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Popular Now 🔥")
                .font(VenuuTheme.headlineFont)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(viewModel.popularVenues) { venue in
                        VenueCard(venue: venue)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Near You

    private var nearYouSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Near You")
                    .font(VenuuTheme.headlineFont)

                Spacer()

                if viewModel.isLoading {
                    ProgressView()
                }
            }
            .padding(.horizontal, 16)

            if viewModel.filteredVenues.isEmpty && !viewModel.isLoading {
                ContentUnavailableView(
                    "No venues found",
                    systemImage: "mappin.slash",
                    description: Text("Try a different category or move to a new area.")
                )
                .padding(.top, 40)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.filteredVenues) { venue in
                        VenueRow(venue: venue, userLocation: locationService.userLocation)
                            .padding(.horizontal, 16)
                        Divider()
                            .padding(.leading, 72)
                    }
                }
            }
        }
    }
}
