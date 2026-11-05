//
//  DeckOfCardsService.swift
//  BlackJack
//
//  Created by Chris Volentine on 11/2/26.
//
import Foundation
import OSLog

// MARK: - Domain results

struct RemoteDeck: Sendable, Equatable {
    let id: DeckID
    let remaining: Int
    let isShuffled: Bool
}

struct RemoteDraw: Sendable, Equatable {
    let deckID: DeckID
    let cards: [Card]
    let remaining: Int
    let imageURLs: [UUID: URL]
}

struct RemotePile: Sendable, Equatable {
    let name: PileName
    let remaining: Int
    let cards: [Card]? /// Present only for list / draw responses
}

// MARK: - Abstraction used by the game

protocol DeckProviding: Sendable {
    /// Returns every card of a newly shuffled `deckCount`-deck shoe in deal order
    func shuffledShoe(deckCount: Int) async throws -> [Card]
}

// MARK: - Service

/// High-level client for https://deckofcardsapi.com
actor DeckOfCardsService: DeckProviding {
    static let supportedDeckCounts = 1...20
    /// Largest single draw request (3 decks); bigger shoes are drawn in several requests
    static let maxCardsPerDraw = 156

    private let client: HTTPClient
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? AppConfig.bundleIdBackup, category: "deck-api")

    /// most recent multi-deck shoe, reused by reshuffling instead of creating new decks.
    private var cachedShoe: (id: DeckID, deckCount: Int)?

    init(client: HTTPClient) {
        self.client = client
    }

    init(monitor: NetworkMonitor? = nil) {
        self.client = URLSessionHTTPClient(baseURL: DeckOfCardsEndpoint.baseURL, monitor: monitor)
    }

    // MARK: Game-level operation

    func shuffledShoe(deckCount: Int) async throws -> [Card] {
        guard Self.supportedDeckCounts.contains(deckCount) else {
            throw NetworkError.invalidRequest("Deck count \(deckCount) is outside \(Self.supportedDeckCounts)")
        }
        let expected = deckCount * 52
        let deck = try await shuffledShoeDeck(deckCount: deckCount, expectedCards: expected)

        // API doesn't document a maximum draw size, so large shoes are drawn in chunks
        var cards: [Card] = []
        cards.reserveCapacity(expected)
        while cards.count < expected {
            try Task.checkCancellation()
            let batch = min(Self.maxCardsPerDraw, expected - cards.count)
            let result = try await draw(count: batch, from: deck.id)
            cards.append(contentsOf: result.cards)
        }

        guard cards.count == expected else {
            throw NetworkError.notEnoughCards(requested: expected, remaining: cards.count)
        }
        logger.info("Drew a \(deckCount)-deck shoe (\(expected) cards) from deck \(deck.id.rawValue, privacy: .public)")
        return cards
    }

    private func shuffledShoeDeck(deckCount: Int, expectedCards: Int) async throws -> RemoteDeck {
        if let cached = cachedShoe, cached.deckCount == deckCount {
            do {
                let deck = try await reshuffle(deckID: cached.id)
                if deck.remaining == expectedCards { return deck }
                logger.notice("Reshuffled deck had \(deck.remaining) cards, expected \(expectedCards); creating a new one")
            } catch NetworkError.deckNotFound {
                logger.notice("Cached deck expired; creating a new one")
            }
            cachedShoe = nil
        }

        let deck = try await newShuffledDeck(deckCount: deckCount)
        guard deck.remaining == expectedCards else {
            throw NetworkError.notEnoughCards(requested: expectedCards, remaining: deck.remaining)
        }
        cachedShoe = (deck.id, deckCount)
        return deck
    }

    func resetCachedDeck() {
        cachedShoe = nil
    }

    // MARK: Decks

    func newShuffledDeck(deckCount: Int = 1, jokersEnabled: Bool = false) async throws -> RemoteDeck {
        guard Self.supportedDeckCounts.contains(deckCount) else {
            throw NetworkError.invalidRequest("Deck count \(deckCount) is outside \(Self.supportedDeckCounts)")
        }
        let dto = try await send(DeckOfCardsEndpoint.newShuffledDeck(deckCount: deckCount, jokersEnabled: jokersEnabled))
        return try remoteDeck(from: dto)
    }

    func newOrderedDeck(jokersEnabled: Bool = false) async throws -> RemoteDeck {
        let dto = try await send(DeckOfCardsEndpoint.newOrderedDeck(jokersEnabled: jokersEnabled))
        return try remoteDeck(from: dto)
    }

    func newPartialDeck(containing cards: [Card]) async throws -> RemoteDeck {
        guard !cards.isEmpty else { throw NetworkError.invalidRequest("A partial deck needs at least one card") }
        let dto = try await send(DeckOfCardsEndpoint.newPartialDeck(cardCodes: cards.map(\.apiCode)))
        return try remoteDeck(from: dto)
    }

    func reshuffle(deckID: DeckID, remainingOnly: Bool = false) async throws -> RemoteDeck {
        let dto = try await send(DeckOfCardsEndpoint.reshuffle(deckID: deckID, remainingOnly: remainingOnly))
        return try remoteDeck(from: dto)
    }

    // MARK: Drawing

    func draw(count: Int, from deckID: DeckID) async throws -> RemoteDraw {
        guard count > 0 else { throw NetworkError.invalidRequest("Draw count must be positive") }
        let dto = try await send(DeckOfCardsEndpoint.draw(deckID: deckID, count: count), requested: count)

        var cards: [Card] = []
        var images: [UUID: URL] = [:]
        cards.reserveCapacity(dto.cards.count)
        for cardDTO in dto.cards {
            let card = try cardDTO.toCard()
            cards.append(card)
            if let url = cardDTO.images?.png ?? cardDTO.image {
                images[card.id] = url
            }
        }
        guard cards.count == count else {
            throw NetworkError.notEnoughCards(requested: count, remaining: cards.count)
        }

        let resolvedID = dto.deckID.flatMap(DeckID.init(rawValue:)) ?? deckID
        return RemoteDraw(deckID: resolvedID, cards: cards, remaining: dto.remaining ?? 0, imageURLs: images)
    }

    func returnToDeck(_ cards: [Card]? = nil, deckID: DeckID) async throws -> RemoteDeck {
        let dto = try await send(DeckOfCardsEndpoint.returnToDeck(deckID: deckID, cardCodes: cards?.map(\.apiCode)))
        guard let remaining = dto.remaining else { throw NetworkError.invalidResponse }
        return RemoteDeck(id: deckID, remaining: remaining, isShuffled: dto.shuffled ?? false)
    }

    // MARK: Piles

    func addToPile(_ cards: [Card], pile: PileName, deckID: DeckID) async throws -> RemotePile {
        guard !cards.isEmpty else { throw NetworkError.invalidRequest("No cards to add") }
        let dto = try await send(DeckOfCardsEndpoint.addToPile(deckID: deckID, pile: pile, cardCodes: cards.map(\.apiCode)))
        return try remotePile(named: pile, from: dto)
    }

    func shufflePile(_ pile: PileName, deckID: DeckID) async throws -> RemotePile {
        let dto = try await send(DeckOfCardsEndpoint.shufflePile(deckID: deckID, pile: pile))
        return try remotePile(named: pile, from: dto)
    }

    func listPile(_ pile: PileName, deckID: DeckID) async throws -> RemotePile {
        let dto = try await send(DeckOfCardsEndpoint.listPile(deckID: deckID, pile: pile))
        return try remotePile(named: pile, from: dto)
    }

    func drawFromPile(
        _ pile: PileName,
        count: Int,
        from position: DeckOfCardsEndpoint.PileDrawPosition = .top,
        deckID: DeckID
    ) async throws -> [Card] {
        guard count > 0 else { throw NetworkError.invalidRequest("Draw count must be positive") }
        let dto = try await send(
            DeckOfCardsEndpoint.drawFromPile(deckID: deckID, pile: pile, count: count, from: position),
            requested: count
        )
        return try dto.cards.map { try $0.toCard() }
    }

    func returnPile(_ pile: PileName, cards: [Card]? = nil, deckID: DeckID) async throws -> RemoteDeck {
        let dto = try await send(DeckOfCardsEndpoint.returnPile(deckID: deckID, pile: pile, cardCodes: cards?.map(\.apiCode)))
        guard let remaining = dto.remaining else { throw NetworkError.invalidResponse }
        return RemoteDeck(id: deckID, remaining: remaining, isShuffled: dto.shuffled ?? false)
    }

    // MARK: - Request pipeline

    private func send<T: Decodable & Sendable & DeckAPIEnvelope>(
        _ request: APIRequest<T>,
        requested: Int? = nil
    ) async throws -> T {
        let response: T
        do {
            response = try await client.send(request)
        } catch NetworkError.httpStatus(let code, let message) {
            throw Self.interpret(statusCode: code, message: message, requested: requested, remaining: nil)
        }

        guard response.success else {
            throw Self.interpret(statusCode: nil, message: response.error, requested: requested, remaining: response.remaining)
        }
        return response
    }

    static func interpret(statusCode: Int?, message: String?, requested: Int?, remaining: Int?) -> NetworkError {
        let text = message ?? ""
        let lowered = text.lowercased()
        if lowered.contains("does not exist") || lowered.contains("not found") || statusCode == 404 {
            return .deckNotFound
        }
        if lowered.contains("not enough cards") {
            return .notEnoughCards(requested: requested ?? 0, remaining: remaining ?? 0)
        }
        if let statusCode {
            return .httpStatus(code: statusCode, message: message)
        }
        return .apiFailure(text.isEmpty ? "The request was not successful." : text)
    }

    private func remoteDeck(from dto: DeckResponseDTO) throws -> RemoteDeck {
        guard let rawID = dto.deckID, let id = DeckID(rawValue: rawID) else {
            throw NetworkError.decodingFailed("Missing or invalid deck_id")
        }
        guard let remaining = dto.remaining, remaining >= 0 else {
            throw NetworkError.decodingFailed("Missing remaining count")
        }
        return RemoteDeck(id: id, remaining: remaining, isShuffled: dto.shuffled ?? false)
    }

    private func remotePile(named pile: PileName, from dto: PileResponseDTO) throws -> RemotePile {
        guard let summary = dto.piles[pile.rawValue] else {
            // A pile that was emptied may be omitted; report it as empty.
            return RemotePile(name: pile, remaining: 0, cards: nil)
        }
        let cards = try summary.cards?.map { try $0.toCard() }
        return RemotePile(name: pile, remaining: summary.remaining, cards: cards)
    }
}

// MARK: - Preview / test stub

/// Offline `DeckProviding` that returns locally shuffled shoes, optionally failing on demand
struct StubDeckProvider: DeckProviding {
    var failure: NetworkError?

    func shuffledShoe(deckCount: Int) async throws -> [Card] {
        if let failure { throw failure }
        return Shoe.freshCards(deckCount: deckCount).shuffled()
    }
}
