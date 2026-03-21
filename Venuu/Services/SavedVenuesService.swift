import Foundation
import os

/// Networking + local cache layer for saved venues.
struct SavedVenuesService {

    private let cacheKey = "savedVenueIDs"
    private let venuesCacheKey = "savedVenuesCache"

    // MARK: - Load from API

    func loadSavedVenues() async throws -> [SavedVenue] {
        Log.saved.debug("Loading saved venues from API")
        let response: ListSavedVenuesResponse = try await APIClient.shared.get(
            path: "/user/saved-venues"
        )
        Log.saved.info("Loaded \(response.venues.count) saved venues")
        let ids = response.venues.map(\.venueId)
        persistIDs(Set(ids))
        persistVenues(response.venues)
        return response.venues
    }

    // MARK: - Save

    func saveVenue(
        venueId: String,
        venueName: String,
        categoryRaw: String,
        lat: Double,
        lng: Double,
        address: String?
    ) async throws {
        let body = SaveVenueBody(
            venueId: venueId,
            venueName: venueName,
            categoryRaw: categoryRaw,
            lat: lat,
            lng: lng,
            address: address
        )
        Log.saved.info("Saving venue \(venueId, privacy: .public)")
        try await APIClient.shared.post(path: "/user/saved-venues", body: body)
    }

    // MARK: - Unsave

    func unsaveVenue(venueId: String) async throws {
        Log.saved.info("Unsaving venue \(venueId, privacy: .public)")
        let body = UnsaveVenueBody(venueId: venueId)
        try await APIClient.shared.post(path: "/user/saved-venues/remove", body: body)
    }

    // MARK: - Local Cache (UserDefaults)

    func loadCachedIDs() -> Set<String> {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let ids = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        Log.saved.debug("Loaded \(ids.count) cached venue IDs")
        return Set(ids)
    }

    func persistIDs(_ ids: Set<String>) {
        if let data = try? JSONEncoder().encode(Array(ids)) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }

    // MARK: - Full Venues Cache (UserDefaults)

    func loadCachedVenues() -> [SavedVenue] {
        guard let data = UserDefaults.standard.data(forKey: venuesCacheKey),
              let venues = try? JSONDecoder().decode([SavedVenue].self, from: data) else {
            return []
        }
        Log.saved.debug("Loaded \(venues.count) cached venues")
        return venues
    }

    func persistVenues(_ venues: [SavedVenue]) {
        if let data = try? JSONEncoder().encode(venues) {
            UserDefaults.standard.set(data, forKey: venuesCacheKey)
        }
    }

    func clearCache() {
        UserDefaults.standard.removeObject(forKey: cacheKey)
        UserDefaults.standard.removeObject(forKey: venuesCacheKey)
    }
}

// MARK: - API Models

private struct SaveVenueBody: Codable, Sendable {
    let venueId: String
    let venueName: String
    let categoryRaw: String
    let lat: Double
    let lng: Double
    let address: String?
}

private struct UnsaveVenueBody: Codable, Sendable {
    let venueId: String
}

private struct ListSavedVenuesResponse: Codable, Sendable {
    let venues: [SavedVenue]
}
