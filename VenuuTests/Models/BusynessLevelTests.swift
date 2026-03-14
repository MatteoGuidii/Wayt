import Testing
import SwiftUI
@testable import Venuu

@Suite("BusynessLevel")
struct BusynessLevelTests {

    // MARK: - Raw Values

    @Test("Raw values span 1 through 5")
    func rawValuesAreOneToFive() {
        #expect(BusynessLevel.empty.rawValue    == 1)
        #expect(BusynessLevel.quiet.rawValue    == 2)
        #expect(BusynessLevel.moderate.rawValue == 3)
        #expect(BusynessLevel.busy.rawValue     == 4)
        #expect(BusynessLevel.packed.rawValue   == 5)
    }

    @Test("init(rawValue:) succeeds for 1 through 5")
    func initRawValueValidRange() {
        #expect(BusynessLevel(rawValue: 1) == .empty)
        #expect(BusynessLevel(rawValue: 2) == .quiet)
        #expect(BusynessLevel(rawValue: 3) == .moderate)
        #expect(BusynessLevel(rawValue: 4) == .busy)
        #expect(BusynessLevel(rawValue: 5) == .packed)
    }

    @Test("init(rawValue:) returns nil for 0 and 6")
    func initRawValueOutOfRange() {
        #expect(BusynessLevel(rawValue: 0) == nil)
        #expect(BusynessLevel(rawValue: 6) == nil)
    }

    // MARK: - Display Properties

    @Test("All levels have non-empty label")
    func allLevelsHaveNonEmptyLabel() {
        for level in BusynessLevel.allCases {
            #expect(!level.label.isEmpty, "label for \(level) is empty")
        }
    }

    @Test("All levels have non-empty icon")
    func allLevelsHaveNonEmptyIcon() {
        for level in BusynessLevel.allCases {
            #expect(!level.icon.isEmpty, "icon for \(level) is empty")
        }
    }

    @Test("All levels have non-empty description")
    func allLevelsHaveNonEmptyDescription() {
        for level in BusynessLevel.allCases {
            #expect(!level.description.isEmpty, "description for \(level) is empty")
        }
    }

    @Test("Labels are distinct across all levels")
    func labelsAreDistinct() {
        let labels = BusynessLevel.allCases.map { $0.label }
        #expect(Set(labels).count == BusynessLevel.allCases.count)
    }

    @Test("Icons are distinct across all levels")
    func iconsAreDistinct() {
        let icons = BusynessLevel.allCases.map { $0.icon }
        #expect(Set(icons).count == BusynessLevel.allCases.count)
    }

    // MARK: - Colors

    @Test("Colors are distinct across all levels")
    func colorsAreDistinct() {
        let colors = BusynessLevel.allCases.map { $0.color }
        for i in 0..<colors.count {
            for j in (i + 1)..<colors.count {
                #expect(colors[i] != colors[j])
            }
        }
    }

    // MARK: - CaseIterable

    @Test("All cases count is 5")
    func allCasesCount() {
        #expect(BusynessLevel.allCases.count == 5)
    }
}
