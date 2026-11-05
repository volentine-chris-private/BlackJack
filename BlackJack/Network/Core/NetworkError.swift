//
//  NetworkError.swift
//  BlackJack
//
//  Created by Chris Volentine on 11/2/26.
//
import Foundation

enum NetworkError: Error, Equatable, Sendable {
    // Connectivity
    case offline
    case timedOut
    case cannotReachServer
    case connectionLost
    case insecureConnection

    // Request / response
    case invalidRequest(String)
    case invalidResponse
    case httpStatus(code: Int, message: String?)
    case rateLimited(retryAfter: TimeInterval?)
    case serverUnavailable(code: Int)
    case decodingFailed(String)

    // Deck of Cards API semantics
    case apiFailure(String)
    case deckNotFound
    case notEnoughCards(requested: Int, remaining: Int)
    case invalidCardData(String)

    // Other
    case transport(String)

    // MARK: Retry

    /// Whether repeating the same request could reasonably succeed
    var isRetryable: Bool {
        switch self {
        case .timedOut, .cannotReachServer, .connectionLost, .rateLimited, .serverUnavailable:
            return true
        case .offline, .insecureConnection, .invalidRequest, .invalidResponse, .httpStatus,
             .decodingFailed, .apiFailure, .deckNotFound, .notEnoughCards, .invalidCardData, .transport:
            return false
        }
    }

    /// Server-suggested wait before retrying (from Retry-After)
    var retryAfter: TimeInterval? {
        if case .rateLimited(let seconds) = self { return seconds }
        return nil
    }

    // MARK: Mapping

    init(_ urlError: URLError) {
        switch urlError.code {
        case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff, .callIsActive:
            self = .offline
        case .timedOut:
            self = .timedOut
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .resourceUnavailable:
            self = .cannotReachServer
        case .networkConnectionLost:
            self = .connectionLost
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot, .clientCertificateRejected,
             .clientCertificateRequired, .appTransportSecurityRequiresSecureConnection:
            self = .insecureConnection
        case .badURL, .unsupportedURL:
            self = .invalidRequest(urlError.localizedDescription)
        case .badServerResponse, .zeroByteResource, .cannotDecodeContentData, .cannotDecodeRawData,
             .cannotParseResponse:
            self = .invalidResponse
        default:
            self = .transport("\(urlError.code.rawValue): \(urlError.localizedDescription)")
        }
    }

    // MARK: Presentation

    var code: String {
        switch self {
        case .offline: return "001"
        case .timedOut: return "002"
        case .cannotReachServer: return "003"
        case .connectionLost: return "004"
        case .insecureConnection: return "005"
        case .invalidRequest: return "006"
        case .invalidResponse: return "007"
        case .httpStatus: return "008"
        case .rateLimited: return "009"
        case .serverUnavailable: return "010"
        case .decodingFailed: return "011"
        case .apiFailure: return "012"
        case .deckNotFound: return "013"
        case .notEnoughCards: return "014"
        case .invalidCardData: return "015"
        case .transport: return "016"
        }
    }

    var severity: ErrorSeverity {
        switch self {
        case .invalidRequest, .insecureConnection:
            return .error
        default:
            return .warning
        }
    }

    var message: String {
        switch self {
        case .offline:
            return "You're offline."
        case .timedOut:
            return "The card service took too long to respond."
        case .cannotReachServer:
            return "The card service couldn't be reached."
        case .connectionLost:
            return "The connection dropped during the request."
        case .insecureConnection:
            return "A secure connection to the card service couldn't be established."
        case .invalidRequest(let detail):
            return "The request couldn't be built. (\(detail))"
        case .invalidResponse:
            return "The card service sent an unexpected response."
        case .httpStatus(let code, let message):
            return "The card service returned an error (\(code))\(message.map { ": \($0)" } ?? ".")"
        case .rateLimited:
            return "Too many requests to the card service."
        case .serverUnavailable(let code):
            return "The card service is temporarily unavailable (\(code))."
        case .decodingFailed(let detail):
            return "The card service's response couldn't be read. (\(detail))"
        case .apiFailure(let message):
            return "The card service reported a problem: \(message)"
        case .deckNotFound:
            return "The deck no longer exists on the card service."
        case .notEnoughCards(let requested, let remaining):
            return "Asked for \(requested) cards but only \(remaining) remain."
        case .invalidCardData(let detail):
            return "The card service returned invalid cards. (\(detail))"
        case .transport(let detail):
            return "A network error occurred. (\(detail))"
        }
    }

    var suggestion: String? {
        switch self {
        case .offline: return "Check your Wi-Fi or cellular connection."
        case .rateLimited, .serverUnavailable, .timedOut: return "Try again in a moment."
        default: return nil
        }
    }
}

extension NetworkError: LocalizedError {
    var errorDescription: String? { message }
    var recoverySuggestion: String? { suggestion }
}
