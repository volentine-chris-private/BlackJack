//
//  TableModels.swift
//  BlackJack
//
//  Created by Chris Volentine on 11/2/26.
//

import Foundation

enum SeatPosition: Int, CaseIterable, Comparable {
    case topRight = 0
    case midRight
    case bottom
    case midLeft
    case topLeft

    static func < (lhs: SeatPosition, rhs: SeatPosition) -> Bool { lhs.rawValue < rhs.rawValue }
}

enum NPCStyle: String, CaseIterable, Equatable {
    /// Basic strategy + Illustrious 18 / Fab 4 deviations, bets ramp with the true count.
    case cardCounter
    /// Perfect basic strategy, mostly flat bets.
    case basicStrategist
    /// Mostly basic strategy with occasional "hunch" plays and erratic bets.
    case casual

    var title: String {
        switch self {
        case .cardCounter: return "Card Counter"
        case .basicStrategist: return "By the Book"
        case .casual: return "Casual"
        }
    }

    var mistakeRate: Double {
        switch self {
        case .cardCounter, .basicStrategist: return 0
        case .casual: return 0.15
        }
    }
}

struct NPCProfile: Equatable {
    var style: NPCStyle
    var baseUnit: Double
}

enum SeatKind: Equatable {
    case user
    case npc(NPCProfile)
}

struct Seat: Identifiable, Equatable {
    let id: UUID
    var name: String
    var kind: SeatKind
    let position: SeatPosition
    /// Chips at the table that aren't currently wagered.
    var stack: Double
    /// What the seat sat down with (plus any chips bought since). Used for  gain/loss label
    var startingStack: Double
    var hands: [PlayerHand] = []
    var lastBet: Double

    init(id: UUID = UUID(), name: String, kind: SeatKind, position: SeatPosition, stack: Double, lastBet: Double) {
        self.id = id
        self.name = name
        self.kind = kind
        self.position = position
        self.stack = stack
        self.startingStack = stack
        self.lastBet = lastBet
    }

    var isUser: Bool { kind == .user }

    var npcProfile: NPCProfile? {
        if case .npc(let profile) = kind { return profile }
        return nil
    }

    var inPlay: Double {
        hands.filter { !$0.isSettled }.reduce(0) { $0 + $1.bet }
    }

    var isInRound: Bool { !hands.isEmpty }

    var sessionNet: Double {
        Money.rounded(stack + inPlay - startingStack)
    }
}

enum GamePhase: String, Equatable {
    case betting
    case dealing
    case earlySurrender
    case playerTurns
    case dealerTurn
    case settling
    case roundComplete

    var displayName: String {
        switch self {
        case .betting: return "betting"
        case .dealing: return "the deal"
        case .earlySurrender: return "early surrender"
        case .playerTurns: return "player turns"
        case .dealerTurn: return "the dealer's turn"
        case .settling: return "settlement"
        case .roundComplete: return "the end of the round"
        }
    }
}

struct TurnPointer: Equatable {
    let seatIndex: Int
    let handIndex: Int
}

enum PlayerAction: String, CaseIterable, Identifiable {
    case stand
    case hit
    case doubleDown
    case split
    case surrender

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stand: return "Stand"
        case .hit: return "Hit"
        case .doubleDown: return "Double"
        case .split: return "Split"
        case .surrender: return "Surrender"
        }
    }

    var systemImage: String {
        switch self {
        case .stand: return "hand.raised.fill"
        case .hit: return "plus.circle.fill"
        case .doubleDown: return "arrow.down.to.line"
        case .split: return "arrow.triangle.branch"
        case .surrender: return "flag.fill"
        }
    }

    var pastTense: String {
        switch self {
        case .stand: return "stood"
        case .hit: return "hit"
        case .doubleDown: return "doubled down"
        case .split: return "split"
        case .surrender: return "surrendered"
        }
    }
}

/// Everything on the felt for one table session
struct TableState {
    var seats: [Seat]
    var dealer = DealerHand()
    var shoe: Shoe
    var phase: GamePhase = .betting
    var turn: TurnPointer?
    var roundNumber = 0

    var userSeatIndex: Int? { seats.firstIndex(where: { $0.isUser }) }

    var cardsOnTableCount: Int {
        seats.reduce(0) { total, seat in
            total + seat.hands.reduce(0) { $0 + $1.cards.count }
        } + dealer.cards.count
    }
}
