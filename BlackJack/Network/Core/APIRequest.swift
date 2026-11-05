//
//  APIRequest.swift
//  BlackJack
//
//  Created by Chris Volentine on 11/2/26.
//
import Foundation

enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
}

struct APIRequest<Response: Decodable & Sendable>: Sendable {
    var method: HTTPMethod = .get
    var path: String /// relative to client's base URL
    var queryItems: [URLQueryItem] = []
    var headers: [String: String] = [:]
    var timeout: TimeInterval = 10 /// per attempt
    var retryPolicy: RetryPolicy? /// will override client's default

    init(
        method: HTTPMethod = .get,
        path: String,
        queryItems: [URLQueryItem] = [],
        headers: [String: String] = [:],
        timeout: TimeInterval = 10,
        retryPolicy: RetryPolicy? = nil
    ) {
        self.method = method
        self.path = path
        self.queryItems = queryItems
        self.headers = headers
        self.timeout = timeout
        self.retryPolicy = retryPolicy
    }

    func urlRequest(baseURL: URL) throws -> URLRequest {
        guard !path.hasPrefix("/"), !path.contains("..") else {
            throw NetworkError.invalidRequest("Invalid path \"\(path)\"")
        }
        guard let resolved = URL(string: path, relativeTo: baseURL),
              var components = URLComponents(url: resolved, resolvingAgainstBaseURL: true) else {
            throw NetworkError.invalidRequest("Couldn't resolve \"\(path)\"")
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url, url.scheme == "https" else {
            throw NetworkError.invalidRequest("Only HTTPS URLs are allowed")
        }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        return request
    }
}

struct RetryPolicy: Sendable, Equatable {
    var maxAttempts: Int
    var baseDelay: TimeInterval
    var maxDelay: TimeInterval
    var jitter: Double

    static let standard = RetryPolicy(maxAttempts: 3, baseDelay: 0.5, maxDelay: 4, jitter: 0.2)
    static let none = RetryPolicy(maxAttempts: 1, baseDelay: 0, maxDelay: 0, jitter: 0)

    func delay(afterAttempt attempt: Int, retryAfter: TimeInterval?) -> TimeInterval {
        if let retryAfter, retryAfter > 0 {
            return min(retryAfter, maxDelay)
        }
        let exponential = baseDelay * pow(2, Double(max(attempt - 1, 0)))
        let capped = min(exponential, maxDelay)
        guard jitter > 0 else { return capped }
        return max(0, capped * Double.random(in: (1 - jitter)...(1 + jitter)))
    }
}
