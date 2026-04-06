import Foundation
import os

// MARK: - Event Types

enum AnalyticsEventType: String, Codable, Sendable {
    case venueView = "venue_view"
    case venueViewEnd = "venue_view_end"
    case search
    case reportSubmit = "report_submit"
    case venueSave = "venue_save"
    case venueUnsave = "venue_unsave"
    case directionsTap = "directions_tap"
    case callTap = "call_tap"
    case websiteTap = "website_tap"
    case shareTap = "share_tap"
    case filterChange = "filter_change"
    case mapInteraction = "map_interaction"
    case detailSheetClose = "detail_sheet_close"
    case lookaroundView = "lookaround_view"
    case reportRejected = "report_rejected"
    case reportDismissed = "report_dismissed"
    case appSession = "app_session"
    case tabSwitch = "tab_switch"
}

struct AnalyticsEvent: Codable, Sendable {
    let eventType: AnalyticsEventType
    let timestamp: Int
    let sessionId: String
    var lat: Double?
    var lng: Double?
    var venueId: String?
    var venueName: String?
    var venueType: String?
    var properties: [String: PropertyValue]?
}

// MARK: - Property Value (heterogeneous JSON)

enum PropertyValue: Codable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(Bool.self) { self = .bool(v) }
        else if let v = try? container.decode(Int.self) { self = .int(v) }
        else if let v = try? container.decode(Double.self) { self = .double(v) }
        else { self = .string(try container.decode(String.self)) }
    }
}

// MARK: - Request/Response Types

private struct IngestRequest: Sendable {
    let events: [AnalyticsEvent]
}

extension IngestRequest: Encodable {
    nonisolated func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(events, forKey: .events)
    }

    private enum CodingKeys: String, CodingKey { case events }
}

private struct IngestResponse: Decodable, Sendable {
    let ingested: Int
}

// MARK: - Analytics Service

actor AnalyticsService {

    static let shared = AnalyticsService()

    private let sessionId = UUID().uuidString
    private var buffer: [AnalyticsEvent] = []
    private var flushTask: Task<Void, Never>?
    private let maxBufferSize = 20
    private let flushInterval: TimeInterval = 60
    private let maxOfflineQueue = 500
    private let offlineKey = "wayt_analytics_offline_queue"

    private init() {
        Task { await self.startFlushTimer() }
    }

    // MARK: - Public API

    func track(
        _ eventType: AnalyticsEventType,
        venueId: String? = nil,
        venueName: String? = nil,
        venueType: String? = nil,
        lat: Double? = nil,
        lng: Double? = nil,
        properties: [String: PropertyValue]? = nil
    ) {
        let event = AnalyticsEvent(
            eventType: eventType,
            timestamp: Int(Date().timeIntervalSince1970 * 1000),
            sessionId: sessionId,
            lat: lat,
            lng: lng,
            venueId: venueId,
            venueName: venueName,
            venueType: venueType,
            properties: properties
        )
        buffer.append(event)
        Log.analytics.debug("Tracked \(eventType.rawValue, privacy: .public) (buffer: \(self.buffer.count))")

        if buffer.count >= maxBufferSize {
            flush()
        }
    }

    func onBackground() {
        flush()
    }

    // MARK: - Flush

    private func flush() {
        guard !buffer.isEmpty else { return }
        let batch = buffer
        buffer.removeAll()

        Task { [batch] in
            await send(batch)
        }
    }

    private func send(_ events: [AnalyticsEvent]) async {
        do {
            let body = IngestRequest(events: events)
            let _: IngestResponse = try await APIClient.shared.post(
                path: "/v1/analytics/events",
                body: body
            )
            Log.analytics.info("Flushed \(events.count) events")

            // Drain offline queue on success
            await drainOfflineQueue()
        } catch {
            Log.analytics.error("Flush failed, queueing offline: \(error.localizedDescription)")
            saveToOfflineQueue(events)
        }
    }

    // MARK: - Offline Queue

    private func saveToOfflineQueue(_ events: [AnalyticsEvent]) {
        var existing = loadOfflineQueue()
        existing.append(contentsOf: events)
        if existing.count > maxOfflineQueue {
            existing = Array(existing.suffix(maxOfflineQueue))
        }
        if let data = try? JSONEncoder().encode(existing) {
            UserDefaults.standard.set(data, forKey: offlineKey)
        }
    }

    private func loadOfflineQueue() -> [AnalyticsEvent] {
        guard let data = UserDefaults.standard.data(forKey: offlineKey) else { return [] }
        return (try? JSONDecoder().decode([AnalyticsEvent].self, from: data)) ?? []
    }

    private func drainOfflineQueue() async {
        let queued = loadOfflineQueue()
        guard !queued.isEmpty else { return }
        UserDefaults.standard.removeObject(forKey: offlineKey)

        // Send in batches of 50
        for chunk in stride(from: 0, to: queued.count, by: 50) {
            let batch = Array(queued[chunk..<min(chunk + 50, queued.count)])
            do {
                let body = IngestRequest(events: batch)
                let _: IngestResponse = try await APIClient.shared.post(
                    path: "/v1/analytics/events",
                    body: body
                )
                Log.analytics.info("Drained \(batch.count) offline events")
            } catch {
                // Re-queue remaining
                let remaining = Array(queued[chunk...])
                saveToOfflineQueue(remaining)
                break
            }
        }
    }

    // MARK: - Timer

    private func startFlushTimer() {
        flushTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.flushInterval ?? 60))
                await self?.flush()
            }
        }
    }
}
