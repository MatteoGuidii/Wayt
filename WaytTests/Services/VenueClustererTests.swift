import Testing
import Foundation
import MapKit
@testable import Wayt

// MARK: - VenueClusterer.cluster()

@Suite("VenueClusterer.cluster")
@MainActor
struct VenueClustererClusterTests {

    // Toronto region used across tests
    private let toronto = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 43.65, longitude: -79.38),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )

    // MARK: - Empty / Single Input

    @Test("Empty venue array returns empty result")
    func emptyVenuesReturnsEmpty() {
        let items = VenueClusterer.cluster(venues: [], in: toronto)
        #expect(items.isEmpty)
    }

    @Test("Single venue returns single item, not a cluster")
    func singleVenueReturnsSingle() {
        let venue = TestFactories.makeVenue(
            name: "Solo Bar",
            coordinate: CLLocationCoordinate2D(latitude: 43.65, longitude: -79.38)
        )
        let items = VenueClusterer.cluster(venues: [venue], in: toronto)
        #expect(items.count == 1)
        if case .single(let v) = items[0] {
            #expect(v.id == venue.id)
        } else {
            Issue.record("Expected single item, got cluster")
        }
    }

    // MARK: - Clustering Behavior

    @Test("Two venues at identical coordinates cluster together")
    func twoVenuesAtSameLocationCluster() {
        let coord = CLLocationCoordinate2D(latitude: 43.65, longitude: -79.38)
        let v1 = TestFactories.makeVenue(name: "Bar A", coordinate: coord)
        let v2 = TestFactories.makeVenue(name: "Bar B", coordinate: coord)
        let items = VenueClusterer.cluster(venues: [v1, v2], in: toronto)
        let clusters = items.compactMap { item -> VenueCluster? in
            if case .cluster(let c) = item { return c }
            return nil
        }
        #expect(clusters.count == 1)
        #expect(clusters[0].count == 2)
    }

    @Test("Two venues very close together cluster")
    func twoVenuesCloseTogetherCluster() {
        // Cell size = 0.05/8 = 0.00625°. Place both well within one cell.
        let v1 = TestFactories.makeVenue(
            name: "Bar A",
            coordinate: CLLocationCoordinate2D(latitude: 43.6520, longitude: -79.3800)
        )
        let v2 = TestFactories.makeVenue(
            name: "Bar B",
            coordinate: CLLocationCoordinate2D(latitude: 43.6540, longitude: -79.3800)
        )
        let items = VenueClusterer.cluster(venues: [v1, v2], in: toronto)
        let clusters = items.compactMap { item -> VenueCluster? in
            if case .cluster(let c) = item { return c }
            return nil
        }
        #expect(clusters.count == 1)
    }

    @Test("Two venues far apart stay separate")
    func twoVenuesFarApartStaySeparate() {
        let v1 = TestFactories.makeVenue(
            name: "North Bar",
            coordinate: CLLocationCoordinate2D(latitude: 43.67, longitude: -79.38)
        )
        let v2 = TestFactories.makeVenue(
            name: "South Bar",
            coordinate: CLLocationCoordinate2D(latitude: 43.63, longitude: -79.38)
        )
        let items = VenueClusterer.cluster(venues: [v1, v2], in: toronto)
        let singles = items.filter { if case .single = $0 { return true }; return false }
        #expect(singles.count == 2)
    }

    @Test("Total venue count is preserved after clustering")
    func totalVenueCountPreserved() {
        let venues = (0..<10).map { i in
            TestFactories.makeVenue(
                name: "Venue \(i)",
                coordinate: CLLocationCoordinate2D(
                    latitude: 43.65 + Double(i) * 0.001,
                    longitude: -79.38
                )
            )
        }
        let items = VenueClusterer.cluster(venues: venues, in: toronto)
        var totalCount = 0
        for item in items {
            switch item {
            case .single: totalCount += 1
            case .cluster(let c): totalCount += c.count
            }
        }
        #expect(totalCount == 10)
    }

    @Test("Cluster centroid is average of member coordinates")
    func clusterCentroidIsAverage() {
        let coord1 = CLLocationCoordinate2D(latitude: 43.650, longitude: -79.380)
        let coord2 = CLLocationCoordinate2D(latitude: 43.650, longitude: -79.380)
        let v1 = TestFactories.makeVenue(name: "A", coordinate: coord1)
        let v2 = TestFactories.makeVenue(name: "B", coordinate: coord2)
        let items = VenueClusterer.cluster(venues: [v1, v2], in: toronto)
        if case .cluster(let c) = items.first {
            let expectedLat = (coord1.latitude + coord2.latitude) / 2
            let expectedLng = (coord1.longitude + coord2.longitude) / 2
            #expect(abs(c.coordinate.latitude - expectedLat) < 0.0001)
            #expect(abs(c.coordinate.longitude - expectedLng) < 0.0001)
        } else {
            Issue.record("Expected cluster")
        }
    }

    // MARK: - Zoom Level Effects

    @Test("Zoomed-out region produces more clusters")
    func zoomedOutProducesMoreClusters() {
        // Spread 6 venues across ~0.03° range
        let venues = (0..<6).map { i in
            TestFactories.makeVenue(
                name: "V\(i)",
                coordinate: CLLocationCoordinate2D(
                    latitude: 43.65 + Double(i) * 0.005,
                    longitude: -79.38
                )
            )
        }

        let zoomedIn = MKCoordinateRegion(
            center: toronto.center,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
        let zoomedOut = MKCoordinateRegion(
            center: toronto.center,
            span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
        )

        let itemsIn = VenueClusterer.cluster(venues: venues, in: zoomedIn)
        let itemsOut = VenueClusterer.cluster(venues: venues, in: zoomedOut)

        // Zoomed out → fewer items (more grouping)
        #expect(itemsOut.count <= itemsIn.count)
    }

    // MARK: - Edge Cases

    @Test("Zero-span region returns all as singles (guard clause)")
    func zeroSpanReturnsSingles() {
        let venue = TestFactories.makeVenue(name: "Bar")
        let zeroSpan = MKCoordinateRegion(
            center: toronto.center,
            span: MKCoordinateSpan(latitudeDelta: 0, longitudeDelta: 0)
        )
        let items = VenueClusterer.cluster(venues: [venue], in: zeroSpan)
        #expect(items.count == 1)
        if case .single = items[0] {} else {
            Issue.record("Expected single for zero-span region")
        }
    }

    @Test("Negative coordinates (southern/western hemisphere) cluster correctly")
    func negativeCoordinatesCluster() {
        // Buenos Aires area
        let v1 = TestFactories.makeVenue(
            name: "BA Bar 1",
            coordinate: CLLocationCoordinate2D(latitude: -34.60, longitude: -58.38)
        )
        let v2 = TestFactories.makeVenue(
            name: "BA Bar 2",
            coordinate: CLLocationCoordinate2D(latitude: -34.60, longitude: -58.38)
        )
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: -34.60, longitude: -58.38),
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
        let items = VenueClusterer.cluster(venues: [v1, v2], in: region)
        let clusters = items.compactMap { item -> VenueCluster? in
            if case .cluster(let c) = item { return c }
            return nil
        }
        #expect(clusters.count == 1)
        #expect(clusters[0].count == 2)
    }

    @Test("Large number of venues at same point produces single cluster")
    func manyVenuesSamePointSingleCluster() {
        let coord = CLLocationCoordinate2D(latitude: 43.65, longitude: -79.38)
        let venues = (0..<50).map {
            TestFactories.makeVenue(name: "Venue \($0)", coordinate: coord)
        }
        let items = VenueClusterer.cluster(venues: venues, in: toronto)
        #expect(items.count == 1)
        if case .cluster(let c) = items[0] {
            #expect(c.count == 50)
        } else {
            Issue.record("Expected single cluster for 50 colocated venues")
        }
    }

    @Test("Cluster IDs are unique")
    func clusterIDsAreUnique() {
        // Create 3 groups that will each cluster
        var venues: [Venue] = []
        for group in 0..<3 {
            let baseLat = 43.60 + Double(group) * 0.02
            for i in 0..<3 {
                venues.append(TestFactories.makeVenue(
                    name: "G\(group)V\(i)",
                    coordinate: CLLocationCoordinate2D(
                        latitude: baseLat + Double(i) * 0.0001,
                        longitude: -79.38
                    )
                ))
            }
        }
        let items = VenueClusterer.cluster(venues: venues, in: toronto)
        let ids = items.map(\.id)
        #expect(Set(ids).count == ids.count, "All map item IDs should be unique")
    }
}

// MARK: - VenueClusterer.shouldCluster()

@Suite("VenueClusterer.shouldCluster")
struct ShouldClusterTests {

    @Test("Large span enables clustering")
    func largeSpanEnablesClustering() {
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 43.65, longitude: -79.38),
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        )
        #expect(VenueClusterer.shouldCluster(region: region) == true)
    }

    @Test("Small span disables clustering")
    func smallSpanDisablesClustering() {
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 43.65, longitude: -79.38),
            span: MKCoordinateSpan(latitudeDelta: 0.003, longitudeDelta: 0.003)
        )
        #expect(VenueClusterer.shouldCluster(region: region) == false)
    }

    @Test("Span exactly at threshold disables clustering")
    func spanAtThresholdDisablesClustering() {
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 43.65, longitude: -79.38),
            span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
        )
        #expect(VenueClusterer.shouldCluster(region: region) == false)
    }

    @Test("Span just above threshold enables clustering")
    func spanJustAboveThresholdEnablesClustering() {
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 43.65, longitude: -79.38),
            span: MKCoordinateSpan(latitudeDelta: 0.0051, longitudeDelta: 0.0051)
        )
        #expect(VenueClusterer.shouldCluster(region: region) == true)
    }

    @Test("Zero span disables clustering")
    func zeroSpanDisablesClustering() {
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 43.65, longitude: -79.38),
            span: MKCoordinateSpan(latitudeDelta: 0, longitudeDelta: 0)
        )
        #expect(VenueClusterer.shouldCluster(region: region) == false)
    }
}

// MARK: - VenueCluster Properties

@Suite("VenueCluster")
@MainActor
struct VenueClusterTests {

    @Test("averageBusyness returns nil when no venue has busyness")
    func averageBusynessNilWhenNoBusyness() {
        let v1 = TestFactories.makeVenue(name: "A", busyness: nil)
        let v2 = TestFactories.makeVenue(name: "B", busyness: nil)
        let cluster = VenueCluster(
            id: "test",
            coordinate: CLLocationCoordinate2D(latitude: 43.65, longitude: -79.38),
            venues: [v1, v2]
        )
        #expect(cluster.averageBusyness == nil)
    }

    @Test("averageBusyness averages only venues with busyness data")
    func averageBusynessIgnoresNil() {
        let v1 = TestFactories.makeVenue(name: "A", busyness: .packed)   // 5
        let v2 = TestFactories.makeVenue(name: "B", busyness: nil)       // skipped
        let v3 = TestFactories.makeVenue(name: "C", busyness: .empty)    // 1
        let cluster = VenueCluster(
            id: "test",
            coordinate: CLLocationCoordinate2D(latitude: 43.65, longitude: -79.38),
            venues: [v1, v2, v3]
        )
        // Average of 5 and 1 = 3.0 → .moderate
        #expect(cluster.averageBusyness == .moderate)
    }

    @Test("averageBusyness with all same level returns that level")
    func averageBusynessUniform() {
        let venues = (0..<5).map {
            TestFactories.makeVenue(name: "V\($0)", busyness: .busy)
        }
        let cluster = VenueCluster(
            id: "test",
            coordinate: CLLocationCoordinate2D(latitude: 43.65, longitude: -79.38),
            venues: venues
        )
        #expect(cluster.averageBusyness == .busy)
    }

    @Test("averageBusyness rounds correctly at boundary (2.5 → 3)")
    func averageBusynessRoundsUp() {
        // quiet(2) + moderate(3) = avg 2.5 → should round to 3 (.moderate)
        let v1 = TestFactories.makeVenue(name: "A", busyness: .quiet)
        let v2 = TestFactories.makeVenue(name: "B", busyness: .moderate)
        let cluster = VenueCluster(
            id: "test",
            coordinate: CLLocationCoordinate2D(latitude: 43.65, longitude: -79.38),
            venues: [v1, v2]
        )
        #expect(cluster.averageBusyness == .moderate)
    }

    @Test("count returns number of venues")
    func countReturnsVenueCount() {
        let venues = (0..<7).map { TestFactories.makeVenue(name: "V\($0)") }
        let cluster = VenueCluster(
            id: "test",
            coordinate: CLLocationCoordinate2D(latitude: 43.65, longitude: -79.38),
            venues: venues
        )
        #expect(cluster.count == 7)
    }
}

// MARK: - VenueMapItem

@Suite("VenueMapItem")
@MainActor
struct VenueMapItemTests {

    @Test("Single item ID matches venue ID")
    func singleItemIDMatchesVenueID() {
        let venue = TestFactories.makeVenue(name: "Test Bar")
        let item = VenueMapItem.single(venue)
        #expect(item.id == venue.id)
    }

    @Test("Cluster item ID matches cluster ID")
    func clusterItemIDMatchesClusterID() {
        let cluster = VenueCluster(
            id: "cluster_42",
            coordinate: CLLocationCoordinate2D(latitude: 43.65, longitude: -79.38),
            venues: []
        )
        let item = VenueMapItem.cluster(cluster)
        #expect(item.id == "cluster_42")
    }

    @Test("Single item coordinate matches venue coordinate")
    func singleCoordinateMatchesVenue() {
        let coord = CLLocationCoordinate2D(latitude: 43.65, longitude: -79.38)
        let venue = TestFactories.makeVenue(name: "Test", coordinate: coord)
        let item = VenueMapItem.single(venue)
        #expect(item.coordinate.latitude == coord.latitude)
        #expect(item.coordinate.longitude == coord.longitude)
    }

    @Test("Cluster item coordinate matches cluster coordinate")
    func clusterCoordinateMatchesCluster() {
        let coord = CLLocationCoordinate2D(latitude: 43.65, longitude: -79.38)
        let cluster = VenueCluster(id: "c", coordinate: coord, venues: [])
        let item = VenueMapItem.cluster(cluster)
        #expect(item.coordinate.latitude == coord.latitude)
        #expect(item.coordinate.longitude == coord.longitude)
    }
}
