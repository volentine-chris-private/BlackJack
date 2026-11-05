//
//  HTTPClient.swift
//  BlackJack
//
//  Created by Chris Volentine on 11/2/26.
//
import Foundation
import OSLog

/// Abstraction over HTTP so services can be tested or previewed with a fake client
protocol HTTPClient: Sendable {
    func send<Response: Decodable & Sendable>(_ request: APIRequest<Response>) async throws -> Response
}

/// Production client built on URLSession and async/await
///
/// - Fails fast with .offline when NetworkMonitor reports no connectivity
/// - Retries transient failures (timeouts, dropped connections, 5xx, 429)
///   with exponential backoff and jitter, honoring Retry-After
/// - Maps transport, HTTP, and decoding failures into NetworkError
/// - Propagates cancellation as CancellationError
struct URLSessionHTTPClient: HTTPClient {
    let baseURL: URL
    private let session: URLSession
    private let monitor: NetworkMonitor?
    private let defaultRetryPolicy: RetryPolicy
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? AppConfig.bundleIdBackup, category: "network")

    init(
        baseURL: URL,
        session: URLSession = URLSessionHTTPClient.makeDefaultSession(),
        monitor: NetworkMonitor? = nil,
        retryPolicy: RetryPolicy = .standard
    ) {
        self.baseURL = baseURL
        self.session = session
        self.monitor = monitor
        self.defaultRetryPolicy = retryPolicy
    }

    static func makeDefaultSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpAdditionalHeaders = ["User-Agent": "Blackjack-iOS/1.0"]
        return URLSession(configuration: configuration)
    }

    func send<Response: Decodable & Sendable>(_ request: APIRequest<Response>) async throws -> Response {
        let urlRequest = try request.urlRequest(baseURL: baseURL)
        let policy = request.retryPolicy ?? defaultRetryPolicy
        let requestID = String(UUID().uuidString.prefix(8))
        let label = "\(request.method.rawValue) \(urlRequest.url?.path ?? request.path)"

        var attempt = 0
        while true {
            attempt += 1
            try Task.checkCancellation()
            let started = Date()
            do {
                let response: Response = try await perform(urlRequest)
                let elapsed = Int(Date().timeIntervalSince(started) * 1000)
                logger.debug("[\(requestID, privacy: .public)] \(label, privacy: .public) - SUCCESS - \(elapsed)ms (attempt \(attempt))")
                return response
            } catch let error as NetworkError {
                logger.notice("[\(requestID, privacy: .public)] \(label, privacy: .public) - FAILURE - \(error.message, privacy: .public) (attempt \(attempt)/\(policy.maxAttempts))")
                guard error.isRetryable, attempt < policy.maxAttempts else { throw error }
                let delay = policy.delay(afterAttempt: attempt, retryAfter: error.retryAfter)
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }

    // MARK: - Single attempt

    private func perform<Response: Decodable>(_ urlRequest: URLRequest) async throws -> Response {
        if monitor?.status == .unsatisfied {
            throw NetworkError.offline
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch let urlError as URLError {
            if urlError.code == .cancelled { throw CancellationError() }
            throw NetworkError(urlError)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw NetworkError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }

        switch http.statusCode {
        case 200..<300:
            break
        case 429:
            throw NetworkError.rateLimited(retryAfter: Self.retryAfter(from: http))
        case 500..<600:
            throw NetworkError.serverUnavailable(code: http.statusCode)
        default:
            throw NetworkError.httpStatus(code: http.statusCode, message: Self.errorMessage(in: data))
        }

        guard !data.isEmpty else { throw NetworkError.invalidResponse }

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch let decodingError as DecodingError {
            throw NetworkError.decodingFailed(Self.describe(decodingError))
        } catch {
            throw NetworkError.decodingFailed(error.localizedDescription)
        }
    }

    // MARK: - Helpers

    private struct ErrorBody: Decodable {
        let error: String?
        let message: String?
    }

    static func errorMessage(in data: Data) -> String? {
        guard !data.isEmpty, let body = try? JSONDecoder().decode(ErrorBody.self, from: data) else { return nil }
        return body.error ?? body.message
    }

    static func retryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After") else { return nil }
        if let seconds = TimeInterval(value.trimmingCharacters(in: .whitespaces)) {
            return seconds
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        if let date = formatter.date(from: value) {
            return max(date.timeIntervalSinceNow, 0)
        }
        return nil
    }

    static func describe(_ error: DecodingError) -> String {
        func path(_ codingPath: [CodingKey]) -> String {
            codingPath.map(\.stringValue).joined(separator: ".")
        }
        switch error {
        case .keyNotFound(let key, let context):
            return "missing key '\(key.stringValue)' at \(path(context.codingPath))"
        case .typeMismatch(let type, let context):
            return "type mismatch for \(type) at \(path(context.codingPath))"
        case .valueNotFound(let type, let context):
            return "missing \(type) at \(path(context.codingPath))"
        case .dataCorrupted(let context):
            return "corrupted data at \(path(context.codingPath)): \(context.debugDescription)"
        @unknown default:
            return error.localizedDescription
        }
    }
}

/// Runs an async operation w/ an overall deadline that covers every retry
enum NetworkDeadline {
    static func run<T: Sendable>(
        seconds: TimeInterval,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(max(seconds, 0) * 1_000_000_000))
                throw NetworkError.timedOut
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw NetworkError.timedOut }
            return result
        }
    }
}
