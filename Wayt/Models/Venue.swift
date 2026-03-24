import Foundation
import MapKit
import SwiftUI

struct Venue: Identifiable, Hashable, @unchecked Sendable {

    // MARK: - Identity

    /// Deduplication key: lowercased name + 5‑decimal lat/lng (~1 m accuracy)
    let id: String
    let name: String
    let coordinate: CLLocationCoordinate2D

    // MARK: - Classification

    /// Raw MapKit POI category for accurate internal classification and external API matching.
    let poiCategory: MKPointOfInterestCategory?

    /// Broad display category computed from MapKit POI category + name fallback.
    var category: VenueCategory {
        let fromPOI = VenueCategory.from(poiCategory: poiCategory)
        // If POI mapped to generic .food, try refining from name
        if fromPOI == .food {
            return VenueCategory.from(name: name)
        }
        return fromPOI
    }

    // MARK: - Metadata (from MapKit)

    let address: String?
    let phoneNumber: String?
    let url: URL?
    let mapItem: MKMapItem

    // MARK: - Busyness (mutable, updated at runtime)

    var busyness: BusynessLevel?
    var busynessConfidence: BusynessConfidence = .none
    var reportCount: Int = 0
    var estimatedWaitMinutes: Int?
    var isOpen: Bool?
    var hoursToday: String?
    var businessStatus: String?

    // MARK: - Name Normalization

    /// Normalize venue name for ID generation to prevent duplicates
    /// caused by apostrophe/quote variations (e.g. "McDonald's" vs "McDonalds").
    private static func normalizedName(_ name: String) -> String {
        name.lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\u{2019}", with: "")  // right single quote
            .replacingOccurrences(of: "\"", with: "")
    }

    // MARK: - Init from MKMapItem

    @MainActor
    init(mapItem: MKMapItem) {
        let venueName = mapItem.name ?? "Unknown Venue"
        let coord = mapItem.placemark.coordinate
        let lat = String(format: "%.5f", coord.latitude)
        let lng = String(format: "%.5f", coord.longitude)

        self.id = "\(Self.normalizedName(venueName))_\(lat)_\(lng)"
        self.name = venueName
        self.coordinate = coord
        self.poiCategory = mapItem.pointOfInterestCategory
        self.address = mapItem.placemark.formattedAddress
        self.phoneNumber = mapItem.phoneNumber
        self.url = mapItem.url
        self.mapItem = mapItem
    }

    // MARK: - Hashable

    static func == (lhs: Venue, rhs: Venue) -> Bool {
        lhs.id == rhs.id
            && lhs.busyness == rhs.busyness
            && lhs.busynessConfidence == rhs.busynessConfidence
            && lhs.reportCount == rhs.reportCount
            && lhs.estimatedWaitMinutes == rhs.estimatedWaitMinutes
            && lhs.isOpen == rhs.isOpen
            && lhs.hoursToday == rhs.hoursToday
            && lhs.businessStatus == rhs.businessStatus
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(busyness)
        hasher.combine(busynessConfidence)
        hasher.combine(reportCount)
        hasher.combine(estimatedWaitMinutes)
        hasher.combine(isOpen)
        hasher.combine(hoursToday)
        hasher.combine(businessStatus)
    }
}

// MARK: - Busyness Confidence

enum BusynessConfidence: String, Sendable, CaseIterable {
    case none      // No data at all
    case estimated // Heuristic / baseline only
    case low       // 1-2 user reports
    case medium    // 1 strong source or 2 conflicting sources
    case high      // 2+ agreeing sources or 3+ reports
    case veryHigh  // 3+ sources agreeing (future-ready)

    var label: String {
        switch self {
        case .none:      return ""
        case .estimated: return "Estimated"
        case .low:       return "Few reports"
        case .medium:    return "Some data"
        case .high:      return "Reliable"
        case .veryHigh:  return "Very reliable"
        }
    }

    /// Initialize from server response string (handles both uppercase API format
    /// like "HIGH", "VERY_HIGH" and lowercase internal format like "high").
    init(fromServer value: String) {
        let normalized = value.lowercased().replacingOccurrences(of: "_", with: "")
        switch normalized {
        case "none":     self = .none
        case "estimated": self = .estimated
        case "low":      self = .low
        case "medium":   self = .medium
        case "high":     self = .high
        case "veryhigh": self = .veryHigh
        default:         self = .estimated
        }
    }
}

// MARK: - CLPlacemark Helper

extension CLPlacemark {
    var formattedAddress: String? {
        [subThoroughfare, thoroughfare, locality]
            .compactMap { $0 }
            .joined(separator: " ")
            .nilIfEmpty
    }
}

extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
