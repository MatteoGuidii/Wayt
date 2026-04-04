import Foundation
import Amplify
import AWSPluginsCore
import os

/// Generic HTTP client for API Gateway endpoints.
/// Automatically attaches the Cognito auth token.
actor APIClient {

    static let shared = APIClient()

    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let session: URLSession

    /// Cached auth token and its expiry to avoid calling Amplify on every request.
    private var cachedToken: String?
    private var tokenExpiry: Date = .distantPast

    private init() {
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.session = .shared
    }

    // MARK: - GET

    func get<T: Decodable>(
        path: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> T {
        let start = CFAbsoluteTimeGetCurrent()
        Log.api.debug("GET \(path, privacy: .public)")
        let request = try await buildRequest(method: "GET", path: path, queryItems: queryItems)
        let (data, response) = try await executeWithRetry(request: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let ms = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
        Log.api.info("GET \(path, privacy: .public) -> \(status) (\(ms)ms)")
        try validateResponse(response, data: data)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            Log.api.error("GET \(path, privacy: .public) decode failed: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - POST

    func post<Body: Encodable, T: Decodable>(
        path: String,
        body: Body
    ) async throws -> T {
        let start = CFAbsoluteTimeGetCurrent()
        Log.api.debug("POST \(path, privacy: .public)")
        var request = try await buildRequest(method: "POST", path: path)
        request.httpBody = try encoder.encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await executeWithRetry(request: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let ms = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
        Log.api.info("POST \(path, privacy: .public) -> \(status) (\(ms)ms)")
        try validateResponse(response, data: data)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            Log.api.error("POST \(path, privacy: .public) decode failed: \(error.localizedDescription)")
            throw error
        }
    }

    /// POST that returns no meaningful body (just success/failure)
    func post<Body: Encodable>(
        path: String,
        body: Body
    ) async throws {
        let start = CFAbsoluteTimeGetCurrent()
        Log.api.debug("POST \(path, privacy: .public)")
        var request = try await buildRequest(method: "POST", path: path)
        request.httpBody = try encoder.encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await executeWithRetry(request: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let ms = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
        Log.api.info("POST \(path, privacy: .public) -> \(status) (\(ms)ms)")
        try validateResponse(response, data: data)
    }

    // MARK: - PUT

    func put<Body: Encodable, T: Decodable>(
        path: String,
        body: Body
    ) async throws -> T {
        let start = CFAbsoluteTimeGetCurrent()
        Log.api.debug("PUT \(path, privacy: .public)")
        var request = try await buildRequest(method: "PUT", path: path)
        request.httpBody = try encoder.encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await executeWithRetry(request: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let ms = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
        Log.api.info("PUT \(path, privacy: .public) -> \(status) (\(ms)ms)")
        try validateResponse(response, data: data)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            Log.api.error("PUT \(path, privacy: .public) decode failed: \(error.localizedDescription)")
            throw error
        }
    }

    func put<Body: Encodable>(
        path: String,
        body: Body
    ) async throws {
        let start = CFAbsoluteTimeGetCurrent()
        Log.api.debug("PUT \(path, privacy: .public)")
        var request = try await buildRequest(method: "PUT", path: path)
        request.httpBody = try encoder.encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (_, response) = try await executeWithRetry(request: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let ms = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
        Log.api.info("PUT \(path, privacy: .public) -> \(status) (\(ms)ms)")
        try validateResponse(response)
    }

    // MARK: - DELETE

    /// DELETE that returns no meaningful body (just success/failure)
    func delete(path: String) async throws {
        let start = CFAbsoluteTimeGetCurrent()
        Log.api.debug("DELETE \(path, privacy: .public)")
        let request = try await buildRequest(method: "DELETE", path: path)
        let (_, response) = try await executeWithRetry(request: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let ms = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
        Log.api.info("DELETE \(path, privacy: .public) -> \(status) (\(ms)ms)")
        try validateResponse(response)
    }

    // MARK: - Image Upload

    /// Uploads raw image data to a presigned S3 URL (no auth header needed).
    func uploadImage(to presignedURL: URL, imageData: Data) async throws {
        let start = CFAbsoluteTimeGetCurrent()
        Log.api.debug("Uploading image (\(imageData.count) bytes)")
        var request = URLRequest(url: presignedURL)
        request.httpMethod = "PUT"
        request.httpBody = imageData
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        let (_, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let ms = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
        Log.api.info("Image upload -> \(status) (\(ms)ms)")
        try validateResponse(response)
    }

    // MARK: - Helpers

    private func buildRequest(
        method: String,
        path: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> URLRequest {
        guard var components = URLComponents(string: AppConstants.apiBaseURL + path) else {
            throw APIError.invalidURL
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15

        // Attach Cognito token
        if let token = try? await fetchAuthToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            Log.auth.notice("Auth token unavailable, proceeding unauthenticated")
        }

        return request
    }

    private func fetchAuthToken() async throws -> String {
        // Return cached token if it's still valid (with 60s buffer before expiry)
        if let cached = cachedToken, Date() < tokenExpiry {
            return cached
        }

        // Timeout prevents a hung Cognito call from blocking all API requests
        let session: AuthSession
        do {
            session = try await withThrowingTaskGroup(of: AuthSession.self) { group in
                group.addTask {
                    try await Amplify.Auth.fetchAuthSession()
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(8))
                    throw APIError.authTimeout
                }
                let result = try await group.next()!
                group.cancelAll()
                return result
            }
        } catch is CancellationError {
            throw APIError.authTimeout
        } catch let error as APIError {
            throw error
        } catch {
            Log.auth.error("Auth session fetch failed: \(error.localizedDescription)")
            throw APIError.unauthorized
        }

        guard let cognitoPlugin = session as? AuthCognitoTokensProvider,
              let tokens = try? cognitoPlugin.getCognitoTokens().get() else {
            // Refresh token likely expired — session exists but tokens can't be obtained
            Log.auth.error("Token retrieval failed — refresh token may be expired")
            invalidateToken()
            throw APIError.unauthorized
        }

        let token = tokens.idToken
        cachedToken = token

        // Decode JWT expiry from the token payload (middle segment)
        let segments = token.split(separator: ".")
        if segments.count >= 2,
           let data = Data(base64Encoded: Self.padBase64(String(segments[1]))),
           let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let exp = payload["exp"] as? TimeInterval {
            tokenExpiry = Date(timeIntervalSince1970: exp).addingTimeInterval(-60)
        } else {
            Log.auth.warning("Failed to parse JWT expiry, using 50-min fallback")
            tokenExpiry = Date().addingTimeInterval(50 * 60)
        }

        return token
    }

    /// Clear cached auth token so the next request fetches a fresh one.
    func invalidateToken() {
        cachedToken = nil
        tokenExpiry = .distantPast
    }

    /// Pad a Base64URL string to standard Base64 length.
    private static func padBase64(_ string: String) -> String {
        var s = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = s.count % 4
        if remainder > 0 {
            s.append(contentsOf: String(repeating: "=", count: 4 - remainder))
        }
        return s
    }

    private func validateResponse(_ response: URLResponse, data: Data = Data()) throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.unknown
        }
        switch http.statusCode {
        case 200...299: return
        case 401:
            // Invalidate cached token on 401 so next request fetches a fresh one
            invalidateToken()
            Log.api.error("Unauthorized (401)")
            throw APIError.unauthorized
        case 429:
            let (reason, retryAfter) = RateLimitReason.from(data: data)
            Log.api.notice("Rate limited (429): \(reason.rawValue, privacy: .public)")
            throw APIError.rateLimited(reason: reason, retryAfter: retryAfter)
        default:
            Log.api.error("Server error (\(http.statusCode))")
            throw APIError.serverError(http.statusCode)
        }
    }

    /// Execute a URLRequest with automatic retry for transient server errors (5xx).
    /// Retries up to 2 times with exponential backoff (200ms, 400ms).
    private func executeWithRetry(request: URLRequest) async throws -> (Data, URLResponse) {
        var lastError: Error?
        for attempt in 0...2 {
            if attempt > 0 {
                let delayMs = 200 * (1 << (attempt - 1))  // 200ms, 400ms
                try await Task.sleep(for: .milliseconds(delayMs))
            }
            do {
                let (data, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode >= 500, attempt < 2 {
                    Log.api.notice("Server error \(http.statusCode), retrying (attempt \(attempt + 1))")
                    lastError = APIError.serverError(http.statusCode)
                    continue
                }
                return (data, response)
            } catch let error as URLError where error.code == .timedOut || error.code == .networkConnectionLost {
                Log.api.notice("Network error, retrying (attempt \(attempt + 1)): \(error.localizedDescription)")
                lastError = error
                continue
            }
        }
        throw lastError ?? APIError.unknown
    }
}

// MARK: - Errors

enum APIError: LocalizedError {
    case invalidURL
    case unauthorized
    case authTimeout
    case rateLimited(reason: RateLimitReason, retryAfter: TimeInterval?)
    case serverError(Int)
    case unknown

    var errorDescription: String? {
        switch self {
        case .invalidURL:            return "Invalid API URL."
        case .unauthorized:          return "Please sign in again."
        case .authTimeout:           return "Authentication timed out."
        case .rateLimited(let reason, _): return reason.userMessage
        case .serverError(let code): return "Server error (\(code))."
        case .unknown:               return "An unexpected error occurred."
        }
    }
}

// MARK: - Rate Limit Reason

enum RateLimitReason: String {
    case cooldown = "COOLDOWN_ACTIVE"
    case velocity = "VELOCITY_LIMIT"
    case dailyCap = "DAILY_LIMIT_REACHED"
    case unknown = "UNKNOWN"

    var userMessage: String {
        switch self {
        case .cooldown:
            return "You reported this venue recently."
        case .velocity:
            return "You're reporting too fast — take a breather. Max 8 reports per 10 minutes."
        case .dailyCap:
            return "Daily report limit reached — come back tomorrow. Max 30 reports per day."
        case .unknown:
            return "Too many requests. Try again shortly."
        }
    }

    nonisolated static func from(data: Data) -> (reason: RateLimitReason, retryAfter: TimeInterval?) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? String,
              let reason = RateLimitReason(rawValue: error) else {
            return (.unknown, nil)
        }
        let retryAfter = (json["retryAfter"] as? NSNumber).map { TimeInterval($0.doubleValue) }
        return (reason, retryAfter)
    }
}
