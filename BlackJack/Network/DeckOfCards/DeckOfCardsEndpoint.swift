//
//  DeckOfCardsEndpoint.swift
//  BlackJack
//
//  Created by Chris Volentine on 11/2/26.
//
import Foundation

/// Every Deck of Cards API endpoint as a typed APIRequest
/// Docs: https://deckofcardsapi.com
enum DeckOfCardsEndpoint {
    static let baseURL = URL(string: "https://deckofcardsapi.com/api/")!

    /// Use as a deck ID to create a fresh shuffled deck and draw from it in one call
    static let newDeckKeyword = "new"

    enum PileDrawPosition: Sendable {
        case top
        case bottom
        case random
    }

    // MARK: Decks

    /// `GET deck/new/shuffle/?deck_count=N`
    static func newShuffledDeck(deckCount: Int, jokersEnabled: Bool = false) -> APIRequest<DeckResponseDTO> {
        var query = [URLQueryItem(name: "deck_count", value: String(deckCount))]
        if jokersEnabled { query.append(URLQueryItem(name: "jokers_enabled", value: "true")) }
        return APIRequest(path: "deck/new/shuffle/", queryItems: query)
    }

    /// `GET deck/new/` Unshuffled, in suit order
    static func newOrderedDeck(jokersEnabled: Bool = false) -> APIRequest<DeckResponseDTO> {
        let query = jokersEnabled ? [URLQueryItem(name: "jokers_enabled", value: "true")] : []
        return APIRequest(path: "deck/new/", queryItems: query)
    }

    /// `GET deck/new/shuffle/?cards=AS,2S,...` A shuffled deck containing only these cards
    static func newPartialDeck(cardCodes: [String]) -> APIRequest<DeckResponseDTO> {
        APIRequest(
            path: "deck/new/shuffle/",
            queryItems: [URLQueryItem(name: "cards", value: cardCodes.joined(separator: ","))]
        )
    }

    /// `GET deck/<id>/shuffle/` (optional: `?remaining=true` to leave drawn cards and piles alone)
    static func reshuffle(deckID: DeckID, remainingOnly: Bool = false) -> APIRequest<DeckResponseDTO> {
        let query = remainingOnly ? [URLQueryItem(name: "remaining", value: "true")] : []
        return APIRequest(path: "deck/\(deckID.rawValue)/shuffle/", queryItems: query)
    }

    /// `GET deck/<id>/draw/?count=N` Note: pass `DeckID.new` to create-and-draw
    /// Bigger draws get a longer timeout
    static func draw(deckID: DeckID, count: Int) -> APIRequest<DrawResponseDTO> {
        APIRequest(
            path: "deck/\(deckID.rawValue)/draw/",
            queryItems: [URLQueryItem(name: "count", value: String(count))],
            timeout: count > 52 ? 15 : 10
        )
    }

    /// `GET deck/<id>/return/` (optionally only the given cards)
    static func returnToDeck(deckID: DeckID, cardCodes: [String]? = nil) -> APIRequest<PileResponseDTO> {
        var query: [URLQueryItem] = []
        if let cardCodes, !cardCodes.isEmpty {
            query.append(URLQueryItem(name: "cards", value: cardCodes.joined(separator: ",")))
        }
        return APIRequest(path: "deck/\(deckID.rawValue)/return/", queryItems: query)
    }

    // MARK: Piles (single-deck only per the API docs)

    /// `GET deck/<id>/pile/<name>/add/?cards=...`
    static func addToPile(deckID: DeckID, pile: PileName, cardCodes: [String]) -> APIRequest<PileResponseDTO> {
        APIRequest(
            path: "deck/\(deckID.rawValue)/pile/\(pile.rawValue)/add/",
            queryItems: [URLQueryItem(name: "cards", value: cardCodes.joined(separator: ","))]
        )
    }

    /// `GET deck/<id>/pile/<name>/shuffle/`
    static func shufflePile(deckID: DeckID, pile: PileName) -> APIRequest<PileResponseDTO> {
        APIRequest(path: "deck/\(deckID.rawValue)/pile/\(pile.rawValue)/shuffle/")
    }

    /// `GET deck/<id>/pile/<name>/list/`
    static func listPile(deckID: DeckID, pile: PileName) -> APIRequest<PileResponseDTO> {
        APIRequest(path: "deck/\(deckID.rawValue)/pile/\(pile.rawValue)/list/")
    }

    /// `GET deck/<id>/pile/<name>/draw/[bottom/|random/]?count=N`
    static func drawFromPile(
        deckID: DeckID,
        pile: PileName,
        count: Int,
        from position: PileDrawPosition = .top
    ) -> APIRequest<PileResponseDTO> {
        let suffix: String
        switch position {
        case .top: suffix = ""
        case .bottom: suffix = "bottom/"
        case .random: suffix = "random/"
        }
        return APIRequest(
            path: "deck/\(deckID.rawValue)/pile/\(pile.rawValue)/draw/\(suffix)",
            queryItems: [URLQueryItem(name: "count", value: String(count))]
        )
    }

    /// `GET deck/<id>/pile/<name>/draw/?cards=AS,...` Draws specific cards
    static func drawSpecificFromPile(deckID: DeckID, pile: PileName, cardCodes: [String]) -> APIRequest<PileResponseDTO> {
        APIRequest(
            path: "deck/\(deckID.rawValue)/pile/\(pile.rawValue)/draw/",
            queryItems: [URLQueryItem(name: "cards", value: cardCodes.joined(separator: ","))]
        )
    }

    /// `GET deck/<id>/pile/<name>/return/` (optionally only the given cards).
    static func returnPile(deckID: DeckID, pile: PileName, cardCodes: [String]? = nil) -> APIRequest<PileResponseDTO> {
        var query: [URLQueryItem] = []
        if let cardCodes, !cardCodes.isEmpty {
            query.append(URLQueryItem(name: "cards", value: cardCodes.joined(separator: ",")))
        }
        return APIRequest(path: "deck/\(deckID.rawValue)/pile/\(pile.rawValue)/return/", queryItems: query)
    }
}

// MARK: - Validated identifiers

struct DeckID: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
    let rawValue: String

    init?(rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 64,
              trimmed.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) && $0.isASCII }) else {
            return nil
        }
        self.rawValue = trimmed
    }

    /// Create a new shuffled deck as part of a draw request
    static let new = DeckID(rawValue: DeckOfCardsEndpoint.newDeckKeyword)!

    var description: String { rawValue }
}

/// Letters, digits, `-` and `_` only
struct PileName: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
    let rawValue: String

    init?(rawValue: String) {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_")
        guard !rawValue.isEmpty, rawValue.count <= 64,
              rawValue.unicodeScalars.allSatisfy({ allowed.contains($0) && $0.isASCII }) else {
            return nil
        }
        self.rawValue = rawValue
    }

    var description: String { rawValue }
}
