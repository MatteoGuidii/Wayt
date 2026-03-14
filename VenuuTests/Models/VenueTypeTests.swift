import Testing
import SwiftUI
@testable import Venuu

@Suite("VenueType")
struct VenueTypeTests {

    // MARK: - Case Count

    @Test("All 7 venue types are defined")
    func allCasesCount() {
        #expect(VenueType.allCases.count == 7)
    }

    // MARK: - Display Properties

    @Test("All types have non-empty displayName")
    func allTypesHaveNonEmptyDisplayName() {
        for type_ in VenueType.allCases {
            #expect(!type_.displayName.isEmpty, "displayName for \(type_) is empty")
        }
    }

    @Test("All types have non-empty icon")
    func allTypesHaveNonEmptyIcon() {
        for type_ in VenueType.allCases {
            #expect(!type_.icon.isEmpty, "icon for \(type_) is empty")
        }
    }

    @Test("All types have non-empty searchTerms")
    func allTypesHaveNonEmptySearchTerms() {
        for type_ in VenueType.allCases {
            #expect(!type_.searchTerms.isEmpty, "searchTerms for \(type_) is empty")
            for term in type_.searchTerms {
                #expect(!term.isEmpty, "search term in \(type_) is empty string")
            }
        }
    }

    // MARK: - Heuristic Data

    @Test("All types have non-empty peakHours in valid 24h range")
    func allTypesHaveValidPeakHours() {
        for type_ in VenueType.allCases {
            #expect(!type_.peakHours.isEmpty, "peakHours for \(type_) is empty")
            for hour in type_.peakHours {
                #expect(hour >= 0 && hour <= 23, "hour \(hour) in \(type_) is out of 0-23 range")
            }
        }
    }

    @Test("All types have non-empty peakDays with valid weekday values")
    func allTypesHaveValidPeakDays() {
        for type_ in VenueType.allCases {
            #expect(!type_.peakDays.isEmpty, "peakDays for \(type_) is empty")
            for day in type_.peakDays {
                #expect(day >= 1 && day <= 7, "day \(day) in \(type_) is out of 1-7 range")
            }
        }
    }

    // MARK: - Uniqueness

    @Test("All types have unique icons")
    func allTypesHaveUniqueIcons() {
        let icons = VenueType.allCases.map { $0.icon }
        #expect(Set(icons).count == VenueType.allCases.count)
    }

    @Test("All types have unique colors")
    func allTypesHaveUniqueColors() {
        let colors = VenueType.allCases.map { $0.color }
        for i in 0..<colors.count {
            for j in (i + 1)..<colors.count {
                #expect(colors[i] != colors[j])
            }
        }
    }

    // MARK: - Raw Values

    @Test("Raw value matches the enum case name")
    func rawValueMatchesCaseName() {
        #expect(VenueType.restaurant.rawValue == "restaurant")
        #expect(VenueType.cafe.rawValue       == "cafe")
        #expect(VenueType.bakery.rawValue     == "bakery")
        #expect(VenueType.bar.rawValue        == "bar")
        #expect(VenueType.pub.rawValue        == "pub")
        #expect(VenueType.lounge.rawValue     == "lounge")
        #expect(VenueType.club.rawValue       == "club")
    }
}
