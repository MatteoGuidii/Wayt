import Foundation
import os

@MainActor
final class LeaderboardService {

    static let shared = LeaderboardService()

    // MARK: - Cache

    private var cachedResponse: LeaderboardResponse?
    private var cacheTimestamp: Date = .distantPast
    private var cachedGeoKey: String = ""

    private static let cacheTTL: TimeInterval = 300

    // MARK: - Fetch

    func fetchLeaderboard(
        latitude: Double,
        longitude: Double
    ) async throws -> LeaderboardResponse {
        let geoKey = "\(Int(latitude * 5)),\(Int(longitude * 5))"

        if let cached = cachedResponse,
           geoKey == cachedGeoKey,
           Date().timeIntervalSince(cacheTimestamp) < Self.cacheTTL {
            return cached
        }

        let queryItems = [
            URLQueryItem(name: "lat", value: String(latitude)),
            URLQueryItem(name: "lng", value: String(longitude)),
        ]

        let response: LeaderboardResponse = try await APIClient.shared.get(
            path: "/leaderboard/nearby",
            queryItems: queryItems
        )

        cachedResponse = response
        cacheTimestamp = Date()
        cachedGeoKey = geoKey

        Log.profile.info("Leaderboard fetched: \(response.leaderboard.count) entries")
        return response
    }

    func invalidateCache() {
        cachedResponse = nil
        cacheTimestamp = .distantPast
    }
}

// MARK: - Response Models

struct LeaderboardResponse: Codable, Sendable {
    let weekKey: String
    let leaderboard: [LeaderboardEntry]
    let currentUserEntry: CurrentUserEntry?
}

struct LeaderboardEntry: Codable, Identifiable, Sendable {
    let rank: Int
    let userId: String?
    let displayName: String
    let reportCount: Int
    let isCurrentUser: Bool

    var id: Int { rank }
}

struct CurrentUserEntry: Codable, Sendable {
    let rank: Int
    let reportCount: Int
}
