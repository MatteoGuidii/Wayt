import Foundation
import CoreLocation
import UIKit

/// Calculates clustering thresholds based on visual marker overlap at current zoom level
struct VisualClusterCalculator {

    /// Marker visual size in points (approximate height of venue marker pill)
    private let markerSizePoints: CGFloat

    /// Screen scale factor for high-DPI displays
    private let screenScale: CGFloat

    /// Overlap percentage threshold (0.0 - 1.0) - markers overlapping more than this will cluster
    private let overlapThreshold: Double

    init(
        markerSize: CGFloat = 40,
        screenScale: CGFloat = UIScreen.main.scale,
        overlapThreshold: Double = 0.7
    ) {
        self.markerSizePoints = markerSize
        self.screenScale = screenScale
        self.overlapThreshold = overlapThreshold
    }

    /// Calculates the clustering threshold in meters based on current map zoom level
    /// - Parameters:
    ///   - latitudeDelta: The latitude span of the visible map region
    ///   - screenHeight: The height of the viewport in points
    /// - Returns: Distance in meters at which markers should be clustered
    func calculateClusteringThreshold(
        latitudeDelta: Double,
        screenHeight: CGFloat
    ) -> CLLocationDistance {
        // Convert latitude delta to meters at the equator
        // One degree of latitude ≈ 111,000 meters
        let metersPerDegree: Double = 111_000
        let visibleMeters = latitudeDelta * metersPerDegree

        // Calculate meters per point at this zoom level
        let metersPerPoint = visibleMeters / Double(screenHeight)

        // Calculate the distance in meters that our marker occupies
        let markerSizeMeters = metersPerPoint * Double(markerSizePoints)

        // Apply overlap threshold - only cluster when markers overlap by this percentage
        let clusterThreshold = markerSizeMeters * overlapThreshold

        // Enforce minimum threshold to prevent excessive clustering at high zoom
        return max(clusterThreshold, 20)
    }

    /// Convenience method that uses screen bounds for height
    func calculateClusteringThreshold(latitudeDelta: Double) -> CLLocationDistance {
        return calculateClusteringThreshold(
            latitudeDelta: latitudeDelta,
            screenHeight: UIScreen.main.bounds.height
        )
    }
}
