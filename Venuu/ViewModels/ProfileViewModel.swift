import Combine
import Foundation
import Amplify

@MainActor
final class ProfileViewModel: ObservableObject {

    // MARK: - Published

    @Published var username: String
    @Published var totalReports: Int = 0
    @Published var memberSince: String = ""
    @Published var isLoading: Bool = false

    let onSignOut: () -> Void

    private var hasLoadedProfile = false

    // MARK: - Init

    init(username: String, onSignOut: @escaping () -> Void) {
        self.username = username
        self.onSignOut = onSignOut
    }

    // MARK: - Load Profile

    func loadProfile() async {
        guard !hasLoadedProfile else { return }
        isLoading = true

        do {
            let user = try await Amplify.Auth.getCurrentUser()
            username = user.username

            // Try to fetch profile from API
            let profile: UserProfile = try await APIClient.shared.get(path: "/user/profile")
            totalReports = profile.totalReports
            memberSince = profile.joinedAt
            hasLoadedProfile = true
        } catch {
            // Graceful fallback — profile features are supplementary
            print("[Profile] Load failed: \(error.localizedDescription)")
        }
        isLoading = false
    }

    // MARK: - Sign Out

    func signOut() {
        onSignOut()
    }
}

// MARK: - API Model

struct UserProfile: Codable, Sendable {
    let userId: String
    let username: String
    let totalReports: Int
    let joinedAt: String
}
