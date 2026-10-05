import Foundation

struct APIError: LocalizedError {
    let status: Int
    let code: String
    let message: String
    var errorDescription: String? { message }
}

private struct ErrorEnvelope: Decodable { struct Body: Decodable { let message: String; let code: String? }; let error: Body }

/// Thin async/await wrapper around the Fuel Station REST API.
final class APIClient: @unchecked Sendable {
    static let shared = APIClient()

    var token: String?
    /// Called when the server rejects the session (expired token, PIN changed, blocked).
    var onUnauthorized: (@MainActor () -> Void)?

    var baseURL: URL {
        if let override = UserDefaults.standard.string(forKey: "apiBaseURL"), let url = URL(string: override) { return url }
        let raw = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String ?? "http://localhost:4000/api/v1"
        return URL(string: raw)!
    }

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config)
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            if let date = withFraction.date(from: s) ?? plain.date(from: s) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad date \(s)"))
        }
        return d
    }()

    static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    func get<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        try await request("GET", path, query: query)
    }

    func post<T: Decodable>(_ path: String, _ body: [String: Any] = [:]) async throws -> T {
        try await request("POST", path, body: body)
    }

    func patch<T: Decodable>(_ path: String, _ body: [String: Any]) async throws -> T {
        try await request("PATCH", path, body: body)
    }

    /// For endpoints whose response body we don't need (204 etc).
    func send(_ method: String, _ path: String, _ body: [String: Any]? = nil) async throws {
        _ = try await raw(method, path, body: body)
    }

    func request<T: Decodable>(_ method: String, _ path: String, query: [String: String] = [:], body: [String: Any]? = nil) async throws -> T {
        let data = try await raw(method, path, query: query, body: body)
        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            #if DEBUG
            print("Decode \(T.self) failed:", error)
            #endif
            throw APIError(status: 0, code: "DECODE", message: "Unexpected response from server")
        }
    }

    func raw(_ method: String, _ path: String, query: [String: String] = [:], body: [String: Any]? = nil) async throws -> Data {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var req = URLRequest(url: components.url!)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw APIError(status: 0, code: "NETWORK", message: "Can't reach the station server. Check your internet connection.")
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let env = try? Self.decoder.decode(ErrorEnvelope.self, from: data)
            let err = APIError(status: status, code: env?.error.code ?? "HTTP_\(status)", message: env?.error.message ?? "Something went wrong (\(status))")
            if status == 401, token != nil, err.code == "TOKEN_INVALID" || err.code == "UNAUTHORIZED" {
                await onUnauthorized?()
            }
            throw err
        }
        return data
    }
}

struct EmptyResponse: Decodable {}

extension Date {
    var iso: String { APIClient.isoFormatter.string(from: self) }
}
