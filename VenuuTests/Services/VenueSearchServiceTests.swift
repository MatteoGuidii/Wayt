import Testing
import Foundation
import MapKit
@testable import Venuu

@Suite("MKCoordinateRegion.isClose(to:)")
struct RegionIsCloseTests {

    private let nyc = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )

    // MARK: - Identical / Near-identical

    @Test("Identical regions are close")
    func identicalRegions() {
        #expect(nyc.isClose(to: nyc))
    }

    @Test("Slight center shift within tolerance is close")
    func slightCenterShift() {
        let shifted = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 40.7128 + 0.01, longitude: -74.0060 + 0.01),
            span: nyc.span
        )
        #expect(nyc.isClose(to: shifted))
    }

    // MARK: - Center Too Far

    @Test("Large center shift is not close")
    func largeCenterShift() {
        let farAway = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 40.7128 + 0.5, longitude: -74.0060),
            span: nyc.span
        )
        #expect(!nyc.isClose(to: farAway))
    }

    // MARK: - Zoom Level Mismatch

    @Test("Zoomed-out region vs zoomed-in region is not close")
    func zoomMismatch() {
        let zoomedOut = MKCoordinateRegion(
            center: nyc.center,
            span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5) // 10x larger
        )
        #expect(!nyc.isClose(to: zoomedOut))
    }

    @Test("Slightly different zoom within 50% tolerance is close")
    func slightZoomDifference() {
        let slightlyZoomed = MKCoordinateRegion(
            center: nyc.center,
            span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.06) // 20% larger
        )
        #expect(nyc.isClose(to: slightlyZoomed))
    }

    @Test("Zoom at exactly 1.5x ratio boundary is still close")
    func zoomAtBoundary() {
        let boundary = MKCoordinateRegion(
            center: nyc.center,
            span: MKCoordinateSpan(latitudeDelta: 0.075, longitudeDelta: 0.075) // exactly 1.5x
        )
        #expect(nyc.isClose(to: boundary))
    }

    @Test("Zoom just over 1.5x ratio is not close")
    func zoomJustOverBoundary() {
        let overBoundary = MKCoordinateRegion(
            center: nyc.center,
            span: MKCoordinateSpan(latitudeDelta: 0.076, longitudeDelta: 0.076) // >1.5x
        )
        #expect(!nyc.isClose(to: overBoundary))
    }

    // MARK: - Degenerate Regions

    @Test("Zero-span region is never close")
    func zeroSpan() {
        let degenerate = MKCoordinateRegion(
            center: nyc.center,
            span: MKCoordinateSpan(latitudeDelta: 0, longitudeDelta: 0)
        )
        #expect(!nyc.isClose(to: degenerate))
        #expect(!degenerate.isClose(to: nyc))
    }

    // MARK: - Symmetry

    @Test("isClose is symmetric")
    func symmetry() {
        let other = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 40.7128 + 0.01, longitude: -74.0060),
            span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.06)
        )
        #expect(nyc.isClose(to: other) == other.isClose(to: nyc))
    }

    // MARK: - Center close but one span axis mismatched

    @Test("Latitude span mismatch alone rejects")
    func latitudeSpanMismatchOnly() {
        let stretchedLat = MKCoordinateRegion(
            center: nyc.center,
            span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.05)
        )
        #expect(!nyc.isClose(to: stretchedLat))
    }
}

// MARK: - Region Contains

@Suite("MKCoordinateRegion.contains")
struct RegionContainsTests {

    private let region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 40.0, longitude: -74.0),
        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
    )

    @Test("Center coordinate is contained")
    func centerContained() {
        #expect(region.contains(region.center))
    }

    @Test("Corner coordinate is contained")
    func cornerContained() {
        let corner = CLLocationCoordinate2D(latitude: 40.05, longitude: -73.95)
        #expect(region.contains(corner))
    }

    @Test("Coordinate outside latitude is not contained")
    func outsideLatitude() {
        let outside = CLLocationCoordinate2D(latitude: 40.2, longitude: -74.0)
        #expect(!region.contains(outside))
    }

    @Test("Coordinate outside longitude is not contained")
    func outsideLongitude() {
        let outside = CLLocationCoordinate2D(latitude: 40.0, longitude: -73.8)
        #expect(!region.contains(outside))
    }
}

// MARK: - onRegionChanged zoom detection

@Suite("MapViewModel.onRegionChanged")
@MainActor
struct OnRegionChangedTests {

    @Test("Zoom in triggers search button")
    func zoomInTriggersButton() {
        let vm = MapViewModel()
        let broad = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 40.0, longitude: -74.0),
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        )
        vm.lastSearchedRegion = broad

        // Zoom in 3x at same center (no pan)
        let zoomedIn = MKCoordinateRegion(
            center: broad.center,
            span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
        )
        vm.onRegionChanged(zoomedIn)
        #expect(vm.showSearchThisArea == true)
    }

    @Test("Small pan triggers search button")
    func panTriggersButton() {
        let vm = MapViewModel()
        let initial = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 40.0, longitude: -74.0),
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
        vm.lastSearchedRegion = initial

        let panned = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 40.01, longitude: -74.0),
            span: initial.span
        )
        vm.onRegionChanged(panned)
        #expect(vm.showSearchThisArea == true)
    }

    @Test("Tiny movement does not trigger button")
    func tinyMovementNoTrigger() {
        let vm = MapViewModel()
        let initial = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 40.0, longitude: -74.0),
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
        vm.lastSearchedRegion = initial

        let barely = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 40.001, longitude: -74.001),
            span: initial.span
        )
        vm.onRegionChanged(barely)
        #expect(vm.showSearchThisArea == false)
    }
}
