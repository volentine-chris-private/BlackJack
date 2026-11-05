//
//  NPCBrain.swift
//  BlackJack
//
//  Created by Chris Volentine on 11/2/26.
//
import Foundation
import os

/// Seating, bet sizing and playing decisions
enum NPCBrain {

    static let seatFillOrder: [SeatPosition] = [.midRight, .midLeft, .topRight, .topLeft]

    // MARK: Seating

    /// Every NPC sits down with the same amount as the player and sizes its bets relative to that amount
    static func makeNPCs(count: Int, avoiding userName: String, startingStack: Double) -> [Seat] {
        let total = count.clamped(to: 0...seatFillOrder.count)
        guard total > 0 else { return [] }

        var names = NameGenerationService.newList(withCount: total)
        var seats: [Seat] = []
        for index in 0..<total {
            let name = names.isEmpty ? "Player \(index + 1)" : names.removeFirst()
            let style = NPCStyle.allCases.randomElement() ?? .basicStrategist
            let stack = Money.rounded(max(startingStack, 0))
            let unit = baseUnit(for: stack)
            seats.append(Seat(
                name: name,
                kind: .npc(NPCProfile(style: style, baseUnit: unit)),
                position: seatFillOrder[index],
                stack: stack,
                lastBet: unit
            ))
        }
        return seats
    }

    /// Between 2-5% of the starting stack, in $5 steps. Never below the table min
    static func baseUnit(for stack: Double) -> Double {
        let minimum = AppConfig.tableMinimumBet
        let fraction = Double.random(in: 0.02...0.05)
        return max(minimum, Money.floor(stack * fraction, toMultipleOf: minimum))
    }

    // MARK: Betting

    /// Card counters spread 1-8 units with the true count; others bet pretty flat.
    static func wager(for profile: NPCProfile, stack: Double, trueCount: Double) -> Double {
        let minimum = AppConfig.tableMinimumBet
        guard stack >= minimum else { return 0 }

        let units: Double
        switch profile.style {
        case .cardCounter:
            switch trueCount {
            case ..<1: units = 1
            case 1..<2: units = 2
            case 2..<3: units = 4
            case 3..<4: units = 6
            default: units = 8
            }
        case .basicStrategist:
            units = Double.random(in: 0..<1) < 0.15 ? 2 : 1
        case .casual:
            units = Double(Int.random(in: 1...3))
        }

        let desired = min(profile.baseUnit * units, stack)
        let rounded = Money.floor(desired, toMultipleOf: minimum)
        return max(minimum, rounded)
    }

    // MARK: Playing

    static func decide(
        profile: NPCProfile,
        hand: PlayerHand,
        dealerUpCard: Rank,
        legal: Set<PlayerAction>,
        rules: TableRules,
        trueCount: Double
    ) -> PlayerAction {
        guard !legal.isEmpty else { return .stand }

        let countForDeviations: Double? = profile.style == .cardCounter ? trueCount : nil
        var choice = BasicStrategy.recommend(
            hand: hand,
            dealerUpCard: dealerUpCard,
            legal: legal,
            rules: rules,
            trueCount: countForDeviations
        )

        // Casual players sometimes play a hunch, won't risk it on 12 or higher
        if Double.random(in: 0..<1) < profile.style.mistakeRate {
            if hand.value.total >= 12 {
                choice = .stand
            } else if legal.contains(.hit) {
                choice = .hit
            }
        }

        if legal.contains(choice) { return choice }
        AppLogger.game.notice("NPC chose illegal action \(choice.rawValue, privacy: .public). Falling back")
        return legal.contains(.stand) ? .stand : (legal.first ?? .stand)
    }

    static func wantsEarlySurrender(profile: NPCProfile, hand: PlayerHand, dealerUpCard: Rank) -> Bool {
        switch profile.style {
        case .cardCounter, .basicStrategist:
            return BasicStrategy.shouldEarlySurrender(hand: hand, dealerUpCard: dealerUpCard)
        case .casual:
            return false
        }
    }
}
