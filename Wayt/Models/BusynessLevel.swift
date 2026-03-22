import SwiftUI

enum BusynessLevel: Int, Codable, CaseIterable, Hashable, Sendable {
    case empty    = 1
    case quiet    = 2
    case moderate = 3
    case busy     = 4
    case packed   = 5

    var label: String {
        switch self {
        case .empty:    return "Empty"
        case .quiet:    return "Quiet"
        case .moderate: return "Moderate"
        case .busy:     return "Busy"
        case .packed:   return "Packed"
        }
    }

    var icon: String {
        switch self {
        case .empty:    return "person"
        case .quiet:    return "person.2"
        case .moderate: return "person.2.fill"
        case .busy:     return "person.3"
        case .packed:   return "person.3.fill"
        }
    }

    var description: String {
        switch self {
        case .empty:    return "Plenty of space"
        case .quiet:    return "A few people"
        case .moderate: return "Comfortably busy"
        case .busy:     return "Getting crowded"
        case .packed:   return "Standing room only"
        }
    }

    var color: Color {
        WaytTheme.busynessColor(for: rawValue)
    }

}
