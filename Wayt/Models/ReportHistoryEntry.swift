import Foundation
import CoreLocation

/// A locally cached record of a user's busyness report submission.
/// Stored in UserDefaults for the Profile activity feed — not sent to the backend.
struct ReportHistoryEntry: Codable, Identifiable, Sendable {
    let entryId: UUID
    let venueId: String?
    let venueName: String
    let venueType: String
    let busynessLevel: Int
    let timestamp: Date
    let lat: Double
    let lng: Double

    var id: UUID { entryId }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    var hasCoordinates: Bool {
        lat != 0 || lng != 0
    }

    /// Supports decoding legacy entries that lack `entryId`, `venueId`, or coordinates.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entryId = (try? container.decode(UUID.self, forKey: .entryId)) ?? UUID()
        venueId = try container.decodeIfPresent(String.self, forKey: .venueId)
        venueName = try container.decode(String.self, forKey: .venueName)
        venueType = try container.decode(String.self, forKey: .venueType)
        busynessLevel = try container.decode(Int.self, forKey: .busynessLevel)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        lat = (try? container.decode(Double.self, forKey: .lat)) ?? 0
        lng = (try? container.decode(Double.self, forKey: .lng)) ?? 0
    }

    init(venueId: String, venueName: String, venueType: String, busynessLevel: Int, lat: Double, lng: Double, timestamp: Date) {
        self.entryId = UUID()
        self.venueId = venueId
        self.venueName = venueName
        self.venueType = venueType
        self.busynessLevel = busynessLevel
        self.lat = lat
        self.lng = lng
        self.timestamp = timestamp
    }

    var category: VenueCategory {
        VenueCategory(rawValue: venueType) ?? .food
    }

    var level: BusynessLevel {
        BusynessLevel(rawValue: busynessLevel) ?? .moderate
    }

    var relativeTime: String {
        let seconds = Int(-timestamp.timeIntervalSinceNow)
        guard seconds >= 0 else { return "Just now" }
        if seconds < 60 { return "Just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        let days = hours / 24
        if days == 1 { return "Yesterday" }
        return "\(days)d ago"
    }
}
