import MapKit
import SwiftUI

/// Async LookAround thumbnail that fetches a scene, snapshots it to a static image,
/// and caches the result. Shows a placeholder while loading and falls back to a
/// category-colored icon when no coverage is available.
struct LookAroundThumbnail: View {

    let coordinate: CLLocationCoordinate2D
    let category: VenueCategory
    let size: CGSize

    @State private var snapshot: UIImage?
    @State private var loaded = false

    var body: some View {
        ZStack {
            if let snapshot {
                Image(uiImage: snapshot)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .clipped()
            } else if loaded {
                // No LookAround coverage — category fallback
                fallbackView
            } else {
                // Loading placeholder
                Rectangle()
                    .fill(Color(.tertiarySystemBackground))
                    .overlay {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(.secondary)
                    }
            }
        }
        .frame(width: size.width, height: size.height)
        .task(id: cacheKey) {
            await loadSnapshot()
        }
    }

    private var fallbackView: some View {
        ZStack {
            LinearGradient(
                colors: [category.color.opacity(0.15), category.color.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: category.icon)
                .font(.system(size: min(size.width, size.height) * 0.35))
                .foregroundStyle(category.color.opacity(0.6))
        }
    }

    private var cacheKey: String {
        String(format: "%.5f,%.5f", coordinate.latitude, coordinate.longitude)
    }

    private func loadSnapshot() async {
        let cache = LookAroundSnapshotCache.shared

        // Check image cache first
        if let cached = cache.image(for: coordinate) {
            snapshot = cached
            loaded = true
            return
        }

        // Known miss — skip network
        if LookAroundCache.shared.isKnownMiss(for: coordinate) {
            loaded = true
            return
        }

        // Try scene cache, else fetch
        let scene: MKLookAroundScene?
        if let cached = LookAroundCache.shared.scene(for: coordinate) {
            scene = cached
        } else {
            let request = MKLookAroundSceneRequest(coordinate: coordinate)
            do {
                scene = try await request.scene
                if let scene {
                    LookAroundCache.shared.store(scene, for: coordinate)
                } else {
                    LookAroundCache.shared.storeMiss(for: coordinate)
                }
            } catch {
                loaded = true
                return
            }
        }

        guard let scene else {
            loaded = true
            return
        }

        // Snapshot the scene to a static image
        let options = MKLookAroundSnapshotter.Options()
        options.size = CGSize(
            width: size.width * UIScreen.main.scale,
            height: size.height * UIScreen.main.scale
        )
        let snapshotter = MKLookAroundSnapshotter(scene: scene, options: options)
        do {
            let snapshotImage = try await snapshotter.snapshot
            cache.store(snapshotImage.image, for: coordinate)
            snapshot = snapshotImage.image
        } catch {
            // Snapshot failed — show fallback
        }
        loaded = true
    }
}

// MARK: - Snapshot Image Cache

/// Caches rendered LookAround snapshot images (UIImage) to avoid re-snapshotting.
@MainActor
final class LookAroundSnapshotCache {

    static let shared = LookAroundSnapshotCache()

    private var cache: [String: UIImage] = [:]
    private let maxEntries = 60

    private init() {}

    func image(for coordinate: CLLocationCoordinate2D) -> UIImage? {
        cache[key(for: coordinate)]
    }

    func store(_ image: UIImage, for coordinate: CLLocationCoordinate2D) {
        if cache.count >= maxEntries {
            let keysToRemove = Array(cache.keys.prefix(maxEntries / 4))
            keysToRemove.forEach { cache.removeValue(forKey: $0) }
        }
        cache[key(for: coordinate)] = image
    }

    private func key(for coordinate: CLLocationCoordinate2D) -> String {
        String(format: "%.5f,%.5f", coordinate.latitude, coordinate.longitude)
    }
}
