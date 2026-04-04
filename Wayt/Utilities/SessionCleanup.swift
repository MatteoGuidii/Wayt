import os

/// Centralized session cleanup for sign-out and account deletion.
@MainActor
enum SessionCleanup {

    static func perform(
        profileViewModel: ProfileViewModel,
        savedVenuesVM: SavedVenuesViewModel,
        mapViewModel: MapViewModel,
        authState: AuthState
    ) async {
        profileViewModel.reset()
        savedVenuesVM.reset()

        LeaderboardService.shared.invalidateCache()
        ReportService.shared.invalidateCache()
        FusionService.shared.invalidateCache()

        mapViewModel.resetForSignOut()

        // Actor-isolated — requires await
        await APIClient.shared.invalidateToken()

        // Must be last — triggers UI transition to auth flow
        authState.didSignOut()

        Log.auth.info("Session cleanup complete")
    }
}
