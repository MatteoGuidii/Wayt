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

    /// Local report history for the activity feed (persisted in UserDefaults).
    @Published var reportHistory: [ReportHistoryEntry] = []

    /// Dates on which the user submitted at least one report (ISO "yyyy-MM-dd" strings).
    @Published var reportDates: [String] = []

    /// Set briefly when the user crosses a rank boundary, triggers celebration overlay.
    @Published var rankUpEvent: UserRank?

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
        static let reportHistory = "wayt_profile_reportHistory"
        static let reportDates = "wayt_profile_reportDates"
        static let lastCelebratedRank = "wayt_profile_lastCelebratedRank"
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // MARK: - Init

    init() {
        loadFromCache()

        NotificationCenter.default.publisher(for: .reportSubmitted)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self else { return }

                // Detect rank-up before incrementing
                let previousRank = UserRank.from(reports: self.totalReports)
                self.totalReports += 1
                let newRank = UserRank.from(reports: self.totalReports)
                self.cacheValue(self.totalReports, forKey: CacheKey.totalReports)

                // Check for rank-up
                let lastCelebrated = UserDefaults.standard.integer(forKey: CacheKey.lastCelebratedRank)
                if newRank != previousRank, newRank.rawValue > lastCelebrated {
                    self.rankUpEvent = newRank
                    UserDefaults.standard.set(newRank.rawValue, forKey: CacheKey.lastCelebratedRank)
                }

                // Record report in local history
                if let userInfo = notification.userInfo,
                   let venueName = userInfo["venueName"] as? String,
                   let venueType = userInfo["venueType"] as? String,
                   let busynessLevel = userInfo["busynessLevel"] as? Int {
                    let entry = ReportHistoryEntry(
                        venueName: venueName,
                        venueType: venueType,
                        busynessLevel: busynessLevel,
                        timestamp: Date()
                    )
                    self.reportHistory.insert(entry, at: 0)
                    // Keep last 100 entries
                    if self.reportHistory.count > 100 {
                        self.reportHistory = Array(self.reportHistory.prefix(100))
                    }
                    self.saveReportHistory()
                }

                // Track report date for streaks
                let today = Self.dateFormatter.string(from: Date())
                if !self.reportDates.contains(today) {
                    self.reportDates.append(today)
                    // Keep last 90 entries to cover 12-window (84-day) streak range
                    if self.reportDates.count > 90 {
                        self.reportDates = Array(self.reportDates.suffix(90))
                    }
                    self.cacheValue(self.reportDates, forKey: CacheKey.reportDates)
                }

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

        // Load report history
        if let historyData = defaults.data(forKey: CacheKey.reportHistory),
           let history = try? JSONDecoder().decode([ReportHistoryEntry].self, from: historyData) {
            // Prune entries older than 90 days
            let cutoff = Date().addingTimeInterval(-90 * 24 * 60 * 60)
            reportHistory = history.filter { $0.timestamp > cutoff }
        }

        // Load streak dates
        if let dates = defaults.stringArray(forKey: CacheKey.reportDates) {
            reportDates = dates
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

    private func saveReportHistory() {
        if let data = try? JSONEncoder().encode(reportHistory) {
            UserDefaults.standard.set(data, forKey: CacheKey.reportHistory)
        }
    }

    // MARK: - Computed: Streak (Rolling 7-Day Windows)

    /// Current streak in weeks. Uses rolling 7-day windows from today:
    /// - Window 0: today → 6 days ago
    /// - Window 1: 7 → 13 days ago, etc.
    /// Streak = number of consecutive windows (starting from 0) with at least one report.
    /// 1 report in the last 7 days = streak of 1. Go 7+ days without reporting = streak breaks.
    var currentStreak: Int {
        let dateSet = Set(reportDates)
        var streak = 0

        for windowIndex in 0..<12 {
            let windowDates = datesInWindow(windowIndex)
            if windowDates.contains(where: { dateSet.contains($0) }) {
                streak += 1
            } else {
                break
            }
        }
        return streak
    }

    /// The last 4 rolling 7-day windows (oldest first).
    /// Each element is the set of "yyyy-MM-dd" date strings for that window.
    var last4Weeks: [[String]] {
        (0..<4).reversed().map { datesInWindow($0) }
    }

    /// Returns all "yyyy-MM-dd" strings for a rolling 7-day window.
    /// Window 0 = today → 6 days ago, window 1 = 7 → 13 days ago, etc.
    private func datesInWindow(_ index: Int) -> [String] {
        let calendar = Calendar.current
        let startOffset = index * 7
        return (startOffset..<startOffset + 7).compactMap { dayOffset in
            guard let d = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) else { return nil }
            return Self.dateFormatter.string(from: d)
        }
    }

    // MARK: - Computed: Impact

    /// Number of distinct venues reported from local history.
    var distinctVenueCount: Int {
        Set(reportHistory.map(\.venueName)).count
    }

    /// The venue name the user has reported most (only if 2+ reports there).
    /// Breaks ties by alphabetical order for stable results.
    var topVenueName: String? {
        let counts = Dictionary(grouping: reportHistory, by: \.venueName)
            .mapValues(\.count)
        guard let max = counts.values.max(), max >= 2 else { return nil }
        return counts
            .filter { $0.value == max }
            .keys
            .sorted()
            .first
    }

    /// The category of the user's most reported venue.
    var topVenueCategory: VenueCategory? {
        guard let topName = topVenueName else { return nil }
        return reportHistory.first(where: { $0.venueName == topName })?.category
    }

    // MARK: - Computed: Contextual Nudge

    var contextualNudge: String? {
        let rank = UserRank.from(reports: totalReports)
        if let next = rank.nextRank {
            let remaining = next.minReports - totalReports
            if remaining <= 3 {
                return "Just \(remaining) more report\(remaining == 1 ? "" : "s") to \(next.title)!"
            }
        }
        let streak = currentStreak
        if streak >= 2 {
            return "\(streak)-week streak — keep it up!"
        }
        return nil
    }

    private func clearCache() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: CacheKey.totalReports)
        defaults.removeObject(forKey: CacheKey.memberSince)
        defaults.removeObject(forKey: CacheKey.displayName)
        defaults.removeObject(forKey: CacheKey.profileImageUrl)
        defaults.removeObject(forKey: CacheKey.reportHistory)
        defaults.removeObject(forKey: CacheKey.reportDates)
        defaults.removeObject(forKey: CacheKey.lastCelebratedRank)
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
        reportHistory = []
        reportDates = []
        rankUpEvent = nil
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
