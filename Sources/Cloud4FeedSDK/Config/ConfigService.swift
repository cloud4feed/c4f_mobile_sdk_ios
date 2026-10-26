import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Sends HTTP requests. Abstracted so tests can run without network.
protocol HTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionTransport: HTTPTransport {
    var session: URLSession = .shared

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        // dataTask + continuation works on every platform (async URLSession APIs differ on Linux).
        try await withCheckedThrowingContinuation { continuation in
            let task = session.dataTask(with: request) { data, response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let http = response as? HTTPURLResponse {
                    continuation.resume(returning: (data ?? Data(), http))
                } else {
                    continuation.resume(throwing: ConfigServiceError.invalidResponse)
                }
            }
            task.resume()
        }
    }
}

enum ConfigServiceError: Error, Equatable {
    case http(statusCode: Int)
    case invalidResponse
}

/// Request body of `get-mobilesdk-surveys` (same shape as Android).
struct ConfigRequestBody: Codable, Equatable {
    struct Param: Codable, Equatable {
        let paramName: String
        let paramValue: String
    }

    let apiKey: String
    /// Epoch milliseconds as a string (the backend expects a string, not a number).
    let timestamp: String
    let sdkVersion: String
    let sdkParams: [Param]
}

/// Fetches the survey configuration (Android: `SurveyApiService`).
final class ConfigService {
    private let apiKey: String
    private let transport: HTTPTransport
    private let endpoint: URL
    private let maxRetries: Int
    private let retryDelay: TimeInterval
    private let now: () -> Date

    init(apiKey: String,
         transport: HTTPTransport = URLSessionTransport(),
         endpoint: URL = SDKConstants.configEndpoint,
         maxRetries: Int = SDKConstants.apiMaxRetries,
         retryDelay: TimeInterval = 1,
         now: @escaping () -> Date = Date.init) {
        self.apiKey = apiKey
        self.transport = transport
        self.endpoint = endpoint
        self.maxRetries = maxRetries
        self.retryDelay = retryDelay
        self.now = now
    }

    func makeRequest(parameters: [String: String]) throws -> URLRequest {
        let body = ConfigRequestBody(
            apiKey: apiKey,
            timestamp: String(Int64(now().timeIntervalSince1970 * 1000)),
            sdkVersion: SDKConstants.sdkVersion,
            sdkParams: parameters
                .sorted { $0.key < $1.key }
                .map { ConfigRequestBody.Param(paramName: $0.key, paramValue: $0.value) }
        )

        var request = URLRequest(url: endpoint,
                                 cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: SDKConstants.apiTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("\(SDKConstants.sdkName)/\(SDKConstants.sdkVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    /// Fetches and parses the configuration. Network errors and HTTP 5xx are retried
    /// (`maxRetries` times, waiting 1 s, 2 s, ...); other HTTP errors fail at once.
    func fetch(parameters: [String: String]) async throws -> Config {
        let request = try makeRequest(parameters: parameters)
        SDKLog.debug("Config request -> \(endpoint.absoluteString) (\(parameters.count) params)", .api)

        var attempt = 0
        while true {
            do {
                let (data, response) = try await transport.send(request)
                SDKLog.debug("Config response status \(response.statusCode)", .api)
                guard response.statusCode == 200 else {
                    if let body = String(data: data, encoding: .utf8), !body.isEmpty {
                        SDKLog.error("HTTP \(response.statusCode): \(body.prefix(500))", .api)
                    }
                    throw ConfigServiceError.http(statusCode: response.statusCode)
                }
                let config = ConfigParser.parseResponse(data)
                if config.surveys.isEmpty {
                    SDKLog.warning("No surveys in response", .api)
                }
                return config
            } catch {
                guard attempt < maxRetries, Self.isRetryable(error) else {
                    SDKLog.error("Config request failed: \(error)", .api)
                    throw error
                }
                attempt += 1
                SDKLog.debug("Retrying config request (\(attempt)/\(maxRetries))", .api)
                let delay = retryDelay * Double(attempt)
                if delay > 0 {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
    }

    static func isRetryable(_ error: Error) -> Bool {
        if error is CancellationError { return false }
        if let urlError = error as? URLError, urlError.code == .cancelled { return false }
        if let serviceError = error as? ConfigServiceError {
            if case .http(let code) = serviceError { return code >= 500 }
            return false
        }
        return true // transport / network error
    }
}
