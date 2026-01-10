import Foundation
import MapKit

/// Actor that manages query execution with rate limiting, concurrency control, and exponential backoff
/// Prevents hitting Apple's MKLocalSearch rate limits while maximizing throughput
actor QueryExecutor {

    // MARK: - Types

    enum Priority: Comparable {
        case low      // Prefetch, background
        case normal   // Discovery mode
        case high     // Visible region, immediate need
    }

    struct QueryResult: Sendable {
        let venues: [Venue]
        let query: String
        let wasThrottled: Bool
    }

    // MARK: - State

    private var backoffMultiplier: Double = 1.0
    private var lastThrottleTime: Date?
    private var activeRequestCount = 0
    private var requestHistory: [Date] = []

    private let searchService = VenueSearchService()

    // MARK: - Configuration

    private let maxConcurrent = VenueQueryConfiguration.maxConcurrentQueries
    private let baseBackoffSeconds: Double = 5.0
    private let maxBackoffSeconds: Double = 60.0
    private let requestsPerMinuteLimit = 30

    // MARK: - Public API

    /// Execute multiple queries with concurrency control and rate limiting
    /// - Parameters:
    ///   - queries: Array of search queries to execute
    ///   - region: Map region to search within
    ///   - priority: Execution priority (affects throttle behavior)
    ///   - useGrid: Whether to use grid-based search for better coverage
    /// - Returns: Array of discovered venues (deduplicated)
    func execute(
        queries: [String],
        in region: MKCoordinateRegion,
        priority: Priority = .normal,
        useGrid: Bool = true
    ) async throws -> [Venue] {
        // Check if we're in backoff period
        if let waitTime = currentWaitTime() {
            if priority == .high {
                // High priority waits, others throw
                try await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
            } else {
                throw QueryExecutorError.rateLimited(retryAfter: waitTime)
            }
        }

        // Check per-minute request limit
        cleanupOldRequests()
        if requestHistory.count >= requestsPerMinuteLimit {
            let waitTime = 60.0 - Date().timeIntervalSince(requestHistory.first ?? Date())
            throw QueryExecutorError.rateLimited(retryAfter: max(0, waitTime))
        }

        // Execute queries with concurrency control
        let chunks = chunked(queries, into: maxConcurrent)

        var allVenues: [Venue] = []
        var seenKeys = Set<String>()
        var wasThrottled = false

        // Process queries in batches respecting concurrency limit
        for (index, batch) in chunks.enumerated() {
            let batchResults = await executeBatch(batch, region: region, useGrid: useGrid)

            for result in batchResults {
                if result.wasThrottled {
                    wasThrottled = true
                }

                for venue in result.venues {
                    let key = venueKey(for: venue)
                    if !seenKeys.contains(key) {
                        seenKeys.insert(key)
                        allVenues.append(venue)
                    }
                }
            }

            // Small delay between batches to be kind to the API
            if index < chunks.count - 1 {
                try? await Task.sleep(nanoseconds: VenueQueryConfiguration.batchDelayNanoseconds)
            }
        }

        if wasThrottled {
            // Partial results due to throttling
            handleThrottle()
        } else {
            resetBackoff()
        }

        return allVenues
    }

    /// Execute a single query
    func executeSingle(
        query: String,
        in region: MKCoordinateRegion,
        useGrid: Bool = true
    ) async throws -> [Venue] {
        return try await execute(queries: [query], in: region, priority: .normal, useGrid: useGrid)
    }

    /// Get current wait time if throttled, nil otherwise
    func currentWaitTime() -> TimeInterval? {
        guard let throttleTime = lastThrottleTime else { return nil }
        let backoff = baseBackoffSeconds * backoffMultiplier
        let elapsed = Date().timeIntervalSince(throttleTime)
        let remaining = backoff - elapsed
        return remaining > 0 ? remaining : nil
    }

    /// Check if executor is currently rate limited
    func isThrottled() -> Bool {
        return currentWaitTime() != nil
    }

    // MARK: - Private Methods

    private func executeBatch(
        _ queries: [String],
        region: MKCoordinateRegion,
        useGrid: Bool
    ) async -> [QueryResult] {
        await withTaskGroup(of: QueryResult.self) { group in
            for query in queries {
                group.addTask {
                    await self.executeSingleQuery(query, region: region, useGrid: useGrid)
                }
            }

            var results: [QueryResult] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
    }

    private func executeSingleQuery(
        _ query: String,
        region: MKCoordinateRegion,
        useGrid: Bool
    ) async -> QueryResult {
        recordRequest()

        do {
            let venues: [Venue]
            if useGrid {
                venues = try await searchService.searchWithGrid(query: query, region: region)
            } else {
                venues = try await searchService.search(query: query, region: region)
            }
            return QueryResult(venues: venues, query: query, wasThrottled: false)
        } catch let error as NSError {
            if error.domain == "GEOErrorDomain" && error.code == -3 {
                // Rate limited by Apple
                return QueryResult(venues: [], query: query, wasThrottled: true)
            }
            return QueryResult(venues: [], query: query, wasThrottled: false)
        } catch {
            return QueryResult(venues: [], query: query, wasThrottled: false)
        }
    }

    private func handleThrottle() {
        lastThrottleTime = Date()
        backoffMultiplier = min(backoffMultiplier * 2, maxBackoffSeconds / baseBackoffSeconds)
    }

    private func resetBackoff() {
        backoffMultiplier = 1.0
        lastThrottleTime = nil
    }

    private func recordRequest() {
        requestHistory.append(Date())
    }

    private func cleanupOldRequests() {
        let oneMinuteAgo = Date().addingTimeInterval(-60)
        requestHistory.removeAll { $0 < oneMinuteAgo }
    }

    private func venueKey(for venue: Venue) -> String {
        let lat = String(format: "%.5f", venue.coordinate.latitude)
        let lng = String(format: "%.5f", venue.coordinate.longitude)
        return "\(venue.name)_\(lat)_\(lng)"
    }

    private func chunked<T>(_ array: [T], into size: Int) -> [[T]] {
        guard size > 0 else { return [array] }
        return stride(from: 0, to: array.count, by: size).map {
            Array(array[$0..<Swift.min($0 + size, array.count)])
        }
    }
}

// MARK: - Errors

enum QueryExecutorError: LocalizedError {
    case rateLimited(retryAfter: TimeInterval)

    var errorDescription: String? {
        switch self {
        case .rateLimited(let retryAfter):
            return "Rate limited. Please wait \(Int(ceil(retryAfter))) seconds."
        }
    }
}
