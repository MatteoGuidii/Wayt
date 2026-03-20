import Testing
import Foundation
@testable import Venuu

@Suite("BusynessConfidence")
struct BusynessConfidenceTests {

    // MARK: - Raw Values

    @Test("none has raw value 'none'")
    func noneRawValue() {
        #expect(BusynessConfidence.none.rawValue == "none")
    }

    @Test("estimated has raw value 'estimated'")
    func estimatedRawValue() {
        #expect(BusynessConfidence.estimated.rawValue == "estimated")
    }

    @Test("low has raw value 'low'")
    func lowRawValue() {
        #expect(BusynessConfidence.low.rawValue == "low")
    }

    @Test("high has raw value 'high'")
    func highRawValue() {
        #expect(BusynessConfidence.high.rawValue == "high")
    }

    // MARK: - Label

    @Test("none label is empty string")
    func noneLabelEmpty() {
        #expect(BusynessConfidence.none.label.isEmpty)
    }

    @Test("estimated label is 'Estimated'")
    func estimatedLabel() {
        #expect(BusynessConfidence.estimated.label == "Estimated")
    }

    @Test("low label is 'Few reports'")
    func lowLabel() {
        #expect(BusynessConfidence.low.label == "Few reports")
    }

    @Test("high label is 'Reported'")
    func highLabel() {
        #expect(BusynessConfidence.high.label == "Reported")
    }

    // MARK: - Init from Raw Value

    @Test("Init from valid raw values succeeds")
    func initFromValidRawValues() {
        #expect(BusynessConfidence(rawValue: "none") == BusynessConfidence.none)
        #expect(BusynessConfidence(rawValue: "estimated") == BusynessConfidence.estimated)
        #expect(BusynessConfidence(rawValue: "low") == BusynessConfidence.low)
        #expect(BusynessConfidence(rawValue: "high") == BusynessConfidence.high)
    }

    @Test("Init from invalid raw value returns nil")
    func initFromInvalidRawValue() {
        #expect(BusynessConfidence(rawValue: "medium") == nil)
        #expect(BusynessConfidence(rawValue: "") == nil)
        #expect(BusynessConfidence(rawValue: "HIGH") == nil)
    }
}

// MARK: - String.nilIfEmpty

@Suite("String.nilIfEmpty")
struct StringNilIfEmptyTests {

    @Test("Empty string returns nil")
    func emptyReturnsNil() {
        let result: String? = "".nilIfEmpty
        #expect(result == nil)
    }

    @Test("Non-empty string returns self")
    func nonEmptyReturnsSelf() {
        let result: String? = "hello".nilIfEmpty
        #expect(result == "hello")
    }

    @Test("Whitespace string returns self (not nil)")
    func whitespaceReturnsSelf() {
        let result: String? = "  ".nilIfEmpty
        #expect(result == "  ")
    }

    @Test("Single character returns self")
    func singleCharReturnsSelf() {
        let result: String? = "a".nilIfEmpty
        #expect(result == "a")
    }
}

// MARK: - UserProfile Codable

@Suite("UserProfile Codable")
struct UserProfileCodableTests {

    @Test("UserProfile decodes from complete JSON")
    func decodesCompleteJSON() throws {
        let json = """
        {
            "userId": "user-123",
            "totalReports": 42,
            "joinedAt": "2024-06-01",
            "displayName": "TestUser",
            "profileImageUrl": "https://example.com/img.jpg"
        }
        """.data(using: .utf8)!
        let profile = try JSONDecoder().decode(UserProfile.self, from: json)
        #expect(profile.userId == "user-123")
        #expect(profile.totalReports == 42)
        #expect(profile.joinedAt == "2024-06-01")
        #expect(profile.displayName == "TestUser")
        #expect(profile.profileImageUrl == "https://example.com/img.jpg")
    }

    @Test("UserProfile decodes with nil displayName")
    func decodesNilDisplayName() throws {
        let json = """
        {
            "userId": "user-123",
            "totalReports": 0,
            "joinedAt": "2024-06-01",
            "displayName": null,
            "profileImageUrl": null
        }
        """.data(using: .utf8)!
        let profile = try JSONDecoder().decode(UserProfile.self, from: json)
        #expect(profile.displayName == nil)
        #expect(profile.profileImageUrl == nil)
    }

    @Test("UserProfile round-trips through JSON")
    func codableRoundTrip() throws {
        let original = UserProfile(
            userId: "u1",
            totalReports: 10,
            joinedAt: "2024-01-01",
            displayName: "User",
            profileImageUrl: "https://example.com/a.jpg"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(UserProfile.self, from: data)
        #expect(decoded.userId == original.userId)
        #expect(decoded.totalReports == original.totalReports)
        #expect(decoded.joinedAt == original.joinedAt)
        #expect(decoded.displayName == original.displayName)
        #expect(decoded.profileImageUrl == original.profileImageUrl)
    }

    @Test("UserProfile with zero reports decodes correctly")
    func zeroReports() throws {
        let json = """
        {
            "userId": "new-user",
            "totalReports": 0,
            "joinedAt": "2025-03-19",
            "displayName": null,
            "profileImageUrl": null
        }
        """.data(using: .utf8)!
        let profile = try JSONDecoder().decode(UserProfile.self, from: json)
        #expect(profile.totalReports == 0)
    }
}

// MARK: - FusedEstimateResponse Codable

@Suite("FusedEstimateResponse Codable")
struct FusedEstimateResponseCodableTests {

    @Test("Decodes complete response")
    func decodesComplete() throws {
        let json = """
        {
            "busynessScore": 0.65,
            "confidence": "high",
            "reportCount": 5,
            "waitMinutes": 15
        }
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(FusedEstimateResponse.self, from: json)
        #expect(response.busynessScore == 0.65)
        #expect(response.confidence == "high")
        #expect(response.reportCount == 5)
        #expect(response.waitMinutes == 15)
    }

    @Test("Decodes with nil waitMinutes")
    func decodesNilWait() throws {
        let json = """
        {
            "busynessScore": 0.2,
            "confidence": "low",
            "reportCount": 1,
            "waitMinutes": null
        }
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(FusedEstimateResponse.self, from: json)
        #expect(response.waitMinutes == nil)
    }

    @Test("busynessScore at boundaries decodes correctly")
    func busynessScoreBoundaries() throws {
        let jsonZero = """
        {"busynessScore": 0.0, "confidence": "none", "reportCount": 0, "waitMinutes": null}
        """.data(using: .utf8)!
        let zero = try JSONDecoder().decode(FusedEstimateResponse.self, from: jsonZero)
        #expect(zero.busynessScore == 0.0)

        let jsonOne = """
        {"busynessScore": 1.0, "confidence": "high", "reportCount": 10, "waitMinutes": null}
        """.data(using: .utf8)!
        let one = try JSONDecoder().decode(FusedEstimateResponse.self, from: jsonOne)
        #expect(one.busynessScore == 1.0)
    }

    @Test("Round-trip through JSON preserves values")
    func roundTrip() throws {
        let original = FusedEstimateResponse(
            busynessScore: 0.75,
            confidence: "estimated",
            reportCount: 3,
            waitMinutes: 20
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FusedEstimateResponse.self, from: data)
        #expect(decoded.busynessScore == original.busynessScore)
        #expect(decoded.confidence == original.confidence)
        #expect(decoded.reportCount == original.reportCount)
        #expect(decoded.waitMinutes == original.waitMinutes)
    }
}
