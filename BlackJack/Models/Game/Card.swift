//
//  Card.swift
//  BlackJack
//
//  Created by Chris Volentine on 11/2/26.
//

import Foundation

enum Suit: String, CaseIterable, Codable, Hashable, Sendable {
    case spades, diamonds, clubs, hearts

    var symbol: String {
        switch self {
        case .spades: return "♠"
        case .diamonds: return "♦"
        case .clubs: return "♣"
        case .hearts: return "♥"
        }
    }

    var isRed: Bool { self == .hearts || self == .diamonds }
}

enum Rank: Int, CaseIterable, Codable, Hashable, Comparable, Sendable {
    case two = 2, three, four, five, six, seven, eight, nine, ten, jack, queen, king, ace

    static func < (lhs: Rank, rhs: Rank) -> Bool { lhs.rawValue < rhs.rawValue }

    var label: String {
        switch self {
        case .jack: return "J"
        case .queen: return "Q"
        case .king: return "K"
        case .ace: return "A"
        default: return String(rawValue)
        }
    }

    var name: String {
        switch self {
        case .jack: return "Jack"
        case .queen: return "Queen"
        case .king: return "King"
        case .ace: return "Ace"
        default: return String(rawValue)
        }
    }

    /// Hard point value
    var pointValue: Int {
        switch self {
        case .ace: return 1
        case .ten, .jack, .queen, .king: return 10
        default: return rawValue
        }
    }

    var isTenValue: Bool { pointValue == 10 }

    /// Dealer up-card / pair value used by strategy tables
    var strategyValue: Int { self == .ace ? 11 : pointValue }

    /// Hi-Lo tag: 2-6 = +1, 7-9 = 0, 10-A = −1
    var hiLoValue: Int {
        switch self {
        case .two, .three, .four, .five, .six: return 1
        case .seven, .eight, .nine: return 0
        case .ten, .jack, .queen, .king, .ace: return -1
        }
    }
}

struct Card: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let rank: Rank
    let suit: Suit

    init(rank: Rank, suit: Suit, id: UUID = UUID()) {
        self.id = id
        self.rank = rank
        self.suit = suit
    }

    var accessibilityLabel: String { "\(rank.name) of \(suit.rawValue.capitalized)" }
}

struct HandValue: Equatable {
    let total: Int
    let isSoft: Bool

    var isBust: Bool { total > 21 }

    /// "Soft 18", "Bust (24)", "20"
    var displayText: String {
        if isBust { return "Bust (\(total))" }
        return isSoft ? "Soft \(total)" : "\(total)"
    }

    /// "8/18", "BUST", "20"
    var shortText: String {
        if isBust { return "BUST" }
        return isSoft ? "\(total - 10)/\(total)" : "\(total)"
    }
}

extension Collection where Element == Card {
    var handValue: HandValue {
        var hardTotal = 0
        var hasAce = false
        for card in self {
            hardTotal += card.rank.pointValue
            if card.rank == .ace { hasAce = true }
        }
        if hasAce && hardTotal + 10 <= 21 {
            return HandValue(total: hardTotal + 10, isSoft: true)
        }
        return HandValue(total: hardTotal, isSoft: false)
    }
}
