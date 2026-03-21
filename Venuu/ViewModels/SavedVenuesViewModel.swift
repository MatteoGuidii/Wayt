import Combine
import CoreLocation
import Foundation
import os

@MainActor
final class SavedVenuesViewModel: ObservableObject {

    // MARK: - Published

    @Published var savedVenueIDs: Set<String> = []
    @Published var savedVenues: [SavedVenue] = []
    @Published var isLoading = false

    // MARK: - Private

    private let service = SavedVenuesService()
    private var hasLoadedFromAPI = false

    // MARK: - Init

    init() {
        // Load cached data synchronously for instant UI — no grey/empty flash
        savedVenueIDs = service.loadCachedIDs()
        savedVenues = service.loadCachedVenues()
    }

    // MARK: - Load from API

    func loadSavedVenues(force: Bool = false) async {
        guard !hasLoadedFromAPI || force else { return }
        // Only show loading indicator when there's nothing cached to display
        let showSpinner = savedVenues.isEmpty
        if showSpinner { isLoading = true }
        defer { if showSpinner { isLoading = false } }

        do {
            let venues = try await service.loadSavedVenues()
            savedVenues = venues
            savedVenueIDs = Set(venues.map(\.venueId))
            hasLoadedFromAPI = true
        } catch {
            Log.saved.error("Load saved venues failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Toggle Save

    func toggleSave(for venue: Venue) async {
        let venueId = venue.id

        if savedVenueIDs.contains(venueId) {
            // Optimistic remove
            savedVenueIDs.remove(venueId)
            savedVenues.removeAll { $0.venueId == venueId }
            persistIDs()

            do {
                try await service.unsaveVenue(venueId: venueId)
            } catch {
                // Revert on failure
                savedVenueIDs.insert(venueId)
                await loadSavedVenues(force: true)
                Log.saved.error("Unsave failed, reverting: \(error.localizedDescription)")
            }
        } else {
            // Optimistic add
            savedVenueIDs.insert(venueId)
            persistIDs()

            do {
                try await service.saveVenue(
                    venueId: venueId,
                    venueName: venue.name,
                    categoryRaw: venue.category.rawValue,
                    lat: venue.coordinate.latitude,
                    lng: venue.coordinate.longitude,
                    address: venue.address
                )
                // Refresh full list to get the server-created SavedVenue
                await loadSavedVenues(force: true)
            } catch {
                // Revert on failure
                savedVenueIDs.remove(venueId)
                persistIDs()
                Log.saved.error("Save failed, reverting: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Unsave by ID (for saved venues list)

    func toggleSaveById(_ venueId: String) async {
        savedVenueIDs.remove(venueId)
        savedVenues.removeAll { $0.venueId == venueId }
        persistIDs()

        do {
            try await service.unsaveVenue(venueId: venueId)
        } catch {
            // Refresh from server on failure
            await loadSavedVenues(force: true)
            Log.saved.error("Unsave by ID failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Query

    func isSaved(_ venueId: String) -> Bool {
        savedVenueIDs.contains(venueId)
    }

    // MARK: - Reset

    func reset() {
        savedVenueIDs = []
        savedVenues = []
        hasLoadedFromAPI = false
        service.clearCache()
    }

    // MARK: - Helpers

    private func persistIDs() {
        service.persistIDs(savedVenueIDs)
        service.persistVenues(savedVenues)
    }
}
