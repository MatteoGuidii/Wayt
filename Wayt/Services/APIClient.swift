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
        try validateResponse(response)
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
        try validateResponse(response)
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
        let (_, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let ms = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
        Log.api.info("POST \(path, privacy: .public) -> \(status) (\(ms)ms)")
        try validateResponse(response)
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
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let ms = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
        Log.api.info("PUT \(path, privacy: .public) -> \(status) (\(ms)ms)")
        try validateResponse(response)
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
        let (_, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let ms = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
        Log.api.info("PUT \(path, privacy: .public) -> \(status) (\(ms)ms)")
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

        let session = try await Amplify.Auth.fetchAuthSession()
        guard let cognitoPlugin = session as? AuthCognitoTokensProvider,
              let tokens = try? cognitoPlugin.getCognitoTokens().get() else {
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
            // Refresh 60 seconds before actual expiry
            tokenExpiry = Date(timeIntervalSince1970: exp).addingTimeInterval(-60)
        } else {
            // Fallback: cache for 50 minutes (Cognito tokens are typically valid for 1 hour)
            tokenExpiry = Date().addingTimeInterval(50 * 60)
        }

        return token
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

    private func validateResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.unknown
        }
        switch http.statusCode {
        case 200...299: return
        case 401:
            // Invalidate cached token on 401 so next request fetches a fresh one
            cachedToken = nil
            tokenExpiry = .distantPast
            Log.api.error("Unauthorized (401)")
            throw APIError.unauthorized
        case 429:
            Log.api.notice("Rate limited (429)")
            throw APIError.rateLimited
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
    case rateLimited
    case serverError(Int)
    case unknown

    var errorDescription: String? {
        switch self {
        case .invalidURL:            return "Invalid API URL."
        case .unauthorized:          return "Please sign in again."
        case .rateLimited:           return "Too many requests. Try again shortly."
        case .serverError(let code): return "Server error (\(code))."
        case .unknown:               return "An unexpected error occurred."
        }
    }
}
