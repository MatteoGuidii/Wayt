import Testing
import Foundation
@testable import Venuu

@Suite("BusynessLevel(closestTo:) Rounding")
struct BusynessLevelRoundingTests {

    // MARK: - Exact Values

    @Test("Exact integer values map correctly")
    func exactValues() {
        #expect(BusynessLevel(closestTo: 1.0) == .empty)
        #expect(BusynessLevel(closestTo: 2.0) == .quiet)
        #expect(BusynessLevel(closestTo: 3.0) == .moderate)
        #expect(BusynessLevel(closestTo: 4.0) == .busy)
        #expect(BusynessLevel(closestTo: 5.0) == .packed)
    }

    // MARK: - Boundary Rounding (0.5 values)

    @Test("1.5 rounds to quiet (2), not empty (1)")
    func onePointFiveRoundsUp() {
        #expect(BusynessLevel(closestTo: 1.5) == .quiet)
    }

    @Test("2.5 rounds to moderate (3), not quiet (2)")
    func twoPointFiveRoundsUp() {
        #expect(BusynessLevel(closestTo: 2.5) == .moderate)
    }

    @Test("3.5 rounds to busy (4), not moderate (3)")
    func threePointFiveRoundsUp() {
        #expect(BusynessLevel(closestTo: 3.5) == .busy)
    }

    @Test("4.5 rounds to packed (5), not busy (4)")
    func fourPointFiveRoundsUp() {
        #expect(BusynessLevel(closestTo: 4.5) == .packed)
    }

    // MARK: - Non-boundary Values

    @Test("Values below midpoint round down")
    func belowMidpointRoundsDown() {
        #expect(BusynessLevel(closestTo: 1.4) == .empty)
        #expect(BusynessLevel(closestTo: 2.4) == .quiet)
        #expect(BusynessLevel(closestTo: 3.4) == .moderate)
        #expect(BusynessLevel(closestTo: 4.4) == .busy)
    }

    @Test("Values above midpoint round up")
    func aboveMidpointRoundsUp() {
        #expect(BusynessLevel(closestTo: 1.6) == .quiet)
        #expect(BusynessLevel(closestTo: 2.6) == .moderate)
        #expect(BusynessLevel(closestTo: 3.6) == .busy)
        #expect(BusynessLevel(closestTo: 4.6) == .packed)
    }

    // MARK: - Clamping

    @Test("Value below 1.0 clamps to empty")
    func belowMinClampsToEmpty() {
        #expect(BusynessLevel(closestTo: 0.0) == .empty)
        #expect(BusynessLevel(closestTo: -1.0) == .empty)
        #expect(BusynessLevel(closestTo: 0.5) == .empty)
    }

    @Test("Value above 5.0 clamps to packed")
    func aboveMaxClampsToPacked() {
        #expect(BusynessLevel(closestTo: 5.5) == .packed)
        #expect(BusynessLevel(closestTo: 6.0) == .packed)
        #expect(BusynessLevel(closestTo: 100.0) == .packed)
    }

    // MARK: - Consistency

    @Test("All 0.5 boundaries round away from zero consistently")
    func allBoundariesRoundConsistently() {
        // After fixing banker's rounding, all .5 values should round UP
        let results = [
            BusynessLevel(closestTo: 1.5),  // → 2
            BusynessLevel(closestTo: 2.5),  // → 3
            BusynessLevel(closestTo: 3.5),  // → 4
            BusynessLevel(closestTo: 4.5),  // → 5
        ]
        let rawValues = results.map(\.rawValue)
        #expect(rawValues == [2, 3, 4, 5])
    }
}
