import Foundation

/// A locally cached record of a user's busyness report submission.
/// Stored in UserDefaults for the Profile activity feed — not sent to the backend.
struct ReportHistoryEntry: Codable, Identifiable, Sendable {
    let entryId: UUID
    let venueName: String
    let venueType: String
    let busynessLevel: Int
    let timestamp: Date

    var id: UUID { entryId }

    /// Supports decoding legacy entries that lack `entryId` (pre-UUID format).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entryId = (try? container.decode(UUID.self, forKey: .entryId)) ?? UUID()
        venueName = try container.decode(String.self, forKey: .venueName)
        venueType = try container.decode(String.self, forKey: .venueType)
        busynessLevel = try container.decode(Int.self, forKey: .busynessLevel)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
    }

    init(venueName: String, venueType: String, busynessLevel: Int, timestamp: Date) {
        self.entryId = UUID()
        self.venueName = venueName
        self.venueType = venueType
        self.busynessLevel = busynessLevel
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
