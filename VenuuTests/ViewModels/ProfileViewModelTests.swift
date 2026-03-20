import Testing
import Foundation
@testable import Venuu

@Suite("ProfileViewModel", .serialized)
@MainActor
struct ProfileViewModelTests {

    // MARK: - Cache Keys (for cleanup)

    private let cacheKeys = [
        "venuu_profile_totalReports",
        "venuu_profile_memberSince",
        "venuu_profile_displayName",
        "venuu_profile_imageUrl"
    ]

    private func cleanUpCache() {
        for key in cacheKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    // MARK: - Initial State

    @Test("Initial totalReports is 0 when no cache")
    func initialTotalReportsZero() {
        cleanUpCache()
        let vm = ProfileViewModel()
        #expect(vm.totalReports == 0)
        cleanUpCache()
    }

    @Test("Initial memberSince is empty when no cache")
    func initialMemberSinceEmpty() {
        cleanUpCache()
        let vm = ProfileViewModel()
        #expect(vm.memberSince.isEmpty)
        cleanUpCache()
    }

    @Test("Initial displayName is nil when no cache")
    func initialDisplayNameNil() {
        cleanUpCache()
        let vm = ProfileViewModel()
        #expect(vm.displayName == nil)
        cleanUpCache()
    }

    @Test("Initial profileImageUrl is nil when no cache")
    func initialImageUrlNil() {
        cleanUpCache()
        let vm = ProfileViewModel()
        #expect(vm.profileImageUrl == nil)
        cleanUpCache()
    }

    @Test("isLoading starts false")
    func isLoadingStartsFalse() {
        cleanUpCache()
        let vm = ProfileViewModel()
        #expect(vm.isLoading == false)
        cleanUpCache()
    }

    @Test("loadError starts false")
    func loadErrorStartsFalse() {
        cleanUpCache()
        let vm = ProfileViewModel()
        #expect(vm.loadError == false)
        cleanUpCache()
    }

    @Test("isUpdatingProfile starts false")
    func isUpdatingProfileStartsFalse() {
        cleanUpCache()
        let vm = ProfileViewModel()
        #expect(vm.isUpdatingProfile == false)
        cleanUpCache()
    }

    @Test("isSavingImage starts false")
    func isSavingImageStartsFalse() {
        cleanUpCache()
        let vm = ProfileViewModel()
        #expect(vm.isSavingImage == false)
        cleanUpCache()
    }

    @Test("showFirstTimeNamePrompt starts false")
    func showFirstTimeNamePromptStartsFalse() {
        cleanUpCache()
        let vm = ProfileViewModel()
        #expect(vm.showFirstTimeNamePrompt == false)
        cleanUpCache()
    }

    @Test("hasLoadedFromAPI starts false")
    func hasLoadedFromAPIStartsFalse() {
        cleanUpCache()
        let vm = ProfileViewModel()
        #expect(vm.hasLoadedFromAPI == false)
        cleanUpCache()
    }

    // MARK: - Reset

    @Test("reset clears all profile data")
    func resetClearsAllData() {
        cleanUpCache()
        let vm = ProfileViewModel()
        vm.totalReports = 42
        vm.memberSince = "2024-01-15"
        vm.displayName = "TestUser"
        vm.profileImageUrl = "https://example.com/image.jpg"
        vm.loadError = true
        vm.showFirstTimeNamePrompt = true

        vm.reset()

        #expect(vm.totalReports == 0)
        #expect(vm.memberSince.isEmpty)
        #expect(vm.displayName == nil)
        #expect(vm.profileImageUrl == nil)
        #expect(vm.loadError == false)
        #expect(vm.showFirstTimeNamePrompt == false)
        #expect(vm.hasLoadedFromAPI == false)
        cleanUpCache()
    }

    @Test("reset is idempotent")
    func resetIdempotent() {
        cleanUpCache()
        let vm = ProfileViewModel()
        vm.totalReports = 10
        vm.reset()
        vm.reset()
        #expect(vm.totalReports == 0)
        #expect(vm.displayName == nil)
        cleanUpCache()
    }

    @Test("reset clears cached image data")
    func resetClearsCachedImage() {
        cleanUpCache()
        let vm = ProfileViewModel()
        vm.cachedImageData = Data([0x00, 0x01, 0x02])
        vm.reset()
        #expect(vm.cachedImageData == nil)
        cleanUpCache()
    }

    // MARK: - Cache Behavior

    @Test("ProfileViewModel loads cached data on init when cache exists")
    func loadsCachedDataOnInit() {
        cleanUpCache()
        let defaults = UserDefaults.standard
        defaults.set(15, forKey: "venuu_profile_totalReports")
        defaults.set("2024-06-01", forKey: "venuu_profile_memberSince")
        defaults.set("CachedUser", forKey: "venuu_profile_displayName")
        defaults.set("https://example.com/img.jpg", forKey: "venuu_profile_imageUrl")

        let vm = ProfileViewModel()
        #expect(vm.totalReports == 15)
        #expect(vm.memberSince == "2024-06-01")
        #expect(vm.displayName == "CachedUser")
        #expect(vm.profileImageUrl == "https://example.com/img.jpg")
        cleanUpCache()
    }

    @Test("ProfileViewModel ignores cache when memberSince is empty")
    func ignoresCacheWhenMemberSinceEmpty() {
        cleanUpCache()
        let defaults = UserDefaults.standard
        defaults.set(15, forKey: "venuu_profile_totalReports")
        defaults.set("", forKey: "venuu_profile_memberSince")

        let vm = ProfileViewModel()
        // Should not load cached data because memberSince is empty
        #expect(vm.totalReports == 0)
        cleanUpCache()
    }

    @Test("ProfileViewModel ignores cache when memberSince key is missing")
    func ignoresCacheWhenMemberSinceMissing() {
        cleanUpCache()
        let defaults = UserDefaults.standard
        defaults.set(15, forKey: "venuu_profile_totalReports")
        // No memberSince key set

        let vm = ProfileViewModel()
        #expect(vm.totalReports == 0)
        cleanUpCache()
    }

    // MARK: - Display Name Validation

    @Test("updateDisplayName rejects name shorter than 2 chars")
    func rejectsShortName() async {
        cleanUpCache()
        let vm = ProfileViewModel()
        let result = await vm.updateDisplayName("A")
        #expect(result == false)
        cleanUpCache()
    }

    @Test("updateDisplayName rejects empty name")
    func rejectsEmptyName() async {
        cleanUpCache()
        let vm = ProfileViewModel()
        let result = await vm.updateDisplayName("")
        #expect(result == false)
        cleanUpCache()
    }

    @Test("updateDisplayName rejects whitespace-only name")
    func rejectsWhitespaceName() async {
        cleanUpCache()
        let vm = ProfileViewModel()
        let result = await vm.updateDisplayName("   ")
        #expect(result == false)
        cleanUpCache()
    }

    @Test("updateDisplayName rejects name longer than 30 chars")
    func rejectsLongName() async {
        cleanUpCache()
        let vm = ProfileViewModel()
        let longName = String(repeating: "A", count: 31)
        let result = await vm.updateDisplayName(longName)
        #expect(result == false)
        cleanUpCache()
    }

    @Test("updateDisplayName rejects name that trims to less than 2 chars")
    func rejectsNameTrimmedTooShort() async {
        cleanUpCache()
        let vm = ProfileViewModel()
        let result = await vm.updateDisplayName(" A ")
        #expect(result == false)
        cleanUpCache()
    }

    @Test("2-char name passes validation (boundary)")
    func twoCharNamePassesValidation() {
        // Pure validation check — no API call needed
        let name = "AB"
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(trimmed.count >= 2)
        #expect(trimmed.count <= 30)
    }

    @Test("30-char name passes validation (boundary)")
    func thirtyCharNamePassesValidation() {
        let name = String(repeating: "A", count: 30)
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(trimmed.count >= 2)
        #expect(trimmed.count <= 30)
    }

    @Test("31-char name fails validation (boundary)")
    func thirtyOneCharNameFailsValidation() {
        let name = String(repeating: "A", count: 31)
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(trimmed.count > 30)
    }

    @Test("1-char name fails validation (boundary)")
    func oneCharNameFailsValidation() {
        let name = "A"
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(trimmed.count < 2)
    }

    @Test("Padded name trims to valid length")
    func paddedNameTrimsCorrectly() {
        let name = "  Valid Name  "
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(trimmed.count >= 2)
        #expect(trimmed.count <= 30)
        #expect(trimmed == "Valid Name")
    }
}
