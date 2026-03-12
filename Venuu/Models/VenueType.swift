import SwiftUI

enum VenueType: String, CaseIterable, Codable, Hashable, Sendable {
    case restaurant
    case cafe
    case bakery
    case bar
    case pub
    case lounge
    case club

    // MARK: - Display

    var displayName: String {
        rawValue.capitalized
    }

    var icon: String {
        switch self {
        case .restaurant: return "fork.knife"
        case .cafe:       return "cup.and.saucer.fill"
        case .bakery:     return "birthday.cake.fill"
        case .bar:        return "wineglass.fill"
        case .pub:        return "mug.fill"
        case .lounge:     return "sofa.fill"
        case .club:       return "figure.dance"
        }
    }

    var color: Color {
        switch self {
        case .restaurant: return .orange
        case .cafe:       return .brown
        case .bakery:     return .pink
        case .bar:        return .purple
        case .pub:        return .yellow
        case .lounge:     return .indigo
        case .club:       return .red
        }
    }

    // MARK: - Search Terms for MapKit

    var searchTerms: [String] {
        switch self {
        case .restaurant: return ["restaurant"]
        case .cafe:       return ["cafe", "coffee"]
        case .bakery:     return ["bakery"]
        case .bar:        return ["bar", "cocktail bar", "wine bar"]
        case .pub:        return ["pub", "gastropub"]
        case .lounge:     return ["lounge", "rooftop bar"]
        case .club:       return ["nightclub", "club"]
        }
    }

    // MARK: - Heuristic Engine Data

    /// Hours of peak busyness (24h format)
    var peakHours: [Int] {
        switch self {
        case .restaurant: return [12, 13, 19, 20, 21]
        case .cafe:       return [8, 9, 10, 14, 15]
        case .bakery:     return [7, 8, 9, 10]
        case .bar:        return [21, 22, 23, 0, 1]
        case .pub:        return [17, 18, 19, 20, 21, 22]
        case .lounge:     return [20, 21, 22, 23, 0]
        case .club:       return [23, 0, 1, 2]
        }
    }

    /// Busiest days of the week (1 = Sunday, 7 = Saturday per Calendar)
    var peakDays: [Int] {
        switch self {
        case .restaurant: return [1, 6, 7]         // Sun, Fri, Sat
        case .cafe:       return [1, 7]             // Sun, Sat
        case .bakery:     return [1, 7]
        case .bar:        return [6, 7]             // Fri, Sat
        case .pub:        return [5, 6, 7]          // Thu, Fri, Sat
        case .lounge:     return [6, 7]
        case .club:       return [6, 7]
        }
    }
}
