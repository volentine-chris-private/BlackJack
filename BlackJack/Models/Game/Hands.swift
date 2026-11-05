//
//  Hands.swift
//  BlackJack
//
//  Created by Chris Volentine on 11/2/26.
//

import Foundation

enum HandState: Equatable {
    case playing
    case stood
    case busted
    case blackjack
    case surrendered
}

enum HandOutcome: Equatable {
    case blackjackWin
    case win
    case push
    case loss
    case surrendered
}

struct PlayerHand: Identifiable, Equatable {
    let id: UUID
    var cards: [Card]
    var bet: Double
    var state: HandState = .playing
    var outcome: HandOutcome?
    var payout: Double = 0
    var doubleCount: Int = 0
    var isFromSplit: Bool
    var isSplitAces: Bool
    var actionsTaken: Int = 0

    init(bet: Double, cards: [Card] = [], isFromSplit: Bool = false, isSplitAces: Bool = false, id: UUID = UUID()) {
        self.id = id
        self.bet = bet
        self.cards = cards
        self.isFromSplit = isFromSplit
        self.isSplitAces = isSplitAces
    }

    var value: HandValue { cards.handValue }

    var isNaturalBlackjack: Bool {
        !isFromSplit && cards.count == 2 && value.total == 21
    }

    var isPair: Bool {
        cards.count == 2 && cards[0].rank.pointValue == cards[1].rank.pointValue
    }

    var isSameRankPair: Bool {
        cards.count == 2 && cards[0].rank == cards[1].rank
    }

    var isSettled: Bool { outcome != nil }

    var netResult: Double { payout - bet }

    /// Short label for the hand badge in a tile
    var badgeText: String {
        if let outcome {
            switch outcome {
            case .blackjackWin: return "BJ " + CurrencyFormatter.signed(netResult)
            case .win, .loss: return CurrencyFormatter.signed(netResult)
            case .push: return "PUSH"
            case .surrendered: return "SURR"
            }
        }
        switch state {
        case .busted: return "BUST"
        case .blackjack: return "BLACKJACK"
        case .surrendered: return "SURR"
        case .playing, .stood: return cards.isEmpty ? "" : value.shortText
        }
    }
}

struct DealerHand: Equatable {
    var cards: [Card] = []
    var isHoleCardRevealed = false

    var upCard: Card? { cards.first }
    var holeCard: Card? { cards.count > 1 ? cards[1] : nil }

    var value: HandValue { cards.handValue }

    var visibleValue: HandValue? {
        if isHoleCardRevealed { return cards.isEmpty ? nil : value }
        guard let upCard else { return nil }
        return [upCard].handValue
    }

    var isBlackjack: Bool { cards.count == 2 && value.total == 21 }

    /// Indices of cards that should render face-down
    var hiddenIndices: Set<Int> { isHoleCardRevealed ? [] : [1] }
}
