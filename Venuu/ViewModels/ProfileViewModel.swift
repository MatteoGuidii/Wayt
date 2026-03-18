import Combine
import Foundation
import Amplify

@MainActor
final class ProfileViewModel: ObservableObject {

    // MARK: - Published

    @Published var totalReports: Int = 0
    @Published var memberSince: String = ""
    @Published var isLoading: Bool = false
    @Published var loadError: Bool = false

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init() {
        NotificationCenter.default.publisher(for: .reportSubmitted)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.totalReports += 1
                Task { await self.syncProfile() }
            }
            .store(in: &cancellables)
    }

    // MARK: - Load Profile

    /// Fetches the user profile from the API. Safe to call multiple times
    /// (e.g. every time the profile tab appears).
    func loadProfile() async {
        isLoading = true
        loadError = false

        do {
            let profile: UserProfile = try await APIClient.shared.get(path: "/user/profile")
            totalReports = profile.totalReports
            memberSince = profile.joinedAt
        } catch {
            loadError = true
            print("[Profile] Load failed: \(error.localizedDescription)")
        }
        isLoading = false
    }

    // MARK: - Reset

    /// Clears all profile data. Call on sign-out so stale data from the
    /// previous user is never shown to the next one.
    func reset() {
        totalReports = 0
        memberSince = ""
        loadError = false
    }

    // MARK: - Sync After Report

    /// Background refresh after a report submission — keeps the optimistic +1
    /// if the network call fails.
    private func syncProfile() async {
        do {
            let profile: UserProfile = try await APIClient.shared.get(path: "/user/profile")
            totalReports = profile.totalReports
        } catch {
            // Optimistic increment already applied — keep it
        }
    }
}

// MARK: - API Model

struct UserProfile: Codable, Sendable {
    let userId: String
    let totalReports: Int
    let joinedAt: String
}
