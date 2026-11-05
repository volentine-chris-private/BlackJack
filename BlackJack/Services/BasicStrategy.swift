//
//  BasicStrategy.swift
//  BlackJack
//
//  Created by Chris Volentine on 11/2/26.
//
import Foundation

/// Multi-deck basic strat. Adapts to the table's rules (S17/H17, DAS, deck count),
/// plus Hi-Lo index plays when a true count is supplied
///
/// Dealer up-card values use `Rank.strategyValue` (2-10, Ace = 11)
enum BasicStrategy {
    enum Play: Equatable {
        case hit
        case stand
        case doubleOrHit
        case doubleOrStand
    }

    /// - Parameter trueCount: pass `nil` for pure basic strategy, or the current true count to
    ///   apply count-based deviations
    static func recommend(
        hand: PlayerHand,
        dealerUpCard: Rank,
        legal: Set<PlayerAction>,
        rules: TableRules,
        trueCount: Double?
    ) -> PlayerAction {
        guard !legal.isEmpty else { return .stand }
        let dealer = dealerUpCard.strategyValue

        if legal.contains(.surrender),
           shouldLateSurrender(hand: hand, dealer: dealer, rules: rules, trueCount: trueCount) {
            return .surrender
        }

        if legal.contains(.split),
           shouldSplit(hand: hand, dealer: dealer, rules: rules, trueCount: trueCount) {
            return .split
        }

        let value = hand.value
        let play = value.isSoft
            ? softPlay(total: value.total, dealer: dealer, rules: rules)
            : hardPlay(total: value.total, dealer: dealer, rules: rules, trueCount: trueCount)
        return resolve(play, legal: legal)
    }

    // MARK: - Hard totals

    static func hardPlay(total: Int, dealer: Int, rules: TableRules, trueCount: Double?) -> Play {
        if let trueCount, let deviation = hardDeviation(total: total, dealer: dealer, trueCount: trueCount) {
            return deviation
        }
        let hitsSoft17 = !rules.dealerStandsOnSoft17
        let fewDecks = rules.deckCount <= 2

        switch total {
        case 17...:
            return .stand
        case 13...16:
            return dealer <= 6 ? .stand : .hit
        case 12:
            return (4...6).contains(dealer) ? .stand : .hit
        case 11:
            if dealer == 11 { return (hitsSoft17 || fewDecks) ? .doubleOrHit : .hit }
            return .doubleOrHit
        case 10:
            return dealer <= 9 ? .doubleOrHit : .hit
        case 9:
            return ((3...6).contains(dealer) || (fewDecks && dealer == 2)) ? .doubleOrHit : .hit
        case 8:
            return (fewDecks && (5...6).contains(dealer)) ? .doubleOrHit : .hit
        default:
            return .hit
        }
    }

    static func hardDeviation(total: Int, dealer: Int, trueCount tc: Double) -> Play? {
        switch (total, dealer) {
        case (16, 10): return tc >= 0 ? .stand : .hit
        case (16, 9): return tc >= 5 ? .stand : nil
        case (15, 10): return tc >= 4 ? .stand : nil
        case (13, 2): return tc <= -1 ? .hit : nil
        case (13, 3): return tc <= -2 ? .hit : nil
        case (12, 2): return tc >= 3 ? .stand : nil
        case (12, 3): return tc >= 2 ? .stand : nil
        case (12, 4): return tc < 0 ? .hit : nil
        case (12, 5): return tc <= -2 ? .hit : nil
        case (12, 6): return tc <= -1 ? .hit : nil
        case (11, 11): return tc >= 1 ? .doubleOrHit : nil
        case (10, 10): return tc >= 4 ? .doubleOrHit : nil
        case (10, 11): return tc >= 4 ? .doubleOrHit : nil
        case (9, 2): return tc >= 1 ? .doubleOrHit : nil
        case (9, 7): return tc >= 3 ? .doubleOrHit : nil
        default: return nil
        }
    }

    // MARK: - Soft totals

    static func softPlay(total: Int, dealer: Int, rules: TableRules) -> Play {
        let hitsSoft17 = !rules.dealerStandsOnSoft17
        switch total {
        case 20...:
            return .stand
        case 19:
            return (hitsSoft17 && dealer == 6) ? .doubleOrStand : .stand
        case 18:
            if (3...6).contains(dealer) || (hitsSoft17 && dealer == 2) { return .doubleOrStand }
            return dealer <= 8 ? .stand : .hit
        case 17:
            return (3...6).contains(dealer) ? .doubleOrHit : .hit
        case 15, 16:
            return (4...6).contains(dealer) ? .doubleOrHit : .hit
        case 13, 14:
            return (5...6).contains(dealer) ? .doubleOrHit : .hit
        default:
            return .hit
        }
    }

    // MARK: - Pairs

    static func shouldSplit(hand: PlayerHand, dealer: Int, rules: TableRules, trueCount: Double?) -> Bool {
        guard hand.cards.count == 2, hand.isPair else { return false }
        let doubleAfterSplit = rules.canDoubleAfterSplit

        switch hand.cards[0].rank.strategyValue {
        case 11: return true
        case 10:
            // Only counters split tens, and only when the count is really high
            guard let tc = trueCount else { return false }
            if dealer == 5 { return tc >= 5 }
            if dealer == 6 { return tc >= 4 }
            return false
        case 9: return [2, 3, 4, 5, 6, 8, 9].contains(dealer)
        case 8: return true
        case 7: return dealer <= 7
        case 6: return doubleAfterSplit ? dealer <= 6 : (3...6).contains(dealer)
        case 5: return false
        case 4: return doubleAfterSplit && (5...6).contains(dealer)
        case 2, 3: return doubleAfterSplit ? dealer <= 7 : (4...7).contains(dealer)
        default: return false
        }
    }

    // MARK: - Surrender

    static func shouldLateSurrender(hand: PlayerHand, dealer: Int, rules: TableRules, trueCount: Double?) -> Bool {
        guard hand.cards.count == 2 else { return false }
        let value = hand.value
        guard !value.isSoft else { return false }
        let hitsSoft17 = !rules.dealerStandsOnSoft17

        if hand.cards[0].rank == .eight && hand.cards[1].rank == .eight {
            return hitsSoft17 && dealer == 11
        }

        if let tc = trueCount {
            switch (value.total, dealer) {
            case (14, 10): return tc >= 3
            case (15, 10): return tc >= 0
            case (15, 9): return tc >= 2
            case (15, 11): return hitsSoft17 ? tc >= -1 : tc >= 1
            default: break
            }
        }

        switch value.total {
        case 16: return dealer >= 9
        case 15: return dealer == 10 || (hitsSoft17 && dealer == 11)
        case 17: return hitsSoft17 && dealer == 11
        default: return false
        }
    }

    static func shouldEarlySurrender(hand: PlayerHand, dealerUpCard: Rank) -> Bool {
        guard hand.cards.count == 2, !hand.isNaturalBlackjack else { return false }
        let dealer = dealerUpCard.strategyValue
        let value = hand.value
        let pairValue: Int? = hand.isPair ? hand.cards[0].rank.strategyValue : nil

        if dealer == 11 {
            if let pairValue { return [3, 6, 7, 8].contains(pairValue) }
            return !value.isSoft && ((5...7).contains(value.total) || (12...17).contains(value.total))
        }
        if dealer == 10 {
            if let pairValue { return [7, 8].contains(pairValue) }
            return !value.isSoft && (14...16).contains(value.total)
        }
        return false
    }

    // MARK: - Resoltion

    private static func resolve(_ play: Play, legal: Set<PlayerAction>) -> PlayerAction {
        switch play {
        case .stand:
            return .stand
        case .hit:
            return legal.contains(.hit) ? .hit : .stand
        case .doubleOrHit:
            if legal.contains(.doubleDown) { return .doubleDown }
            return legal.contains(.hit) ? .hit : .stand
        case .doubleOrStand:
            return legal.contains(.doubleDown) ? .doubleDown : .stand
        }
    }
}
