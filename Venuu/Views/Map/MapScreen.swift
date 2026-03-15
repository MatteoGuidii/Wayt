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
            .mapControls { } // Disable default controls — we use custom ones
            .mapStyle(.standard(elevation: is3D ? .realistic : .flat, pointsOfInterest: .excludingAll))
            .onMapCameraChange(frequency: .onEnd) { context in
                visibleRegion = context.region
                mapHeading = context.camera.heading
                mapPitch = context.camera.pitch
                viewModel.onRegionChanged(context.region)
            }
            .ignoresSafeArea(edges: .top)

            // MARK: - Search Bar Overlay
            searchBar

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
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .task {
            locationService.requestPermission()

            // Only search if we don't already have results (avoids re-firing on tab return)
            if viewModel.venues.isEmpty, locationService.userLocation != nil {
                viewModel.searchVenues(in: locationService.region)
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

    // MARK: - Map Controls (grouped)

    private var mapControls: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                VStack(spacing: 0) {
                    // Compass — only visible when map is rotated
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
                                .frame(width: 44, height: 44)
                        }

                        Divider()
                            .frame(width: 28)
                    }

                    // 2D / 3D toggle
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
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(is3D ? VenuuTheme.coral : .secondary)
                            .frame(width: 44, height: 44)
                    }

                    Divider()
                        .frame(width: 28)

                    // Recenter on user
                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            viewModel.cameraPosition = .userLocation(fallback: .automatic)
                        }
                    } label: {
                        Image(systemName: "location.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(VenuuTheme.coral)
                            .frame(width: 44, height: 44)
                    }
                }
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
                .padding(.trailing, 16)
                .padding(.bottom, 110)
            }
        }
    }

    // MARK: - Compass Icon

    private var compassIcon: some View {
        ZStack {
            // North half (red)
            CompassNeedle(isTop: true)
                .fill(.red)
            // South half (white/gray)
            CompassNeedle(isTop: false)
                .fill(Color(.systemGray3))
        }
        .frame(width: 14, height: 14)
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
                    .background(VenuuTheme.coral)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .shadow(color: VenuuTheme.coral.opacity(0.3), radius: 6, y: 3)
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
            .background(VenuuTheme.coral.opacity(0.6))
            .clipShape(Capsule())
            .padding(.bottom, 100)
        }
    }
}

// MARK: - Compass Needle Shape

/// Diamond-shaped half needle for the compass icon (like Apple Maps).
struct CompassNeedle: Shape {
    let isTop: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midX = rect.midX
        let midY = rect.midY

        if isTop {
            // Top triangle: center-top → left-center → right-center
            path.move(to: CGPoint(x: midX, y: rect.minY))
            path.addLine(to: CGPoint(x: midX - rect.width * 0.3, y: midY))
            path.addLine(to: CGPoint(x: midX + rect.width * 0.3, y: midY))
            path.closeSubpath()
        } else {
            // Bottom triangle: center-bottom → left-center → right-center
            path.move(to: CGPoint(x: midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: midX - rect.width * 0.3, y: midY))
            path.addLine(to: CGPoint(x: midX + rect.width * 0.3, y: midY))
            path.closeSubpath()
        }

        return path
    }
}
