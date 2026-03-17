import Testing
import Foundation
import MapKit
@testable import Venuu

@Suite("VenueSearchService Cache Key")
struct CacheKeyTests {

    // MARK: - Region Proximity (isClose)

    private let baseRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 43.65, longitude: -79.38),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )

    @Test("Same region is close to itself")
    func sameRegionIsClose() {
        #expect(baseRegion.isClose(to: baseRegion))
    }

    @Test("Nearby region with same zoom is close")
    func nearbyRegionClose() {
        let nearby = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 43.655, longitude: -79.385),
            span: baseRegion.span
        )
        #expect(baseRegion.isClose(to: nearby))
    }

    @Test("Far region is not close even at same zoom")
    func farRegionNotClose() {
        let far = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 44.0, longitude: -79.38),
            span: baseRegion.span
        )
        #expect(!baseRegion.isClose(to: far))
    }

    @Test("10x zoom difference is not close")
    func hugeZoomDifferenceNotClose() {
        let zoomedOut = MKCoordinateRegion(
            center: baseRegion.center,
            span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
        )
        #expect(!baseRegion.isClose(to: zoomedOut))
    }

    @Test("isClose is symmetric")
    func isCloseSymmetric() {
        let other = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 43.655, longitude: -79.385),
            span: MKCoordinateSpan(latitudeDelta: 0.055, longitudeDelta: 0.055)
        )
        #expect(baseRegion.isClose(to: other) == other.isClose(to: baseRegion))
    }

    // MARK: - Region Contains

    @Test("Center is contained")
    func centerContained() {
        #expect(baseRegion.contains(baseRegion.center))
    }

    @Test("Point well outside is not contained")
    func pointOutsideNotContained() {
        let outside = CLLocationCoordinate2D(latitude: 44.0, longitude: -79.38)
        #expect(!baseRegion.contains(outside))
    }

    @Test("Boundary point is contained (inclusive)")
    func boundaryPointContained() {
        let edge = CLLocationCoordinate2D(
            latitude: baseRegion.center.latitude + baseRegion.span.latitudeDelta / 2,
            longitude: baseRegion.center.longitude
        )
        #expect(baseRegion.contains(edge))
    }

    @Test("Point just outside boundary is not contained")
    func pointJustOutsideNotContained() {
        let justOutside = CLLocationCoordinate2D(
            latitude: baseRegion.center.latitude + baseRegion.span.latitudeDelta / 2 + 0.001,
            longitude: baseRegion.center.longitude
        )
        #expect(!baseRegion.contains(justOutside))
    }

    // MARK: - Negative Coordinates

    @Test("Contains works with negative latitude (southern hemisphere)")
    func containsNegativeLatitude() {
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: -34.60, longitude: -58.38),
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        )
        #expect(region.contains(region.center))
        #expect(!region.contains(CLLocationCoordinate2D(latitude: -34.0, longitude: -58.38)))
    }

    @Test("isClose works with negative coordinates")
    func isCloseNegativeCoordinates() {
        let r1 = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: -34.60, longitude: -58.38),
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
        let r2 = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: -34.605, longitude: -58.385),
            span: r1.span
        )
        #expect(r1.isClose(to: r2))
    }

    // MARK: - Zero / Degenerate Regions

    @Test("Zero span is never close to non-zero span")
    func zeroSpanNeverClose() {
        let zero = MKCoordinateRegion(
            center: baseRegion.center,
            span: MKCoordinateSpan(latitudeDelta: 0, longitudeDelta: 0)
        )
        #expect(!baseRegion.isClose(to: zero))
        #expect(!zero.isClose(to: baseRegion))
    }

    @Test("Contains with very small region still works")
    func verySmallRegionContains() {
        let tiny = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 43.65, longitude: -79.38),
            span: MKCoordinateSpan(latitudeDelta: 0.0001, longitudeDelta: 0.0001)
        )
        #expect(tiny.contains(tiny.center))
        #expect(!tiny.contains(CLLocationCoordinate2D(latitude: 43.651, longitude: -79.38)))
    }
}
