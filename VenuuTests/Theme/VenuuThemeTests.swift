import Testing
import SwiftUI
@testable import Venuu

@Suite("VenuuTheme")
struct VenuuThemeTests {

    // MARK: - Brand Colors

    @Test("amber is a valid color (non-clear)")
    func amberIsValid() {
        #expect(VenuuTheme.amber != Color.clear)
    }

    @Test("steel is a valid color (non-clear)")
    func steelIsValid() {
        #expect(VenuuTheme.steel != Color.clear)
    }

    @Test("amber and steel are distinct colors")
    func brandColorsAreDistinct() {
        #expect(VenuuTheme.amber != VenuuTheme.steel)
    }

    // MARK: - Busyness Colors

    @Test("All 5 busyness level colors are distinct")
    func busynessColorsAreDistinct() {
        let colors = (1...5).map { VenuuTheme.busynessColor(for: $0) }
        for i in 0..<colors.count {
            for j in (i + 1)..<colors.count {
                #expect(colors[i] != colors[j])
            }
        }
    }

    @Test("Busyness color for out-of-range level returns gray")
    func busynessColorOutOfRangeReturnsGray() {
        #expect(VenuuTheme.busynessColor(for: 0) == Color.gray)
        #expect(VenuuTheme.busynessColor(for: 6) == Color.gray)
    }

    // MARK: - Typography

    @Test("Headline font size is positive")
    func headlineFontExists() {
        let _ = VenuuTheme.headlineFont
    }

    @Test("Body font exists")
    func bodyFontExists() {
        let _ = VenuuTheme.bodyFont
    }

    @Test("Caption font exists")
    func captionFontExists() {
        let _ = VenuuTheme.captionFont
    }

    @Test("Badge font exists")
    func badgeFontExists() {
        let _ = VenuuTheme.badgeFont
    }

    // MARK: - Dimensions

    @Test("cornerRadius is positive")
    func cornerRadiusIsPositive() {
        #expect(VenuuTheme.cornerRadius > 0)
    }

    @Test("markerSize is positive")
    func markerSizeIsPositive() {
        #expect(VenuuTheme.markerSize > 0)
    }

    @Test("cardPadding is positive")
    func cardPaddingIsPositive() {
        #expect(VenuuTheme.cardPadding > 0)
    }

    @Test("chipHeight is positive")
    func chipHeightIsPositive() {
        #expect(VenuuTheme.chipHeight > 0)
    }

    @Test("cornerRadius has expected value of 14")
    func cornerRadiusValue() {
        #expect(VenuuTheme.cornerRadius == 14)
    }

    @Test("markerSize has expected value of 40")
    func markerSizeValue() {
        #expect(VenuuTheme.markerSize == 40)
    }
}
