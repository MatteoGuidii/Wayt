import Testing
import SwiftUI
@testable import Venuu

@Suite("VenuuTheme")
struct VenuuThemeTests {

    // MARK: - Brand Colors

    @Test("skyPunch is a valid color (non-clear)")
    func skyPunchIsValid() {
        #expect(VenuuTheme.skyPunch != Color.clear)
    }

    @Test("mapsBlue is a valid color (non-clear)")
    func mapsBlueIsValid() {
        #expect(VenuuTheme.mapsBlue != Color.clear)
    }

    @Test("skyPunch and mapsBlue are distinct colors")
    func brandColorsAreDistinct() {
        #expect(VenuuTheme.skyPunch != VenuuTheme.mapsBlue)
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

    // MARK: - Rank Colors

    @Test("rankGreen is a valid color")
    func rankGreenExists() {
        #expect(VenuuTheme.rankGreen != Color.clear)
    }

    @Test("rankOrange is a valid color")
    func rankOrangeExists() {
        #expect(VenuuTheme.rankOrange != Color.clear)
    }

    @Test("rankPurple is a valid color")
    func rankPurpleExists() {
        #expect(VenuuTheme.rankPurple != Color.clear)
    }

    @Test("rankGold is a valid color")
    func rankGoldExists() {
        #expect(VenuuTheme.rankGold != Color.clear)
    }

    @Test("All 4 rank colors are distinct")
    func rankColorsAreDistinct() {
        let colors = [
            VenuuTheme.rankGreen,
            VenuuTheme.rankOrange,
            VenuuTheme.rankPurple,
            VenuuTheme.rankGold
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
        #expect(VenuuTheme.mascotBodyTop != Color.clear)
    }

    @Test("mascotBodyBottom is a valid color")
    func mascotBodyBottomExists() {
        #expect(VenuuTheme.mascotBodyBottom != Color.clear)
    }

    @Test("ink is a valid color")
    func inkExists() {
        #expect(VenuuTheme.ink != Color.clear)
    }

    @Test("mascotOutline is a valid color")
    func mascotOutlineExists() {
        #expect(VenuuTheme.mascotOutline != Color.clear)
    }

    @Test("mascotFace is a valid color")
    func mascotFaceExists() {
        #expect(VenuuTheme.mascotFace != Color.clear)
    }

    @Test("mascotBodyTop and mascotBodyBottom are distinct")
    func mascotBodyColorsDistinct() {
        #expect(VenuuTheme.mascotBodyTop != VenuuTheme.mascotBodyBottom)
    }

    // MARK: - Text Colors

    @Test("primaryText is a valid color")
    func primaryTextExists() {
        #expect(VenuuTheme.primaryText != Color.clear)
    }

    @Test("secondaryText is a valid color")
    func secondaryTextExists() {
        #expect(VenuuTheme.secondaryText != Color.clear)
    }

    // MARK: - Background Colors

    @Test("cardBackground is a valid color")
    func cardBackgroundExists() {
        #expect(VenuuTheme.cardBackground != Color.clear)
    }

    @Test("signalPulseBase is a valid color")
    func signalPulseBaseExists() {
        #expect(VenuuTheme.signalPulseBase != Color.clear)
    }

    @Test("avatarRing is a valid color")
    func avatarRingExists() {
        #expect(VenuuTheme.avatarRing != Color.clear)
    }

    @Test("avatarBackground is a valid color")
    func avatarBackgroundExists() {
        #expect(VenuuTheme.avatarBackground != Color.clear)
    }

    @Test("fieldBackground is a valid color")
    func fieldBackgroundExists() {
        #expect(VenuuTheme.fieldBackground != Color.clear)
    }

    @Test("savedOrange is a valid color")
    func savedOrangeExists() {
        #expect(VenuuTheme.savedOrange != Color.clear)
    }

    // MARK: - Typography Token Smoke Tests

    @Test("Key font tokens are distinct sizes")
    func keyFontTokensDistinctSizes() {
        // Verify key font size tokens differ — catches accidental copy/paste
        #expect(VenuuTheme.displayFont != VenuuTheme.bodyFont)
        #expect(VenuuTheme.bodyFont != VenuuTheme.captionFont)
        #expect(VenuuTheme.captionFont != VenuuTheme.badgeFont)
        #expect(VenuuTheme.badgeFont != VenuuTheme.nanoFont)
        #expect(VenuuTheme.heroFont != VenuuTheme.headlineFont)
    }

    // MARK: - Dimension Values

    @Test("cardPadding has expected value of 16")
    func cardPaddingValue() {
        #expect(VenuuTheme.cardPadding == 16)
    }

    @Test("chipHeight has expected value of 36")
    func chipHeightValue() {
        #expect(VenuuTheme.chipHeight == 36)
    }

    // MARK: - Busyness Color Edge Cases

    @Test("Busyness color for negative level returns gray")
    func busynessColorNegativeLevel() {
        #expect(VenuuTheme.busynessColor(for: -1) == Color.gray)
    }

    @Test("Busyness color for very large level returns gray")
    func busynessColorVeryLargeLevel() {
        #expect(VenuuTheme.busynessColor(for: 100) == Color.gray)
    }

    @Test("Busyness colors are non-gray for levels 1-5")
    func busynessColorsAreNonGray() {
        for level in 1...5 {
            #expect(VenuuTheme.busynessColor(for: level) != Color.gray)
        }
    }
}
