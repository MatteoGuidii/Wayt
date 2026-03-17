import SwiftUI
import MapKit

struct MapScreen: View {

    @StateObject private var viewModel = MapViewModel()
    @EnvironmentObject private var locationService: LocationService
    @EnvironmentObject private var authState: AuthState
    @State private var visibleRegion: MKCoordinateRegion = .defaultRegion
    @State private var mapHeading: Double = 0
    @State private var mapPitch: Double = 0
    @State private var is3D: Bool = false

    @Namespace private var mapScope

    var body: some View {
        ZStack(alignment: .top) {
            // MARK: - Map
            Map(position: $viewModel.cameraPosition, scope: mapScope) {
                // User location
                UserAnnotation()

                // Venue markers (clustered)
                ForEach(viewModel.mapItems) { item in
                    switch item {
                    case .single(let venue):
                        let selected = viewModel.selectedVenue?.id == venue.id
                        Annotation(
                            "",
                            coordinate: venue.coordinate,
                            anchor: .bottom
                        ) {
                            VenueMarkerView(
                                venue: venue,
                                isSelected: selected
                            )
                            .zIndex(selected ? 100 : 0)
                            .onTapGesture {
                                viewModel.selectVenue(venue, heading: mapHeading, pitch: mapPitch)
                            }
                        }

                    case .cluster(let cluster):
                        Annotation(
                            "",
                            coordinate: cluster.coordinate,
                            anchor: .bottom
                        ) {
                            ClusterMarkerView(cluster: cluster)
                                .onTapGesture {
                                    // Zoom into the cluster
                                    let clusterRegion = MKCoordinateRegion(
                                        center: cluster.coordinate,
                                        span: MKCoordinateSpan(
                                            latitudeDelta: visibleRegion.span.latitudeDelta / 3,
                                            longitudeDelta: visibleRegion.span.longitudeDelta / 3
                                        )
                                    )
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                        viewModel.cameraPosition = .region(clusterRegion)
                                    }
                                }
                        }
                    }
                }
            }
            .mapScope(mapScope)
            .mapControls { } // Disable default controls — we use custom ones
            .mapStyle(.standard(elevation: is3D ? .realistic : .flat, pointsOfInterest: .excludingAll))
            .onMapCameraChange(frequency: .onEnd) { context in
                visibleRegion = context.region
                mapHeading = context.camera.heading
                mapPitch = context.camera.pitch
                viewModel.onRegionChanged(context.region)
            }
            .ignoresSafeArea(edges: .top)

            // MARK: - Search Bar + Category Filters
            VStack(spacing: 10) {
                searchBar
                categoryChips
            }

            // MARK: - Map Controls (Compass + Recenter)
            mapControls

            // MARK: - Search This Area Button
            if viewModel.showSearchThisArea {
                searchThisAreaButton
            }

            // MARK: - Loading Indicator
            if viewModel.isSearching {
                loadingIndicator
            }
        }
        .sheet(item: $viewModel.selectedVenue, onDismiss: {
            viewModel.refreshAfterReport()
        }) { venue in
            VenueDetailSheet(venue: venue)
                .presentationDetents([.large, .medium], selection: .constant(.large))
                .presentationDragIndicator(.visible)
        }
        .task {
            locationService.requestPermission()

            // Search immediately — use GPS region if available, otherwise visible region
            if viewModel.venues.isEmpty {
                let region = locationService.userLocation != nil
                    ? locationService.region : visibleRegion
                viewModel.searchVenues(in: region)
            }

            viewModel.startLiveRefresh()
        }
        .onDisappear {
            viewModel.stopLiveRefresh()
        }
        .onChange(of: locationService.userLocation) { _, newLocation in
            guard newLocation != nil, viewModel.venues.isEmpty else { return }
            viewModel.searchVenues(in: locationService.region)
        }
        .onChange(of: authState.dismissSheets) { _, shouldDismiss in
            if shouldDismiss {
                viewModel.selectedVenue = nil
            }
        }
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

    // MARK: - Category Filter Chips

    private var categoryChips: some View {
        HStack(spacing: 8) {
            ForEach(VenueCategory.allCases, id: \.self) { category in
                let isActive = viewModel.selectedCategory == category

                Button {
                    viewModel.toggleCategoryFilter(category)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: category.icon)
                            .font(.system(size: 11, weight: .medium))
                        Text(category.shortName)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                    }
                    .frame(height: VenuuTheme.chipHeight)
                    .padding(.horizontal, 12)
                    .background(isActive ? VenuuTheme.mapsBlue.opacity(0.15) : Color.black.opacity(0.03))
                    .background(.ultraThinMaterial)
                    .foregroundStyle(isActive ? VenuuTheme.mapsBlue : .primary.opacity(0.55))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                isActive ? VenuuTheme.mapsBlue.opacity(0.5) : Color.black.opacity(0.1),
                                lineWidth: isActive ? 1.5 : 0.5
                            )
                    )
                }
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Map Controls (Apple Maps style)

    private var mapControls: some View {
        VStack {
            Spacer()

            HStack {
                Spacer()

                // Grouped controls: Compass (when rotated), 3D, Location
                VStack(spacing: 0) {
                    // Compass — appears inside the group when map is rotated
                    if mapHeading != 0 {
                        Button {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                viewModel.cameraPosition = .camera(MapCamera(
                                    centerCoordinate: visibleRegion.center,
                                    distance: visibleRegion.span.latitudeDelta * 111_000,
                                    heading: 0,
                                    pitch: is3D ? 45 : 0
                                ))
                            }
                        } label: {
                            compassIcon
                                .frame(maxWidth: .infinity, minHeight: 54)
                        }

                        Divider()
                            .padding(.horizontal, 8)
                    }

                    // 3D toggle
                    Button {
                        is3D.toggle()
                        withAnimation(.easeInOut(duration: 0.4)) {
                            viewModel.cameraPosition = .camera(MapCamera(
                                centerCoordinate: visibleRegion.center,
                                distance: visibleRegion.span.latitudeDelta * 111_000,
                                heading: mapHeading,
                                pitch: is3D ? 45 : 0
                            ))
                        }
                    } label: {
                        Text(is3D ? "3D" : "2D")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(VenuuTheme.mapsBlue)
                            .frame(maxWidth: .infinity, minHeight: 54)
                    }

                    Divider()
                        .padding(.horizontal, 8)

                    // Recenter on user
                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            viewModel.cameraPosition = .userLocation(fallback: .automatic)
                        }
                    } label: {
                        Image(systemName: "location.fill")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(VenuuTheme.mapsBlue)
                            .frame(maxWidth: .infinity, minHeight: 54)
                    }
                }
                .frame(width: 56)
                .background(.regularMaterial)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.10), radius: 6, y: 3)
                .padding(.trailing, 16)
            }
            .padding(.bottom, 8)
        }
        .animation(.easeInOut(duration: 0.25), value: mapHeading != 0)
    }

    // MARK: - Compass Icon (Apple Maps style)

    private var compassIcon: some View {
        ZStack {
            // "N" letter
            Text("N")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(VenuuTheme.mapsBlue)

            // Small red north triangle at the top
            Triangle()
                .fill(.red)
                .frame(width: 7, height: 6)
                .offset(y: -15)
        }
        .rotationEffect(.degrees(-mapHeading))
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
                    .background(VenuuTheme.mapsBlue)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .shadow(color: VenuuTheme.mapsBlue.opacity(0.3), radius: 6, y: 3)
            }
            .padding(.bottom, 16)
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
            .background(VenuuTheme.mapsBlue.opacity(0.6))
            .clipShape(Capsule())
            .padding(.bottom, 16)
        }
    }
}

// MARK: - Compass Needle Shape


// MARK: - Triangle Shape (compass north indicator)

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
