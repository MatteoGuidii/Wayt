import Foundation
import MapKit
@testable import Wayt

enum TestFactories {

    @MainActor
    static func makeVenue(
        name: String = "Test Venue",
        busyness: BusynessLevel? = nil,
        coordinate: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 43.65107, longitude: -79.34723)
    ) -> Venue {
        let placemark = MKPlacemark(coordinate: coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = name
        var venue = Venue(mapItem: mapItem)
        venue.busyness = busyness
        return venue
    }

    static func makeReport(
        busynessLevel: BusynessLevel = .moderate,
        waitMinutes: Int? = nil,
        timestamp: Date = Date()
    ) -> BusynessReport {
        BusynessReport(
            reportId: UUID().uuidString,
            userId: "test-user",
            busynessLevel: busynessLevel,
            waitMinutes: waitMinutes,
            timestamp: timestamp,
            venueName: "Test Venue",
            venueType: "bar"
        )
    }
}
