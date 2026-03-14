import Testing
import Foundation
@testable import Venuu

@Suite("AppConstants")
struct AppConstantsTests {

    @Test("defaultSearchRadius is positive")
    func defaultSearchRadiusIsPositive() {
        #expect(AppConstants.defaultSearchRadius > 0)
    }

    @Test("reportTTL is positive and equals 7200 seconds")
    func reportTTLIsSevenThousandTwoHundred() {
        #expect(AppConstants.reportTTL > 0)
        #expect(AppConstants.reportTTL == 7200)
    }

    @Test("highConfidenceReportCount is at least 2")
    func highConfidenceReportCountAtLeastTwo() {
        #expect(AppConstants.highConfidenceReportCount >= 2)
    }

    @Test("reportBlendWeight is between 0 and 1 exclusive")
    func reportBlendWeightBetweenZeroAndOne() {
        #expect(AppConstants.reportBlendWeight > 0)
        #expect(AppConstants.reportBlendWeight < 1)
    }

    @Test("liveRefreshInterval is positive")
    func liveRefreshIntervalIsPositive() {
        #expect(AppConstants.liveRefreshInterval > 0)
    }

    @Test("maxVisibleVenues is positive")
    func maxVisibleVenuesIsPositive() {
        #expect(AppConstants.maxVisibleVenues > 0)
    }

    @Test("reportCacheTTL is positive")
    func reportCacheTTLIsPositive() {
        #expect(AppConstants.reportCacheTTL > 0)
    }

    @Test("apiBaseURL starts with https://")
    func apiBaseURLIsHTTPS() {
        #expect(AppConstants.apiBaseURL.hasPrefix("https://"))
    }

    @Test("searchThisAreaThreshold is positive")
    func searchThisAreaThresholdIsPositive() {
        #expect(AppConstants.searchThisAreaThreshold > 0)
    }

    @Test("locationDistanceFilter is positive")
    func locationDistanceFilterIsPositive() {
        #expect(AppConstants.locationDistanceFilter > 0)
    }
}
