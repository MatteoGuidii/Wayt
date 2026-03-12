import SwiftUI
import MapKit

struct MapScreen: View {

    @StateObject private var viewModel = MapViewModel()
    @EnvironmentObject private var locationService: LocationService
    @State private var visibleRegion: MKCoordinateRegion = .defaultRegion

    @Namespace private var mapScope

    var body: some View {
        ZStack(alignment: .top) {
            // MARK: - Map
            Map(position: $viewModel.cameraPosition, scope: mapScope) {
                // User location
                UserAnnotation()

                // Venue markers
                ForEach(viewModel.venues) { venue in
                    Annotation(
                        venue.name,
                        coordinate: venue.coordinate,
                        anchor: .center
                    ) {
                        VenueMarkerView(
                            venue: venue,
                            isSelected: viewModel.selectedVenue?.id == venue.id
                        )
                        .onTapGesture {
                            viewModel.selectVenue(venue)
                        }
                    }
                }
            }
            .mapScope(mapScope)
            .mapControls {
                MapCompass(scope: mapScope)
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .onMapCameraChange(frequency: .onEnd) { context in
                visibleRegion = context.region
                viewModel.onRegionChanged(context.region)
            }
            .ignoresSafeArea(edges: .top)

            // MARK: - Search Bar Overlay
            searchBar

            // MARK: - Search This Area Button
            if viewModel.showSearchThisArea {
                searchThisAreaButton
            }

            // MARK: - Loading Indicator
            if viewModel.isSearching {
                loadingIndicator
            }

            // MARK: - Recenter Button
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            viewModel.cameraPosition = .userLocation(fallback: .automatic)
                        }
                    } label: {
                        Image(systemName: "location.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(VenuuTheme.primaryPurple)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 100)
                }
            }
        }
        .sheet(item: $viewModel.selectedVenue, onDismiss: {
            viewModel.refreshAfterReport()
        }) { venue in
            VenueDetailSheet(venue: venue)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .task {
            locationService.requestPermission()
            // Wait for location to become available, then do initial search
            await waitForLocationAndSearch()
            // Start live refresh (auto-updates busyness every 60s)
            viewModel.startLiveRefresh()
        }
        .onDisappear {
            viewModel.stopLiveRefresh()
        }
        .onChange(of: locationService.userLocation) { _, newLocation in
            guard newLocation != nil, viewModel.venues.isEmpty else { return }
            viewModel.searchVenues(in: locationService.region)
        }
    }

    // MARK: - Initial Search

    private func waitForLocationAndSearch() async {
        // If location is already available, search immediately
        if locationService.userLocation != nil {
            print("[MapScreen] Location already available, searching...")
            viewModel.searchVenues(in: locationService.region)
            return
        }
        // Otherwise poll briefly until location arrives
        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(500))
            if locationService.userLocation != nil {
                print("[MapScreen] Location received, searching...")
                viewModel.searchVenues(in: locationService.region)
                return
            }
        }
        print("[MapScreen] Timed out waiting for location")
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search restaurants, bars...", text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit {
                    let region = locationService.userLocation != nil
                        ? locationService.region : visibleRegion
                    viewModel.performTextSearch(in: region)
                }

            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.clearSearch(in: visibleRegion)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.10), radius: 8, y: 4)
        .padding(.horizontal, 16)
        .padding(.top, 60)
    }

    // MARK: - Search This Area

    private var searchThisAreaButton: some View {
        VStack {
            Spacer()

            Button {
                viewModel.searchVenues(in: visibleRegion)
            } label: {
                Label("Search This Area", systemImage: "arrow.clockwise")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(VenuuTheme.primaryPurple)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
            }
            .padding(.bottom, 100)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.spring(response: 0.35), value: viewModel.showSearchThisArea)
    }

    // MARK: - Loading

    private var loadingIndicator: some View {
        VStack {
            Spacer()
            HStack(spacing: 8) {
                ProgressView()
                    .tint(.white)
                Text("Finding venues...")
                    .font(VenuuTheme.captionFont)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial.opacity(0.9))
            .background(VenuuTheme.primaryPurple.opacity(0.6))
            .clipShape(Capsule())
            .padding(.bottom, 100)
        }
    }
}
