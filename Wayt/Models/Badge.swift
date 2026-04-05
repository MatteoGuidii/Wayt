import Foundation

enum Badge: String, CaseIterable, Identifiable {
    case firstReport = "First Report"
    case fiveReports = "Getting Started"
    case twentyFiveReports = "Regular"
    case fiftyReports = "Veteran"
    case hundredReports = "Centurion"
    case nightOwl = "Night Owl"
    case earlyBird = "Early Bird"
    case venueHopper = "Venue Hopper"
    case loyalRegular = "Loyal Regular"
    case categoryKing = "Category King"
    case weekendWarrior = "Weekend Warrior"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .firstReport: "megaphone.fill"
        case .fiveReports: "star.fill"
        case .twentyFiveReports: "flame.fill"
        case .fiftyReports: "shield.fill"
        case .hundredReports: "crown.fill"
        case .nightOwl: "moon.fill"
        case .earlyBird: "sunrise.fill"
        case .venueHopper: "map.fill"
        case .loyalRegular: "heart.fill"
        case .categoryKing: "trophy.fill"
        case .weekendWarrior: "party.popper.fill"
        }
    }

    var subtitle: String {
        switch self {
        case .firstReport: "Submit your first report"
        case .fiveReports: "Submit 5 reports"
        case .twentyFiveReports: "Submit 25 reports"
        case .fiftyReports: "Submit 50 reports"
        case .hundredReports: "Submit 100 reports"
        case .nightOwl: "Report after 10 PM"
        case .earlyBird: "Report before 10 AM"
        case .venueHopper: "Report at 5+ different venues"
        case .loyalRegular: "Report at the same venue 10 times"
        case .categoryKing: "Submit 30 reports in one category"
        case .weekendWarrior: "Report on both Saturday and Sunday"
        }
    }

    func isEarned(reports: [ReportHistoryEntry], totalReports: Int) -> Bool {
        let calendar = Calendar.current
        switch self {
        case .firstReport:
            return totalReports >= 1
        case .fiveReports:
            return totalReports >= 5
        case .twentyFiveReports:
            return totalReports >= 25
        case .fiftyReports:
            return totalReports >= 50
        case .hundredReports:
            return totalReports >= 100
        case .nightOwl:
            return reports.contains { calendar.component(.hour, from: $0.timestamp) >= 22 }
        case .earlyBird:
            return reports.contains { calendar.component(.hour, from: $0.timestamp) < 10 }
        case .venueHopper:
            return Set(reports.map(\.venueName)).count >= 5
        case .loyalRegular:
            return Dictionary(grouping: reports, by: \.venueName).mapValues(\.count)
                .values.contains { $0 >= 10 }
        case .categoryKing:
            return Dictionary(grouping: reports, by: \.venueType).mapValues(\.count)
                .values.contains { $0 >= 30 }
        case .weekendWarrior:
            let hasSaturday = reports.contains { calendar.component(.weekday, from: $0.timestamp) == 7 }
            let hasSunday = reports.contains { calendar.component(.weekday, from: $0.timestamp) == 1 }
            return hasSaturday && hasSunday
        }
    }
}
