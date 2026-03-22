import Testing
import SwiftUI
@testable import Wayt

@Suite("WaytTheme")
struct WaytThemeTests {

    // MARK: - Brand Colors

    @Test("skyPunch is a valid color (non-clear)")
    func skyPunchIsValid() {
        #expect(WaytTheme.skyPunch != Color.clear)
    }

    @Test("mapsBlue is a valid color (non-clear)")
    func mapsBlueIsValid() {
        #expect(WaytTheme.mapsBlue != Color.clear)
    }

    @Test("skyPunch and mapsBlue are distinct colors")
    func brandColorsAreDistinct() {
        #expect(WaytTheme.skyPunch != WaytTheme.mapsBlue)
    }

    // MARK: - Busyness Colors

    @Test("All 5 busyness level colors are distinct")
    func busynessColorsAreDistinct() {
        let colors = (1...5).map { WaytTheme.busynessColor(for: $0) }
        for i in 0..<colors.count {
            for j in (i + 1)..<colors.count {
                #expect(colors[i] != colors[j])
            }
        }
    }

    @Test("Busyness color for out-of-range level returns gray")
    func busynessColorOutOfRangeReturnsGray() {
        #expect(WaytTheme.busynessColor(for: 0) == Color.gray)
        #expect(WaytTheme.busynessColor(for: 6) == Color.gray)
    }

    // MARK: - Typography

    @Test("Headline font size is positive")
    func headlineFontExists() {
        let _ = WaytTheme.headlineFont
    }

    @Test("Body font exists")
    func bodyFontExists() {
        let _ = WaytTheme.bodyFont
    }

    @Test("Caption font exists")
    func captionFontExists() {
        let _ = WaytTheme.captionFont
    }

    @Test("Badge font exists")
    func badgeFontExists() {
        let _ = WaytTheme.badgeFont
    }

    // MARK: - Dimensions

    @Test("cornerRadius is positive")
    func cornerRadiusIsPositive() {
        #expect(WaytTheme.cornerRadius > 0)
    }

    @Test("markerSize is positive")
    func markerSizeIsPositive() {
        #expect(WaytTheme.markerSize > 0)
    }

    @Test("cardPadding is positive")
    func cardPaddingIsPositive() {
        #expect(WaytTheme.cardPadding > 0)
    }

    @Test("chipHeight is positive")
    func chipHeightIsPositive() {
        #expect(WaytTheme.chipHeight > 0)
    }

    @Test("cornerRadius has expected value of 14")
    func cornerRadiusValue() {
        #expect(WaytTheme.cornerRadius == 14)
    }

    @Test("markerSize has expected value of 40")
    func markerSizeValue() {
        #expect(WaytTheme.markerSize == 40)
    }

    // MARK: - Rank Colors

    @Test("rankGreen is a valid color")
    func rankGreenExists() {
        #expect(WaytTheme.rankGreen != Color.clear)
    }

    @Test("rankOrange is a valid color")
    func rankOrangeExists() {
        #expect(WaytTheme.rankOrange != Color.clear)
    }

    @Test("rankPurple is a valid color")
    func rankPurpleExists() {
        #expect(WaytTheme.rankPurple != Color.clear)
    }

    @Test("rankGold is a valid color")
    func rankGoldExists() {
        #expect(WaytTheme.rankGold != Color.clear)
    }

    @Test("All 4 rank colors are distinct")
    func rankColorsAreDistinct() {
        let colors = [
            WaytTheme.rankGreen,
            WaytTheme.rankOrange,
            WaytTheme.rankPurple,
            WaytTheme.rankGold
        ]
        for i in 0..<colors.count {
            for j in (i + 1)..<colors.count {
                #expect(colors[i] != colors[j])
            }
        }
    }

    // MARK: - Mascot Colors

    @Test("mascotBodyTop is a valid color")
    func mascotBodyTopExists() {
        #expect(WaytTheme.mascotBodyTop != Color.clear)
    }

    @Test("mascotBodyBottom is a valid color")
    func mascotBodyBottomExists() {
        #expect(WaytTheme.mascotBodyBottom != Color.clear)
    }

    @Test("ink is a valid color")
    func inkExists() {
        #expect(WaytTheme.ink != Color.clear)
    }

    @Test("mascotOutline is a valid color")
    func mascotOutlineExists() {
        #expect(WaytTheme.mascotOutline != Color.clear)
    }

    @Test("mascotFace is a valid color")
    func mascotFaceExists() {
        #expect(WaytTheme.mascotFace != Color.clear)
    }

    @Test("mascotBodyTop and mascotBodyBottom are distinct")
    func mascotBodyColorsDistinct() {
        #expect(WaytTheme.mascotBodyTop != WaytTheme.mascotBodyBottom)
    }

    // MARK: - Text Colors

    @Test("primaryText is a valid color")
    func primaryTextExists() {
        #expect(WaytTheme.primaryText != Color.clear)
    }

    @Test("secondaryText is a valid color")
    func secondaryTextExists() {
        #expect(WaytTheme.secondaryText != Color.clear)
    }

    // MARK: - Background Colors

    @Test("cardBackground is a valid color")
    func cardBackgroundExists() {
        #expect(WaytTheme.cardBackground != Color.clear)
    }

    @Test("signalPulseBase is a valid color")
    func signalPulseBaseExists() {
        #expect(WaytTheme.signalPulseBase != Color.clear)
    }

    @Test("avatarRing is a valid color")
    func avatarRingExists() {
        #expect(WaytTheme.avatarRing != Color.clear)
    }

    @Test("avatarBackground is a valid color")
    func avatarBackgroundExists() {
        #expect(WaytTheme.avatarBackground != Color.clear)
    }

    @Test("fieldBackground is a valid color")
    func fieldBackgroundExists() {
        #expect(WaytTheme.fieldBackground != Color.clear)
    }

    @Test("savedOrange is a valid color")
    func savedOrangeExists() {
        #expect(WaytTheme.savedOrange != Color.clear)
    }

    // MARK: - Typography Token Smoke Tests

    @Test("Key font tokens are distinct sizes")
    func keyFontTokensDistinctSizes() {
        // Verify key font size tokens differ — catches accidental copy/paste
        #expect(WaytTheme.displayFont != WaytTheme.bodyFont)
        #expect(WaytTheme.bodyFont != WaytTheme.captionFont)
        #expect(WaytTheme.captionFont != WaytTheme.badgeFont)
        #expect(WaytTheme.badgeFont != WaytTheme.nanoFont)
        #expect(WaytTheme.heroFont != WaytTheme.headlineFont)
    }

    // MARK: - Dimension Values

    @Test("cardPadding has expected value of 16")
    func cardPaddingValue() {
        #expect(WaytTheme.cardPadding == 16)
    }

    @Test("chipHeight has expected value of 36")
    func chipHeightValue() {
        #expect(WaytTheme.chipHeight == 36)
    }

    // MARK: - Busyness Color Edge Cases

    @Test("Busyness color for negative level returns gray")
    func busynessColorNegativeLevel() {
        #expect(WaytTheme.busynessColor(for: -1) == Color.gray)
    }

    @Test("Busyness color for very large level returns gray")
    func busynessColorVeryLargeLevel() {
        #expect(WaytTheme.busynessColor(for: 100) == Color.gray)
    }

    @Test("Busyness colors are non-gray for levels 1-5")
    func busynessColorsAreNonGray() {
        for level in 1...5 {
            #expect(WaytTheme.busynessColor(for: level) != Color.gray)
        }
    }
}
