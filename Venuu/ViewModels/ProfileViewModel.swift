import Combine
import Foundation
import Amplify

@MainActor
final class ProfileViewModel: ObservableObject {

    // MARK: - Published

    @Published var totalReports: Int = 0
    @Published var memberSince: String = ""
    @Published var isLoading: Bool = false

    private var hasLoadedProfile = false

    // MARK: - Load Profile

    func loadProfile() async {
        guard !hasLoadedProfile else { return }
        isLoading = true

        do {
            let profile: UserProfile = try await APIClient.shared.get(path: "/user/profile")
            totalReports = profile.totalReports
            memberSince = profile.joinedAt
            hasLoadedProfile = true
        } catch {
            print("[Profile] Load failed: \(error.localizedDescription)")
        }
        isLoading = false
    }
}

// MARK: - API Model

struct UserProfile: Codable, Sendable {
    let userId: String
    let username: String
    let totalReports: Int
    let joinedAt: String
}
