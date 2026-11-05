//
//  DeckOfCardsDTOs.swift
//  BlackJack
//
//  Created by Chris Volentine on 11/2/26.
//
import Foundation

// Models for https://deckofcardsapi.com. They mirror the json and are mapped to
// domain types (Card, RemoteDeck, etc) by `DeckOfCardsService`, so the rest
// of the app never depends on the API's field names

protocol DeckAPIEnvelope {
    var success: Bool { get }
    var error: String? { get }
    var remaining: Int? { get }
}

private enum EnvelopeKeys: String, CodingKey {
    case success, error, remaining
    case deckID = "deck_id"
    case shuffled, cards, piles
}

nonisolated struct DeckResponseDTO: Decodable, Sendable, DeckAPIEnvelope {
    let success: Bool
    let error: String?
    let deckID: String?
    let shuffled: Bool?
    let remaining: Int?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: EnvelopeKeys.self)
        success = try c.decodeIfPresent(Bool.self, forKey: .success) ?? false
        error = try c.decodeIfPresent(String.self, forKey: .error)
        deckID = try c.decodeIfPresent(String.self, forKey: .deckID)
        shuffled = try c.decodeIfPresent(Bool.self, forKey: .shuffled)
        remaining = try c.decodeFlexibleIntIfPresent(forKey: .remaining)
    }
}

nonisolated struct DrawResponseDTO: Decodable, Sendable, DeckAPIEnvelope {
    let success: Bool
    let error: String?
    let deckID: String?
    let cards: [CardDTO]
    let remaining: Int?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: EnvelopeKeys.self)
        success = try c.decodeIfPresent(Bool.self, forKey: .success) ?? false
        error = try c.decodeIfPresent(String.self, forKey: .error)
        deckID = try c.decodeIfPresent(String.self, forKey: .deckID)
        cards = try c.decodeIfPresent([CardDTO].self, forKey: .cards) ?? []
        remaining = try c.decodeFlexibleIntIfPresent(forKey: .remaining)
    }
}

struct PileSummaryDTO: Decodable, Sendable {
    let remaining: Int
    let cards: [CardDTO]?

    private enum Keys: String, CodingKey { case remaining, cards }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        remaining = try c.decodeFlexibleIntIfPresent(forKey: .remaining) ?? 0
        cards = try c.decodeIfPresent([CardDTO].self, forKey: .cards)
    }
}

/// Used by pile add / shuffle / list / draw and by the return endpoints
nonisolated struct PileResponseDTO: Decodable, Sendable, DeckAPIEnvelope {
    let success: Bool
    let error: String?
    let deckID: String?
    let remaining: Int?
    let shuffled: Bool?
    let piles: [String: PileSummaryDTO]
    let cards: [CardDTO]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: EnvelopeKeys.self)
        success = try c.decodeIfPresent(Bool.self, forKey: .success) ?? false
        error = try c.decodeIfPresent(String.self, forKey: .error)
        deckID = try c.decodeIfPresent(String.self, forKey: .deckID)
        remaining = try c.decodeFlexibleIntIfPresent(forKey: .remaining)
        shuffled = try c.decodeIfPresent(Bool.self, forKey: .shuffled)
        piles = try c.decodeIfPresent([String: PileSummaryDTO].self, forKey: .piles) ?? [:]
        cards = try c.decodeIfPresent([CardDTO].self, forKey: .cards) ?? []
    }
}

struct CardDTO: Decodable, Sendable, Equatable {
    struct Images: Decodable, Sendable, Equatable {
        let svg: URL?
        let png: URL?
    }

    let code: String
    let value: String?
    let suit: String?
    let image: URL?
    let images: Images?
}

// MARK: - Mapping to domain cards

extension CardDTO {
    /// Converts the API card into the game's Card
    func toCard() throws -> Card {
        if let card = Self.card(fromCode: code) { return card }
        if let value, let suit,
           let rank = Self.rank(fromValue: value),
           let parsedSuit = Self.suit(fromName: suit) {
            return Card(rank: rank, suit: parsedSuit)
        }
        throw NetworkError.invalidCardData("Unrecognized card \"\(code)\"")
    }

    static func card(fromCode code: String) -> Card? {
        let upper = code.uppercased()
        guard upper.count == 2, let rankChar = upper.first, let suitChar = upper.last else { return nil }
        guard let parsedRank = Self.rank(fromCodeCharacter: rankChar),
              let parsedSuit = Self.suit(fromCodeCharacter: suitChar) else { return nil }
        return Card(rank: parsedRank, suit: parsedSuit)
    }

    static func rank(fromCodeCharacter character: Character) -> Rank? {
        switch character {
        case "A": return .ace
        case "K": return .king
        case "Q": return .queen
        case "J": return .jack
        case "0": return .ten
        default:
            guard let digit = character.wholeNumberValue, (2...9).contains(digit) else { return nil }
            return Rank(rawValue: digit)
        }
    }

    static func suit(fromCodeCharacter character: Character) -> Suit? {
        switch character {
        case "S": return .spades
        case "H": return .hearts
        case "D": return .diamonds
        case "C": return .clubs
        default: return nil
        }
    }

    static func rank(fromValue value: String) -> Rank? {
        switch value.uppercased() {
        case "ACE": return .ace
        case "KING": return .king
        case "QUEEN": return .queen
        case "JACK": return .jack
        default:
            guard let number = Int(value), (2...10).contains(number) else { return nil }
            return Rank(rawValue: number)
        }
    }

    static func suit(fromName name: String) -> Suit? {
        switch name.uppercased() {
        case "SPADES": return .spades
        case "HEARTS": return .hearts
        case "DIAMONDS": return .diamonds
        case "CLUBS": return .clubs
        default: return nil
        }
    }
}

extension Card {
    var apiCode: String {
        let rankCode: String
        switch rank {
        case .ten: rankCode = "0"
        case .jack: rankCode = "J"
        case .queen: rankCode = "Q"
        case .king: rankCode = "K"
        case .ace: rankCode = "A"
        default: rankCode = String(rank.rawValue)
        }
        let suitCode: String
        switch suit {
        case .spades: suitCode = "S"
        case .hearts: suitCode = "H"
        case .diamonds: suitCode = "D"
        case .clubs: suitCode = "C"
        }
        return rankCode + suitCode
    }
}

// MARK: - API Sanity

extension KeyedDecodingContainer {
    /// The API sometimes sends `remaining` as a number and sometimes as a string ("42")
    nonisolated func decodeFlexibleIntIfPresent(forKey key: Key) throws -> Int? {
        if let intValue = try? decodeIfPresent(Int.self, forKey: key) {
            return intValue
        }
        if let stringValue = try? decodeIfPresent(String.self, forKey: key) {
            guard let parsed = Int(stringValue.trimmingCharacters(in: .whitespaces)) else {
                throw DecodingError.dataCorruptedError(
                    forKey: key,
                    in: self,
                    debugDescription: "Expected an integer, found \"\(stringValue)\""
                )
            }
            return parsed
        }
        return nil
    }
}
