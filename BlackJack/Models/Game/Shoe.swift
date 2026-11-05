//
//  Shoe.swift
//  BlackJack
//
//  Created by Chris Volentine on 11/2/26.
//

import Foundation

enum ShuffleReason: Equatable {
    case newShoe
    case cutCard
    case timer
    case hotDeck
    case continuous
    case lowCards

    var bannerText: String? {
        switch self {
        case .newShoe: return "Shuffling a fresh shoe... "
        case .cutCard: return "Cut card reached - shuffling"
        case .timer: return "Shuffle time - new shoe"
        case .hotDeck: return "Deck's running hot - dealer shuffles"
        case .continuous: return nil // happens every hand; no banner
        case .lowCards: return "Shoe is running low - shuffling"
        }
    }
}

/// multi-deck shoe with a discard tray and a cut card.
/// cards are drawn from the end of the cards array
struct Shoe {
    static let cardsPerDeck = 52

    let deckCount: Int
    private(set) var cards: [Card]
    private(set) var discards: [Card] = []
    private(set) var cutCardPosition: Int
    private(set) var shuffledAt: Date
    private(set) var shuffleDeadline: Date?

    var totalCardCount: Int { deckCount * Shoe.cardsPerDeck }
    var cardsRemaining: Int { cards.count }
    var cardsDealt: Int { totalCardCount - cards.count }
    var penetration: Double {
        totalCardCount > 0 ? Double(cardsDealt) / Double(totalCardCount) : 0
    }

    init(deckCount: Int) {
        let clamped = deckCount.clamped(to: AppConfig.absoluteDeckRange)
        self.deckCount = clamped
        self.cards = Shoe.freshCards(deckCount: clamped).shuffled()
        self.cutCardPosition = Int(Double(clamped * Shoe.cardsPerDeck) * 0.75)
        self.shuffledAt = Date()
        self.shuffleDeadline = nil
    }

    static func freshCards(deckCount: Int) -> [Card] {
        var result: [Card] = []
        result.reserveCapacity(deckCount * cardsPerDeck)
        for _ in 0..<deckCount {
            for suit in Suit.allCases {
                for rank in Rank.allCases {
                    result.append(Card(rank: rank, suit: suit))
                }
            }
        }
        return result
    }

    @discardableResult
    mutating func shuffle(rules: TableRules, cardsOnTable: Int = 0, now: Date = Date()) -> Bool {
        var pool = cards + discards
        var repaired = false
        if pool.count + cardsOnTable != totalCardCount {
            pool = Shoe.freshCards(deckCount: deckCount)
            repaired = true
        }
        cards = pool.shuffled()
        discards = []
        if let burned = cards.popLast() {
            discards.append(burned)
        }
        configureShufflePoint(rules: rules, now: now)
        shuffledAt = now
        return repaired
    }

    /// Throws if the cards aren't exactly deckCount complete decks, so
    /// a bad server response can never produce a rigged or short shoe.
    mutating func loadShuffledOrder(_ order: [Card], rules: TableRules, now: Date = Date()) throws {
        guard order.count == totalCardCount else {
            throw NetworkError.invalidCardData("Expected \(totalCardCount) cards, received \(order.count)")
        }
        var counts: [String: Int] = [:]
        for card in order {
            counts["\(card.rank.rawValue)\(card.suit.rawValue)", default: 0] += 1
        }
        let isCompleteShoe = counts.count == Shoe.cardsPerDeck && counts.values.allSatisfy { $0 == deckCount }
        guard isCompleteShoe else {
            throw NetworkError.invalidCardData("The shoe isn't made of \(deckCount) complete deck(s)")
        }

        // Cards are drawn from the end of the array
        cards = Array(order.reversed())
        discards = []
        if let burned = cards.popLast() {
            discards.append(burned)
        }
        configureShufflePoint(rules: rules, now: now)
        shuffledAt = now
    }

    private mutating func configureShufflePoint(rules: TableRules, now: Date) {
        let low = Double(rules.penetrationRange.lowerBound)
        let high = Double(rules.penetrationRange.upperBound)
        let percent = (low < high ? Double.random(in: low...high) : low) / 100
        cutCardPosition = max(1, Int(Double(totalCardCount) * percent))

        if rules.shuffleMethod == .timedInterval {
            let minutes = Int.random(in: rules.shuffleMinutesRange)
            shuffleDeadline = now.addingTimeInterval(TimeInterval(minutes * 60))
        } else {
            shuffleDeadline = nil
        }
    }

    /// Draws a card. If the shoe is empty mid-hand, the discard tray is reshuffled
    /// back in and reshuffledPileSize reports how many cards it contained.
    mutating func draw() throws -> (card: Card, reshuffledPileSize: Int?) {
        if let card = cards.popLast() {
            return (card, nil)
        }
        guard !discards.isEmpty else { throw AppError.game(.shoeExhausted) }
        cards = discards.shuffled()
        discards = []
        let pileSize = cards.count
        guard let card = cards.popLast() else { throw AppError.game(.shoeExhausted) }
        return (card, pileSize)
    }

    mutating func discard(_ used: [Card]) {
        discards.append(contentsOf: used)
    }

    func shuffleReason(
        rules: TableRules,
        trueCount: Double,
        cardsSeenSinceShuffle: Int,
        minimumCardsNeeded: Int,
        now: Date = Date()
    ) -> ShuffleReason? {
        if rules.shuffleMethod == .continuous { return .continuous }
        if cards.count < minimumCardsNeeded { return .lowCards }

        switch rules.shuffleMethod {
        case .penetrationRange:
            return cardsDealt >= cutCardPosition ? .cutCard : nil
        case .timedInterval:
            if let deadline = shuffleDeadline, now >= deadline { return .timer }
            return nil
        case .hotDeck:
            if cardsSeenSinceShuffle >= AppConfig.hotDeckMinimumCardsSeen,
               trueCount >= AppConfig.hotDeckTrueCount {
                return .hotDeck
            }
            return cardsDealt >= cutCardPosition ? .cutCard : nil
        case .continuous:
            return .continuous
        }
    }
}
