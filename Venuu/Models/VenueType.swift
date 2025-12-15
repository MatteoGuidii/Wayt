import Foundation
import SwiftUI

enum VenueType: String, CaseIterable, Codable, Hashable {
    case club = "Club"
    case bar = "Bar"
    case pub = "Pub"
    case lounge = "Lounge"
    case liveMusic = "Live Music"
    case restaurant = "Restaurant"
    case other = "Other"
    
    var icon: String {
        switch self {
        case .club: return "figure.dance"
        case .bar: return "wineglass.fill"
        case .pub: return "mug.fill"
        case .lounge: return "sofa.fill"
        case .liveMusic: return "music.mic"
        case .restaurant: return "fork.knife"
        case .other: return "mappin"
        }
    }
    
    var color: Color {
        switch self {
        case .club: return .pink
        case .bar: return .purple
        case .pub: return .orange
        case .lounge: return .indigo
        case .liveMusic: return .blue
        case .restaurant: return .green
        case .other: return .gray
        }
    }
}
