import Combine
import Foundation
import Amplify

@MainActor
final class ProfileViewModel: ObservableObject {

    // MARK: - Published

    @Published var totalReports: Int = 0
    @Published var memberSince: String = ""
    @Published var displayName: String?
    @Published var profileImageUrl: String?
    @Published var isLoading: Bool = false
    @Published var loadError: Bool = false
    @Published var isUpdatingProfile: Bool = false
    @Published var isSavingImage: Bool = false
    @Published var showFirstTimeNamePrompt: Bool = false

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
            displayName = profile.displayName
            profileImageUrl = profile.profileImageUrl

            showFirstTimeNamePrompt = (profile.displayName == nil)
        } catch {
            loadError = true
            print("[Profile] Load failed: \(error.localizedDescription)")
        }
        isLoading = false
    }

    // MARK: - Update Display Name

    func updateDisplayName(_ name: String) async -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, trimmed.count <= 30 else { return false }

        isUpdatingProfile = true
        defer { isUpdatingProfile = false }

        do {
            let body = UpdateProfileBody(displayName: trimmed)
            let _: UpdateProfileResponse = try await APIClient.shared.put(
                path: "/user/profile",
                body: body
            )
            displayName = trimmed
            showFirstTimeNamePrompt = false
            return true
        } catch {
            print("[Profile] Update failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Upload Profile Image

    func uploadProfileImage(_ imageData: Data) async -> Bool {
        isSavingImage = true
        defer { isSavingImage = false }

        do {
            let response: UploadURLResponse = try await APIClient.shared.get(
                path: "/user/profile/upload-url"
            )

            guard let uploadURL = URL(string: response.uploadUrl) else { return false }
            try await APIClient.shared.uploadImage(to: uploadURL, imageData: imageData)

            // Reload profile to get the new presigned GET URL
            await loadProfile()
            return true
        } catch {
            print("[Profile] Image upload failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Reset

    /// Clears all profile data. Call on sign-out so stale data from the
    /// previous user is never shown to the next one.
    func reset() {
        totalReports = 0
        memberSince = ""
        displayName = nil
        profileImageUrl = nil
        loadError = false
        showFirstTimeNamePrompt = false
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

// MARK: - API Models

struct UserProfile: Codable, Sendable {
    let userId: String
    let totalReports: Int
    let joinedAt: String
    let displayName: String?
    let profileImageUrl: String?
}

private struct UpdateProfileBody: Codable, Sendable {
    let displayName: String
}

private struct UpdateProfileResponse: Codable, Sendable {
    let message: String
    let displayName: String
}

private struct UploadURLResponse: Codable, Sendable {
    let uploadUrl: String
    let imageKey: String
}
