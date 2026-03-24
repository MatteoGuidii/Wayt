import Amplify
import Combine
import Foundation
import os

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

    /// Locally cached profile image data for instant display.
    @Published var cachedImageData: Data?

    private var cancellables = Set<AnyCancellable>()
    private var hasLoadedFromCache = false
    /// True after the first successful API fetch — prevents duplicate loads.
    private(set) var hasLoadedFromAPI = false
    /// Debounce task for syncProfile — avoids stale server counts overwriting optimistic increments.
    private var syncTask: Task<Void, Never>?

    // MARK: - Cache Keys

    private enum CacheKey {
        static let totalReports = "wayt_profile_totalReports"
        static let memberSince = "wayt_profile_memberSince"
        static let displayName = "wayt_profile_displayName"
        static let profileImageUrl = "wayt_profile_imageUrl"
    }

    // MARK: - Init

    init() {
        loadFromCache()

        NotificationCenter.default.publisher(for: .reportSubmitted)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.totalReports += 1
                self.cacheValue(self.totalReports, forKey: CacheKey.totalReports)
                self.syncTask?.cancel()
                self.syncTask = Task {
                    try? await Task.sleep(for: .seconds(2))
                    guard !Task.isCancelled else { return }
                    await self.syncProfile()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Local Cache

    private func loadFromCache() {
        let defaults = UserDefaults.standard
        let cached = defaults.integer(forKey: CacheKey.totalReports)
        let member = defaults.string(forKey: CacheKey.memberSince)
        let name = defaults.string(forKey: CacheKey.displayName)
        let imageUrl = defaults.string(forKey: CacheKey.profileImageUrl)

        // Only apply if we have cached data (memberSince is set on first load)
        if let member, !member.isEmpty {
            totalReports = cached
            memberSince = member
            displayName = name
            profileImageUrl = imageUrl
            hasLoadedFromCache = true
        }

        // Load cached profile image from disk
        if let data = Self.loadCachedImage() {
            cachedImageData = data
        }
    }

    private func saveToCache() {
        let defaults = UserDefaults.standard
        defaults.set(totalReports, forKey: CacheKey.totalReports)
        defaults.set(memberSince, forKey: CacheKey.memberSince)
        defaults.set(displayName, forKey: CacheKey.displayName)
        defaults.set(profileImageUrl, forKey: CacheKey.profileImageUrl)
    }

    private func cacheValue(_ value: Any?, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    private func clearCache() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: CacheKey.totalReports)
        defaults.removeObject(forKey: CacheKey.memberSince)
        defaults.removeObject(forKey: CacheKey.displayName)
        defaults.removeObject(forKey: CacheKey.profileImageUrl)
        Self.deleteCachedImage()
        cachedImageData = nil
        hasLoadedFromCache = false
    }

    // MARK: - Profile Image Disk Cache

    private static var imageCacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("wayt_profile_avatar.jpg")
    }

    private static func loadCachedImage() -> Data? {
        try? Data(contentsOf: imageCacheURL)
    }

    private static func saveCachedImage(_ data: Data) {
        let url = imageCacheURL
        Task.detached {
            try? data.write(to: url, options: .atomic)
        }
    }

    private static func deleteCachedImage() {
        let url = imageCacheURL
        Task.detached {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Downloads and caches the profile image from the presigned URL.
    private func cacheProfileImage() async {
        guard let urlString = profileImageUrl,
              let url = URL(string: urlString) else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            Self.saveCachedImage(data)
            cachedImageData = data
        } catch {
            // Non-critical — AsyncImage will still work as fallback
        }
    }

    // MARK: - Load Profile

    /// Fetches the user profile from the API. Shows cached data instantly,
    /// then refreshes from network in the background.
    /// Safe to call multiple times — skips if already loaded from API.
    func loadProfile(force: Bool = false) async {
        guard !hasLoadedFromAPI || force else { return }
        // Only show loading spinner if we have no cached data
        if !hasLoadedFromCache {
            isLoading = true
        }
        loadError = false

        do {
            let profile: UserProfile = try await APIClient.shared.get(path: "/user/profile")
            totalReports = profile.totalReports
            memberSince = profile.joinedAt
            displayName = profile.displayName
            profileImageUrl = profile.profileImageUrl
            hasLoadedFromAPI = true
            saveToCache()
            Log.profile.info("Profile loaded: \(profile.totalReports) reports")

            // Cache profile image to disk if we don't have one yet
            if profile.profileImageUrl != nil, cachedImageData == nil {
                Task { await cacheProfileImage() }
            }

            showFirstTimeNamePrompt = (profile.displayName == nil)
        } catch {
            // Only show error if we had no cached data to display
            if !hasLoadedFromCache {
                loadError = true
            }
            Log.profile.error("Profile load failed: \(error.localizedDescription)")
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
            saveToCache()
            Log.profile.info("Display name updated")
            return true
        } catch {
            Log.profile.error("Profile update failed: \(error.localizedDescription)")
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

            // Immediately cache the uploaded image locally for instant display
            Self.saveCachedImage(imageData)
            cachedImageData = imageData

            Log.profile.info("Profile image uploaded")
            // Reload profile to get the new presigned GET URL
            await loadProfile(force: true)
            return true
        } catch {
            Log.profile.error("Image upload failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Reset

    /// Clears all profile data and local cache. Call on sign-out so stale
    /// data from the previous user is never shown to the next one.
    func reset() {
        totalReports = 0
        memberSince = ""
        displayName = nil
        profileImageUrl = nil
        loadError = false
        showFirstTimeNamePrompt = false
        hasLoadedFromAPI = false
        clearCache()
    }

    // MARK: - Sync After Report

    /// Background refresh after a report submission — keeps the optimistic +1
    /// if the network call fails.
    private func syncProfile() async {
        do {
            let profile: UserProfile = try await APIClient.shared.get(path: "/user/profile")
            totalReports = profile.totalReports
            cacheValue(totalReports, forKey: CacheKey.totalReports)
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
