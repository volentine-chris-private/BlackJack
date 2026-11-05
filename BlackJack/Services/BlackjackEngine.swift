//
//  BlackjackEngine.swift
//  BlackJack
//
//  Created by Chris Volentine on 11/2/26.
//
import Foundation

/// Something the engine did that the view model needs to react to (in order)
enum EngineStep: Equatable {
    /// A card became visible to the table (must notify the true count calculator)
    case revealed(Card)
    /// The shoe ran dry mid-hand and the discard tray was reshuffled
    case emergencyReshuffle(pileSize: Int)
}

struct EngineEvents {
    private(set) var steps: [EngineStep] = []

    mutating func append(_ step: EngineStep) { steps.append(step) }
    mutating func merge(_ other: EngineEvents) { steps.append(contentsOf: other.steps) }
}

enum DealTarget: Equatable {
    case seat(Int)
    case dealer(faceUp: Bool)
}

struct SeatSettlement {
    let seatID: UUID
    let name: String
    let isUser: Bool
    let wagered: Double
    let returned: Double
    let outcomes: [HandOutcome]

    var net: Double { Money.rounded(returned - wagered) }
}

/// Blackjack rules engine. Doesn't hold a state of its own. Every function operates on a
/// `TableState` passed in by the view model
struct BlackjackEngine {
    let rules: TableRules

    // MARK: - Round setup

    func startRound(table: inout TableState, bets: [UUID: Double]) throws {
        guard table.phase == .betting else {
            throw AppError.game(.wrongPhase(expected: GamePhase.betting.displayName, actual: table.phase.displayName))
        }
        guard table.cardsOnTableCount == 0 else {
            throw AppError.game(.invariantViolated("Cards were still on the table at the start of a round."))
        }

        // Validate every bet before touching any stack so a bad bet can't leave things half-done
        var accepted: [Int: Double] = [:]
        for (index, seat) in table.seats.enumerated() {
            guard let bet = bets[seat.id], bet > 0 else { continue }
            guard bet >= AppConfig.tableMinimumBet else {
                throw AppError.game(.betBelowMinimum(minimum: AppConfig.tableMinimumBet))
            }
            guard bet.isWithinToleranceOf(seat.stack) else {
                throw AppError.game(.insufficientChips(needed: bet, available: seat.stack))
            }
            accepted[index] = Money.rounded(bet)
        }
        guard !accepted.isEmpty else { throw AppError.game(.noBetsPlaced) }

        for index in table.seats.indices {
            if let bet = accepted[index] {
                table.seats[index].stack = Money.rounded(table.seats[index].stack - bet)
                table.seats[index].hands = [PlayerHand(bet: bet)]
                table.seats[index].lastBet = bet
            } else {
                table.seats[index].hands = []
            }
        }
        table.dealer = DealerHand()
        table.turn = nil
        table.roundNumber += 1
        table.phase = .dealing
    }

    func initialDealSequence(table: TableState) -> [DealTarget] {
        let seatIndices = table.seats.indices.filter { table.seats[$0].isInRound }
        var sequence: [DealTarget] = []
        sequence += seatIndices.map { DealTarget.seat($0) }
        sequence.append(.dealer(faceUp: true))
        sequence += seatIndices.map { DealTarget.seat($0) }
        sequence.append(.dealer(faceUp: false))
        return sequence
    }

    func deal(to target: DealTarget, table: inout TableState) throws -> EngineEvents {
        guard table.phase == .dealing else {
            throw AppError.game(.wrongPhase(expected: GamePhase.dealing.displayName, actual: table.phase.displayName))
        }
        var events = EngineEvents()
        switch target {
        case .seat(let index):
            guard table.seats.indices.contains(index), !table.seats[index].hands.isEmpty else {
                throw AppError.game(.invariantViolated("Tried to deal to an empty seat."))
            }
            let card = try draw(&table, events: &events)
            table.seats[index].hands[0].cards.append(card)
            events.append(.revealed(card))
        case .dealer(let faceUp):
            let card = try draw(&table, events: &events)
            table.dealer.cards.append(card)
            if faceUp { events.append(.revealed(card)) }
        }
        return events
    }

    /// Flag player naturals after the initial deal
    func markNaturals(table: inout TableState) {
        for s in table.seats.indices {
            for h in table.seats[s].hands.indices where table.seats[s].hands[h].isNaturalBlackjack {
                table.seats[s].hands[h].state = .blackjack
            }
        }
    }

    // MARK: - Dealer peek & early surrender

    func dealerShouldPeek(_ dealer: DealerHand) -> Bool {
        guard let up = dealer.upCard else { return false }
        return up.rank == .ace || up.rank.isTenValue
    }

    func isEarlySurrenderOffered(table: TableState) -> Bool {
        rules.canEarlySurrender && dealerShouldPeek(table.dealer)
    }

    func beginEarlySurrender(table: inout TableState) {
        table.phase = .earlySurrender
    }

    func canEarlySurrender(seat: Seat) -> Bool {
        guard seat.hands.count == 1, let hand = seat.hands.first else { return false }
        return hand.state == .playing && hand.cards.count == 2
    }

    func applyEarlySurrender(seatIndex: Int, table: inout TableState) throws {
        guard table.phase == .earlySurrender else {
            throw AppError.game(.wrongPhase(expected: GamePhase.earlySurrender.displayName, actual: table.phase.displayName))
        }
        guard let seat = table.seats[safe: seatIndex], canEarlySurrender(seat: seat) else {
            throw AppError.game(.illegalAction(action: PlayerAction.surrender.title, reason: "Early surrender is only available on your first two cards."))
        }
        surrenderHand(seatIndex: seatIndex, handIndex: 0, table: &table)
    }

    func dealerHasBlackjack(_ dealer: DealerHand) -> Bool { dealer.isBlackjack }

    func revealHoleCard(table: inout TableState) throws -> EngineEvents {
        var events = EngineEvents()
        guard !table.dealer.isHoleCardRevealed else { return events }
        guard let hole = table.dealer.holeCard else {
            throw AppError.game(.dealerStateInvalid("The dealer has no hole card."))
        }
        table.dealer.isHoleCardRevealed = true
        events.append(.revealed(hole))
        return events
    }

    // MARK: - Player turns

    func beginPlayerTurns(table: inout TableState) {
        table.phase = .playerTurns
        table.turn = nil
    }

    /// Finds the next hand that needs a decision. Split hands waiting for their second card
    /// are dealt it here. Hands that resolve automatically (like 21 or split aces depending
    /// on its config setting) are skipped. Sets `table.turn` to nil when all players are done
    func advanceToNextTurn(table: inout TableState) throws -> EngineEvents {
        var events = EngineEvents()
        while let pointer = firstPlayableHand(in: table) {
            let s = pointer.seatIndex
            let h = pointer.handIndex
            if table.seats[s].hands[h].cards.count < 2 {
                let card = try draw(&table, events: &events)
                table.seats[s].hands[h].cards.append(card)
                events.append(.revealed(card))
                autoResolveSplitHand(seatIndex: s, handIndex: h, table: &table)
                continue
            }
            if table.seats[s].hands[h].value.total >= 21 {
                table.seats[s].hands[h].state = table.seats[s].hands[h].value.isBust ? .busted : .stood
                continue
            }
            table.turn = pointer
            return events
        }
        table.turn = nil
        return events
    }

    func legalActions(seat: Seat, handIndex: Int, phase: GamePhase) -> Set<PlayerAction> {
        guard phase == .playerTurns else { return [] }
        return Set(PlayerAction.allCases.filter { illegalReason($0, seat: seat, handIndex: handIndex) == nil })
    }

    func illegalReason(_ action: PlayerAction, seat: Seat, handIndex: Int) -> String? {
        guard let hand = seat.hands[safe: handIndex] else { return "There's no hand to play." }
        guard hand.state == .playing else { return "This hand is already finished." }

        switch action {
        case .stand:
            return nil

        case .hit:
            if hand.isSplitAces { return "Split aces receive only one card." }
            if hand.doubleCount > 0 { return "You can't hit after doubling down." }
            if hand.value.total >= 21 { return "This hand is already at 21." }
            return nil

        case .doubleDown:
            if hand.value.total >= 21 { return "This hand is already at 21." }
            if hand.doubleCount > 0 {
                if !rules.canReDouble { return "Re-doubling isn't allowed at this table." }
                if hand.doubleCount >= AppConfig.maxDoublesPerHand {
                    return "A hand can be doubled at most \(AppConfig.maxDoublesPerHand) times."
                }
            } else {
                if hand.isSplitAces { return "Split aces can't be doubled." }
                if hand.cards.count > 2 && !rules.canDoubleAfterHit {
                    return "You can only double on your first two cards."
                }
                if hand.isFromSplit && !rules.canDoubleAfterSplit {
                    return "Doubling after a split isn't allowed."
                }
                if !rules.doubleDownRule.permits(hand.value) {
                    return "This table only allows doubling on \(rules.doubleDownRule.restrictionDescription)."
                }
            }
            if !hand.bet.isWithinToleranceOf(seat.stack) {
                return "You need \(CurrencyFormatter.string(hand.bet)) more on the table to double."
            }
            return nil

        case .split:
            if hand.cards.count != 2 || hand.doubleCount > 0 || hand.actionsTaken > 0 {
                return "You can only split your first two cards."
            }
            if !hand.isPair { return "Only pairs can be split." }
            if rules.enforceSameRankSplits && !hand.isSameRankPair {
                return "Cards must be the same rank to split (e.g. K-K, not K-Q)."
            }
            if seat.hands.count >= rules.reSplitRule.maxHands { return rules.reSplitRule.limitDescription }
            if hand.isSplitAces && !rules.canReSplitAces { return "Re-splitting aces isn't allowed." }
            if !hand.bet.isWithinToleranceOf(seat.stack) {
                return "You need \(CurrencyFormatter.string(hand.bet)) more on the table to split."
            }
            return nil

        case .surrender:
            if !rules.canLateSurrender { return "Surrender isn't offered at this table." }
            if seat.hands.count > 1 || hand.isFromSplit { return "You can't surrender after splitting." }
            if hand.cards.count != 2 || hand.actionsTaken > 0 { return "Surrender must be your first decision." }
            return nil
        }
    }

    func perform(_ action: PlayerAction, at pointer: TurnPointer, table: inout TableState) throws -> EngineEvents {
        guard table.phase == .playerTurns else {
            throw AppError.game(.wrongPhase(expected: GamePhase.playerTurns.displayName, actual: table.phase.displayName))
        }
        guard table.turn == pointer else { throw AppError.game(.notYourTurn) }
        guard let seat = table.seats[safe: pointer.seatIndex],
              seat.hands.indices.contains(pointer.handIndex) else {
            throw AppError.game(.noActiveHand)
        }
        if let reason = illegalReason(action, seat: seat, handIndex: pointer.handIndex) {
            throw AppError.game(.illegalAction(action: action.title, reason: reason))
        }

        let s = pointer.seatIndex
        let h = pointer.handIndex
        var events = EngineEvents()

        switch action {
        case .hit:
            let card = try draw(&table, events: &events)
            table.seats[s].hands[h].cards.append(card)
            table.seats[s].hands[h].actionsTaken += 1
            events.append(.revealed(card))
            resolveAfterDraw(seatIndex: s, handIndex: h, table: &table)

        case .stand:
            table.seats[s].hands[h].actionsTaken += 1
            table.seats[s].hands[h].state = .stood

        case .doubleDown:
            let extra = table.seats[s].hands[h].bet
            table.seats[s].stack = Money.rounded(table.seats[s].stack - extra)
            table.seats[s].hands[h].bet = Money.rounded(table.seats[s].hands[h].bet + extra)
            table.seats[s].hands[h].doubleCount += 1
            table.seats[s].hands[h].actionsTaken += 1
            let card = try draw(&table, events: &events)
            table.seats[s].hands[h].cards.append(card)
            events.append(.revealed(card))

            let hand = table.seats[s].hands[h]
            if hand.value.isBust {
                table.seats[s].hands[h].state = .busted
            } else if rules.canReDouble
                        && hand.doubleCount < AppConfig.maxDoublesPerHand
                        && hand.value.total < 21
                        && hand.bet.isWithinToleranceOf(table.seats[s].stack) {
                table.seats[s].hands[h].state = .playing
            } else {
                table.seats[s].hands[h].state = .stood
            }

        case .split:
            let original = table.seats[s].hands[h]
            let isAces = original.cards[0].rank == .ace
            table.seats[s].stack = Money.rounded(table.seats[s].stack - original.bet)
            let first = PlayerHand(bet: original.bet, cards: [original.cards[0]], isFromSplit: true, isSplitAces: isAces)
            let second = PlayerHand(bet: original.bet, cards: [original.cards[1]], isFromSplit: true, isSplitAces: isAces)
            table.seats[s].hands[h] = first
            table.seats[s].hands.insert(second, at: h + 1)
            // Second cards are dealt by `advanceToNextTurn` as each hand comes up

        case .surrender:
            surrenderHand(seatIndex: s, handIndex: h, table: &table)
        }
        return events
    }

    // MARK: - Dealer

    func beginDealerTurn(table: inout TableState) {
        table.phase = .dealerTurn
        table.turn = nil
    }

    /// dealer only draws if at least one player hand is still standing
    func dealerNeedsToPlay(_ table: TableState) -> Bool {
        table.seats.contains { seat in seat.hands.contains { $0.state == .stood } }
    }

    func dealerShouldHit(_ dealer: DealerHand) -> Bool {
        let value = dealer.value
        if value.total < 17 { return true }
        if value.total == 17 && value.isSoft && !rules.dealerStandsOnSoft17 { return true }
        return false
    }

    func dealerDraw(table: inout TableState) throws -> EngineEvents {
        guard table.dealer.isHoleCardRevealed else {
            throw AppError.game(.dealerStateInvalid("The hole card must be revealed before the dealer draws."))
        }
        var events = EngineEvents()
        let card = try draw(&table, events: &events)
        table.dealer.cards.append(card)
        events.append(.revealed(card))
        return events
    }

    // MARK: - Settlement

    @discardableResult
    func settle(table: inout TableState) -> [SeatSettlement] {
        table.phase = .settling
        let dealerValue = table.dealer.value
        let dealerBlackjack = table.dealer.isBlackjack
        var results: [SeatSettlement] = []

        for s in table.seats.indices where table.seats[s].isInRound {
            var wagered = 0.0
            var returned = 0.0
            var outcomes: [HandOutcome] = []

            for h in table.seats[s].hands.indices {
                var hand = table.seats[s].hands[h]
                wagered += hand.bet

                if let existing = hand.outcome {
                    // Surrendered earlier, refund already credited
                    returned += hand.payout
                    outcomes.append(existing)
                    continue
                }

                let (outcome, payout) = resolve(hand, dealerValue: dealerValue, dealerBlackjack: dealerBlackjack)
                hand.outcome = outcome
                hand.payout = payout
                table.seats[s].hands[h] = hand
                table.seats[s].stack = Money.rounded(table.seats[s].stack + payout)
                returned += payout
                outcomes.append(outcome)
            }

            let seat = table.seats[s]
            results.append(SeatSettlement(
                seatID: seat.id,
                name: seat.name,
                isUser: seat.isUser,
                wagered: Money.rounded(wagered),
                returned: Money.rounded(returned),
                outcomes: outcomes
            ))
        }

        table.turn = nil
        table.phase = .roundComplete
        return results
    }

    private func resolve(_ hand: PlayerHand, dealerValue: HandValue, dealerBlackjack: Bool) -> (HandOutcome, Double) {
        let bet = hand.bet
        switch hand.state {
        case .surrendered:
            return (.surrendered, Money.rounded(bet / 2))
        case .busted:
            return (.loss, 0)
        case .blackjack:
            if dealerBlackjack { return (.push, bet) }
            return (.blackjackWin, Money.rounded(bet + bet * rules.blackjackPayout))
        case .playing, .stood:
            if dealerBlackjack { return (.loss, 0) }
            let player = hand.value.total
            if player > 21 { return (.loss, 0) }
            if dealerValue.isBust || player > dealerValue.total { return (.win, Money.rounded(bet * 2)) }
            if player == dealerValue.total { return (.push, bet) }
            return (.loss, 0)
        }
    }

    // MARK: - Cleanup

    /// Moves every card on the table to the discard tray and returns to betting
    func clearRound(table: inout TableState) {
        var collected: [Card] = []
        for s in table.seats.indices {
            for hand in table.seats[s].hands { collected.append(contentsOf: hand.cards) }
            table.seats[s].hands = []
        }
        collected.append(contentsOf: table.dealer.cards)
        table.shoe.discard(collected)
        table.dealer = DealerHand()
        table.turn = nil
        table.phase = .betting
    }

    /// Error recovery: refunds every unsettled wager in full and then clears the table
    func voidRound(table: inout TableState) {
        guard table.phase != .roundComplete else {
            clearRound(table: &table)
            return
        }
        for s in table.seats.indices {
            var refund = 0.0
            for hand in table.seats[s].hands {
                refund += hand.isSettled ? max(0, hand.bet - hand.payout) : hand.bet
            }
            table.seats[s].stack = Money.rounded(table.seats[s].stack + refund)
        }
        clearRound(table: &table)
    }

    /// Removes NPCs who can no longer cover the table minimum
    func removeBrokeNPCs(table: inout TableState) -> [String] {
        let broke = table.seats.filter { !$0.isUser && $0.stack < AppConfig.tableMinimumBet }
        guard !broke.isEmpty else { return [] }
        table.seats.removeAll { seat in broke.contains { $0.id == seat.id } }
        return broke.map(\.name)
    }

    // MARK: - Private helpers

    private func draw(_ table: inout TableState, events: inout EngineEvents) throws -> Card {
        let result = try table.shoe.draw()
        if let pileSize = result.reshuffledPileSize {
            events.append(.emergencyReshuffle(pileSize: pileSize))
        }
        return result.card
    }

    private func firstPlayableHand(in table: TableState) -> TurnPointer? {
        for (s, seat) in table.seats.enumerated() {
            if let h = seat.hands.firstIndex(where: { $0.state == .playing }) {
                return TurnPointer(seatIndex: s, handIndex: h)
            }
        }
        return nil
    }

    private func resolveAfterDraw(seatIndex s: Int, handIndex h: Int, table: inout TableState) {
        let value = table.seats[s].hands[h].value
        if value.isBust {
            table.seats[s].hands[h].state = .busted
        } else if value.total == 21 {
            table.seats[s].hands[h].state = .stood
        }
    }

    private func autoResolveSplitHand(seatIndex s: Int, handIndex h: Int, table: inout TableState) {
        let hand = table.seats[s].hands[h]
        if hand.value.total == 21 {
            // 21 after a split is a non-blackjack auto-stand
            table.seats[s].hands[h].state = .stood
            return
        }
        guard hand.isSplitAces else { return }
        let drewAnotherAce = hand.cards.count == 2 && hand.cards[1].rank == .ace
        let canResplit = drewAnotherAce
            && rules.canReSplitAces
            && table.seats[s].hands.count < rules.reSplitRule.maxHands
            && hand.bet.isWithinToleranceOf(table.seats[s].stack)
        if !canResplit {
            table.seats[s].hands[h].state = .stood
        }
    }

    private func surrenderHand(seatIndex s: Int, handIndex h: Int, table: inout TableState) {
        let refund = Money.rounded(table.seats[s].hands[h].bet / 2)
        table.seats[s].hands[h].state = .surrendered
        table.seats[s].hands[h].outcome = .surrendered
        table.seats[s].hands[h].payout = refund
        table.seats[s].hands[h].actionsTaken += 1
        table.seats[s].stack = Money.rounded(table.seats[s].stack + refund)
    }
}
