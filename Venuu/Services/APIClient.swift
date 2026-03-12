import Foundation
import Amplify
import AWSPluginsCore

/// Generic HTTP client for API Gateway endpoints.
/// Automatically attaches the Cognito auth token.
actor APIClient {

    static let shared = APIClient()

    private let baseURL: String = "https://36w1q7mbqg.execute-api.ca-central-1.amazonaws.com/dev"
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let session: URLSession

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
        let request = try await buildRequest(method: "GET", path: path, queryItems: queryItems)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response)
        return try decoder.decode(T.self, from: data)
    }

    // MARK: - POST

    func post<Body: Encodable, T: Decodable>(
        path: String,
        body: Body
    ) async throws -> T {
        var request = try await buildRequest(method: "POST", path: path)
        request.httpBody = try encoder.encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: request)
        try validateResponse(response)
        return try decoder.decode(T.self, from: data)
    }

    /// POST that returns no meaningful body (just success/failure)
    func post<Body: Encodable>(
        path: String,
        body: Body
    ) async throws {
        var request = try await buildRequest(method: "POST", path: path)
        request.httpBody = try encoder.encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (_, response) = try await session.data(for: request)
        try validateResponse(response)
    }

    // MARK: - Helpers

    private func buildRequest(
        method: String,
        path: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> URLRequest {
        guard var components = URLComponents(string: baseURL + path) else {
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
        }

        return request
    }

    private func fetchAuthToken() async throws -> String {
        let session = try await Amplify.Auth.fetchAuthSession()
        guard let cognitoPlugin = session as? AuthCognitoTokensProvider,
              let tokens = try? cognitoPlugin.getCognitoTokens().get() else {
            throw APIError.unauthorized
        }
        return tokens.idToken
    }

    private func validateResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.unknown
        }
        switch http.statusCode {
        case 200...299: return
        case 401: throw APIError.unauthorized
        case 429: throw APIError.rateLimited
        default: throw APIError.serverError(http.statusCode)
        }
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
