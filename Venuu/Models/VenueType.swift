import Foundation
import SwiftUI

enum VenueType: String, CaseIterable, Codable, Hashable {
    case restaurant = "Restaurant"
    case cafe = "Cafe"
    case bakery = "Bakery"
    case bar = "Bar"
    case pub = "Pub"
    case lounge = "Lounge"
    case club = "Club"

    var icon: String {
        switch self {
        case .restaurant: return "fork.knife"
        case .cafe: return "cup.and.saucer.fill"
        case .bakery: return "birthday.cake.fill"
        case .bar: return "wineglass.fill"
        case .pub: return "mug.fill"
        case .lounge: return "sofa.fill"
        case .club: return "figure.dance"
        }
    }

    var color: Color {
        switch self {
        case .restaurant: return .orange
        case .cafe: return .brown
        case .bakery: return .pink
        case .bar: return .purple
        case .pub: return .yellow
        case .lounge: return .indigo
        case .club: return .red
        }
    }
}
