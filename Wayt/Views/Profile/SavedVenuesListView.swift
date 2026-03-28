import SwiftUI
import MapKit

/// Full-screen list of all saved venues.
struct SavedVenuesListView: View {

    @EnvironmentObject private var savedVenuesVM: SavedVenuesViewModel
    @Environment(\.dismiss) private var dismiss
    var onNavigate: ((SavedVenue) -> Void)?

    @State private var searchText = ""

    private var filteredVenues: [SavedVenue] {
        if searchText.isEmpty { return savedVenuesVM.savedVenues }
        return savedVenuesVM.savedVenues.filter {
            $0.venueName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WaytTheme.backgroundGradient
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        header
                        searchBar
                        venuesList
                    }
                    .padding(.bottom, 32)
                }
                .scrollIndicators(.hidden)

                if savedVenuesVM.savedVenues.isEmpty {
                    emptyState
                } else if !searchText.isEmpty && filteredVenues.isEmpty {
                    noResultsState
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(WaytTheme.mapsBlue)
                            .font(.title3)
                    }
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [WaytTheme.savedOrange, WaytTheme.savedOrange.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Saved Venues")
                    .font(WaytTheme.headlineFont)
                Text("\(savedVenuesVM.savedVenues.count) spots saved")
                    .font(WaytTheme.captionLightFont)
                    .foregroundStyle(WaytTheme.secondaryText)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(WaytTheme.secondaryText)

            TextField("Search saved venues", text: $searchText)
                .font(WaytTheme.subheadLightFont)
                .textFieldStyle(.plain)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(WaytTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.gray.opacity(0.15), lineWidth: 1)
        }
        .shadow(color: WaytTheme.cardShadow, radius: 4, x: 0, y: 2)
        .padding(.horizontal, 16)
    }

    // MARK: - Venues List

    private var venuesList: some View {
        LazyVStack(spacing: 10) {
            ForEach(filteredVenues) { venue in
                savedVenueCard(venue)
            }
        }
        .padding(.horizontal, 16)
    }

    private func savedVenueCard(_ venue: SavedVenue) -> some View {
        HStack(spacing: 14) {
            // Category icon badge
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(venue.category.color.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: venue.category.icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(venue.category.color)
            }

            // Venue info
            VStack(alignment: .leading, spacing: 3) {
                Text(venue.venueName)
                    .font(WaytTheme.subheadFont)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let address = venue.address {
                    Text(address)
                        .font(WaytTheme.captionLightFont)
                        .foregroundStyle(WaytTheme.secondaryText)
                        .lineLimit(1)
                }

                // Category pill
                Text(venue.category.shortName)
                    .font(WaytTheme.badgeFont)
                    .foregroundStyle(venue.category.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(venue.category.color.opacity(0.1))
                    .clipShape(Capsule())
            }

            Spacer()

            // Actions
            VStack(spacing: 8) {
                // Directions
                Button {
                    let placemark = MKPlacemark(coordinate: venue.coordinate)
                    let mapItem = MKMapItem(placemark: placemark)
                    mapItem.name = venue.venueName
                    mapItem.openInMaps(launchOptions: [
                        MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault
                    ])
                } label: {
                    Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(WaytTheme.mapsBlue)
                }

                // Unsave
                Button {
                    Task { await savedVenuesVM.toggleSaveById(venue.venueId) }
                } label: {
                    Image(systemName: "bookmark.slash.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(WaytTheme.savedOrange)
                }
            }
        }
        .padding(14)
        .background(WaytTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture {
            dismiss()
            onNavigate?(venue)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.gray.opacity(0.15), lineWidth: 1)
        }
        .shadow(color: WaytTheme.cardShadow, radius: 6, x: 0, y: 3)
    }

    // MARK: - Empty States

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bookmark")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.tertiary)

            VStack(spacing: 6) {
                Text("No saved spots yet")
                    .font(WaytTheme.bodyBoldFont)

                Text("Tap the bookmark on any venue\nto save it for later")
                    .font(WaytTheme.footnoteLightFont)
                    .foregroundStyle(WaytTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
        }
    }

    private var noResultsState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)

            Text("No matches for \"\(searchText)\"")
                .font(WaytTheme.footnoteLightFont)
                .foregroundStyle(WaytTheme.secondaryText)
        }
    }
}
