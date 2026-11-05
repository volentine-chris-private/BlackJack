//
//  BlackjackViewModel.swift
//  BlackJack
//
//  Created by Chris Volentine on 11/2/26.
//
import Foundation
import Observation
import os

/// Settings captured when the player sits down.
struct GameSessionConfig: Identifiable {
    let id = UUID()
    let buyIn: Double
    let rules: TableRules
}

/// - Drives one table session: betting, dealing, turn order, NPC decisions, the dealer,
/// settlement, banners, and persisting results after every hand
/// - A round runs as a single async task. When it's the player's turn the task suspends on a
/// continuation that resumes when either a button is tapped or the player forfeits
@Observable
@MainActor
final class BlackjackViewModel {
    // MARK: Types

    struct Banner: Identifiable, Equatable {
        enum Tone { case neutral, positive, negative, info }
        let id = UUID()
        let text: String
        let tone: Tone
    }

    private enum UserDecision {
        case action(PlayerAction)
        case declineEarlySurrender
        case abandon
    }

    /// Delays between table events in seconds. To help with pacing
    enum Timing {
        static let dealCard = 0.5
        static let npcThink = 1.6
        static let afterAction = 1.6
        static let dealerStep = 2.0
        static let roundSummary = 3.0
        static let shuffle = 2.4
        static let bannerLifetimeDefault = 1.6
        static let bannerLifetimeRoundOver = 3.0
        static let remoteShuffleDeadline: TimeInterval = 10
    }

    static let chipValues: [Double] = [5, 25, 100, 500, 1_000]

    // MARK: Dependencies

    private let services: AppServices
    private let engine: BlackjackEngine
    private let profile: UserProfile?
    private let requestedBuyIn: Double
    private let timingScale: Double
    let rules: TableRules

    // MARK: Observable state

    private(set) var table: TableState
    private(set) var banner: Banner?
    private(set) var isAwaitingUserAction = false
    private(set) var isAwaitingEarlySurrender = false
    private(set) var leaveAfterHand = false
    private(set) var shouldDismiss = false
    private(set) var lastUserResult: Double?
    private(set) var isRoundInProgress = false
    private(set) var isShuffling = false
    private(set) var pendingBet: Double = 0
    var isShowingForfeitConfirmation = false
    var isShowingOutOfChips = false
    var isShowingRebuy = false
    var isCountVisible = false

    // MARK: Internal state

    @ObservationIgnored private var flowTask: Task<Void, Never>?
    @ObservationIgnored private var bannerTask: Task<Void, Never>?
    @ObservationIgnored private var decisionContinuation: CheckedContinuation<UserDecision, Never>?
    @ObservationIgnored private var roundStartStack: Double?
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var hasReportedRemoteFallback = false

    // MARK: Init

    init(services: AppServices, config: GameSessionConfig, timingScale: Double = LaunchOptions.timingScale) {
        self.services = services
        self.rules = config.rules
        self.engine = BlackjackEngine(rules: config.rules)
        self.requestedBuyIn = config.buyIn
        self.timingScale = max(timingScale, 0)

        let profile = services.dataStore.fetchProfile()
        self.profile = profile

        let name = profile?.name ?? "You"
        let funds = profile?.totalFunds ?? 0
        let buyIn = Money.rounded(max(0, min(config.buyIn, funds)))

        // Every NPC sits down with the same amount the player chose. Fun to compare how well the NPC's strats are working.
        var seats = NPCBrain.makeNPCs(count: config.rules.npcCount, avoiding: name, startingStack: buyIn)
        seats.append(Seat(
            name: name,
            kind: .user,
            position: .bottom,
            stack: buyIn,
            lastBet: 0
        ))
        seats.sort { $0.position < $1.position }

        self.table = TableState(seats: seats, shoe: Shoe(deckCount: config.rules.deckCount))
    }

    // MARK: - Lifecycle

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true

        guard let profile else {
            services.errorCenter.report(AppError.persistence(.profileMissing), context: "BlackjackViewModel.start")
            shouldDismiss = true
            return
        }
        if !requestedBuyIn.isWithinToleranceOf(profile.totalFunds) {
            services.errorCenter.report(AppError.funds(.buyInAdjusted(to: userStack)), context: "BlackjackViewModel.start")
        }

        let npcNames = table.seats.filter { !$0.isUser }.map(\.name)
        if !npcNames.isEmpty {
            showBanner("\(npcNames.formatted(.list(type: .and))) joined the table", tone: .info)
        }

        do {
            try await shuffleShoe(reason: .newShoe)
        } catch {
            AppLogger.game.debug("Initial shuffle cancelled")
        }
    }

    func tearDown() {
        bannerTask?.cancel()
        /// If the app is killed mid-hand, the persisted pending wager is forfeited on next launch
        guard shouldDismiss else { return }
        cancelFlow()
    }

    // MARK: - Derived state

    var phase: GamePhase { table.phase }
    var userSeatIndex: Int? { table.userSeatIndex }
    var userSeat: Seat? { userSeatIndex.flatMap { table.seats[safe: $0] } }
    var userStack: Double { userSeat?.stack ?? 0 }
    var isBetting: Bool { table.phase == .betting && !isRoundInProgress && !isShuffling }

    func seat(at position: SeatPosition) -> Seat? {
        table.seats.first { $0.position == position }
    }

    func activeHandIndex(for seat: Seat?) -> Int? {
        guard let seat, let turn = table.turn, table.seats[safe: turn.seatIndex]?.id == seat.id else { return nil }
        return turn.handIndex
    }

    var availableActions: Set<PlayerAction> {
        if isAwaitingEarlySurrender { return [.surrender] }
        guard isAwaitingUserAction,
              let turn = table.turn,
              let seat = table.seats[safe: turn.seatIndex],
              seat.isUser else { return [] }
        return engine.legalActions(seat: seat, handIndex: turn.handIndex, phase: table.phase)
    }

    /// Amnt the player would lose by forfeiting in the moment
    var amountAtRisk: Double {
        guard let start = roundStartStack, let seat = userSeat else { return 0 }
        return Money.rounded(max(0, start - seat.stack))
    }

    var rebuyAvailable: Double {
        Money.rounded(max(0, (profile?.totalFunds ?? 0) - userStack))
    }

    var leaveButtonTitle: String {
        if isBetting { return "Leave Table" }
        return leaveAfterHand ? "Leaving after this hand · Tap to stay" : "Leave After This Hand"
    }

    var countSummary: String {
        let calc = services.countCalculator
        let dealt = Int((table.shoe.penetration * 100).rounded())
        return "RC \(calc.runningCountText)\nTC \(calc.trueCountText)\n\(dealt)% dealt"
    }

    var statusText: String {
        if isShuffling { return "Shuffling the shoe..." }
        if isAwaitingEarlySurrender, let up = table.dealer.upCard {
            return "Dealer shows \(up.rank.label). Surrender early for half your bet?"
        }
        switch table.phase {
        case .betting:
            return userStack < AppConfig.tableMinimumBet ? "You're out of chips" : "Place your bet"
        case .dealing:
            return "Dealing..."
        case .earlySurrender:
            return "Early surrender..."
        case .playerTurns:
            guard let turn = table.turn, let seat = table.seats[safe: turn.seatIndex] else { return "" }
            if seat.isUser, let hand = seat.hands[safe: turn.handIndex], let up = table.dealer.upCard {
                let handLabel = seat.hands.count > 1 ? "Hand \(turn.handIndex + 1): " : ""
                return "\(handLabel)\(hand.value.displayText) vs dealer \(up.rank.label)"
            }
            /// See here re: localizedStringWithFormat - https://stackoverflow.com/a/55569952
            return String.localizedStringWithFormat("%@ is deciding...", seat.name)
        case .dealerTurn:
            return "Dealer's turn"
        case .settling, .roundComplete:
            guard let result = lastUserResult else { return "Round complete" }
            return result == 0 ? "Push" : "Round result: \(CurrencyFormatter.signed(result))"
        }
    }

    // MARK: - Betting state

    var canDeal: Bool {
        isBetting && pendingBet >= AppConfig.tableMinimumBet && pendingBet.isWithinToleranceOf(userStack)
    }

    var canClearBet: Bool { isBetting && pendingBet > 0 }

    var canMaxBet: Bool {
        guard isBetting, userStack >= AppConfig.tableMinimumBet else { return false }
        return pendingBet < Money.floor(userStack, toMultipleOf: AppConfig.tableMinimumBet)
    }

    func canAddChip(_ value: Double) -> Bool {
        isBetting && (pendingBet + value).isWithinToleranceOf(userStack)
    }

    var dealHint: String? {
        guard isBetting else { return nil }
        if userStack < AppConfig.tableMinimumBet { return "Not enough chips for the minimum" }
        if pendingBet == 0 { return "Tap chips to build your bet" }
        if pendingBet < AppConfig.tableMinimumBet {
            return "Minimum bet is \(CurrencyFormatter.string(AppConfig.tableMinimumBet))"
        }
        return nil
    }

    // MARK: - Betting intents

    func addChip(_ value: Double) {
        guard isBetting else { return }
        guard canAddChip(value) else {
            services.errorCenter.report(
                AppError.game(.insufficientChips(needed: pendingBet + value, available: userStack)),
                context: "BlackjackViewModel.addChip"
            )
            return
        }
        pendingBet = Money.rounded(pendingBet + value)
    }

    func clearBet() {
        guard isBetting else { return }
        pendingBet = 0
    }

    func maxBet() {
        guard isBetting else { return }
        pendingBet = Money.floor(userStack, toMultipleOf: AppConfig.tableMinimumBet)
    }

    func deal() {
        guard flowTask == nil, isBetting else {
            services.errorCenter.report(
                AppError.game(.wrongPhase(expected: GamePhase.betting.displayName, actual: table.phase.displayName)),
                context: "BlackjackViewModel.deal"
            )
            return
        }
        if case .failure(let error) = InputValidator.validateBet(pendingBet, stack: userStack) {
            services.errorCenter.report(error, context: "BlackjackViewModel.deal")
            return
        }
        lastUserResult = nil
        isRoundInProgress = true
        flowTask = Task { [weak self] in
            await self?.playRound()
        }
    }

    // MARK: - Player intents

    func perform(_ action: PlayerAction) {
        if isAwaitingEarlySurrender {
            guard action == .surrender else { return }
            resume(with: .action(.surrender))
            return
        }
        guard isAwaitingUserAction, let turn = table.turn, let seat = table.seats[safe: turn.seatIndex], seat.isUser else {
            services.errorCenter.report(AppError.game(.notYourTurn), context: "BlackjackViewModel.perform")
            return
        }
        if let reason = engine.illegalReason(action, seat: seat, handIndex: turn.handIndex) {
            services.errorCenter.report(
                AppError.game(.illegalAction(action: action.title, reason: reason)),
                context: "BlackjackViewModel.perform"
            )
            return
        }
        resume(with: .action(action))
    }

    func declineEarlySurrender() {
        guard isAwaitingEarlySurrender else { return }
        resume(with: .declineEarlySurrender)
    }

    // MARK: - Leaving

    func leaveButtonTapped() {
        if isBetting {
            exitTable()
            return
        }
        leaveAfterHand.toggle()
        showBanner(leaveAfterHand ? "You'll leave after this hand" : "You're staying at the table", tone: .info)
    }

    func requestReturnHome() {
        isShowingForfeitConfirmation = true
    }

    func confirmForfeit() {
        isShowingForfeitConfirmation = false
        if roundStartStack != nil {
            forfeitCurrentRound()
        }
        cancelFlow()
        exitTable()
    }

    /// Bought chips aren't winnings so they're added to the seat's
    /// starting amount too and the gain/loss label doesn't change
    func rebuy(_ amount: Double) {
        isShowingRebuy = false
        guard isBetting, let index = userSeatIndex else { return }
        switch InputValidator.validateBuyIn(amount, available: rebuyAvailable) {
        case .success(let value):
            table.seats[index].stack = Money.rounded(table.seats[index].stack + value)
            table.seats[index].startingStack = Money.rounded(table.seats[index].startingStack + value)
            pendingBet = 0
            showBanner("Added \(CurrencyFormatter.string(value)) in chips", tone: .positive)
        case .failure(let error):
            services.errorCenter.report(error, context: "BlackjackViewModel.rebuy")
        }
    }

    // MARK: - Round flow

    private func playRound() async {
        defer {
            flowTask = nil
            isRoundInProgress = false
            isAwaitingUserAction = false
            isAwaitingEarlySurrender = false
        }
        do {
            try placeBetsAndStart()
            try await dealInitialCards()
            try await runEarlySurrenderIfOffered()
            let dealerHasBlackjack = try await peekForBlackjack()
            if !dealerHasBlackjack {
                try await runPlayerTurns()
                try await runDealerTurn()
            }
            try await settleRound()
            try await finishRound()
        } catch is CancellationError {
            AppLogger.game.debug("Round cancelled")
        } catch {
            recoverFromRoundFailure(error)
        }
    }

    private func prepareShoeIfNeeded() async throws {
        let calc = services.countCalculator
        let minimumCards = (table.seats.count + 1) * 8
        guard let reason = table.shoe.shuffleReason(
            rules: rules,
            trueCount: calc.trueCount,
            cardsSeenSinceShuffle: calc.cardsSeen,
            minimumCardsNeeded: minimumCards
        ) else { return }

        try await shuffleShoe(reason: reason)
        if reason.bannerText != nil {
            try await pause(Timing.shuffle)
        }
    }

    private func placeBetsAndStart() throws {
        guard let userIndex = userSeatIndex else { throw AppError.game(.seatMissing) }
        let trueCount = services.countCalculator.trueCount

        var bets: [UUID: Double] = [table.seats[userIndex].id: pendingBet]
        for seat in table.seats {
            guard let npc = seat.npcProfile else { continue }
            let wager = NPCBrain.wager(for: npc, stack: seat.stack, trueCount: trueCount)
            if wager > 0 { bets[seat.id] = wager }
        }

        let startingStack = table.seats[userIndex].stack
        try engine.startRound(table: &table, bets: bets)
        roundStartStack = startingStack
        updatePendingWager()
    }

    private func dealInitialCards() async throws {
        // Initial pause needed to allow for initial card animation
        try await pause(Timing.dealCard)
        
        for target in engine.initialDealSequence(table: table) {
            process(try engine.deal(to: target, table: &table))
            try await pause(Timing.dealCard)
        }
        engine.markNaturals(table: &table)

        let naturals = table.seats.filter { $0.hands.first?.state == .blackjack }
            .map { $0.isUser ? "You" : $0.name }
        if !naturals.isEmpty {
            let verb = (naturals.count > 1 || naturals == ["You"]) ? "have" : "has"
            showBanner("\(naturals.formatted(.list(type: .and))) \(verb) Blackjack!", tone: .positive)
            try await pause(Timing.afterAction)
        }
    }

    private func runEarlySurrenderIfOffered() async throws {
        guard engine.isEarlySurrenderOffered(table: table) else { return }
        guard let upCard = table.dealer.upCard?.rank else {
            throw AppError.game(.dealerStateInvalid("No dealer up-card."))
        }
        engine.beginEarlySurrender(table: &table)
        showBanner("Dealer shows \(upCard.label) - early surrender is open", tone: .info)
        try await pause(Timing.afterAction)

        for index in table.seats.indices {
            let seat = table.seats[index]
            guard engine.canEarlySurrender(seat: seat), let hand = seat.hands.first else { continue }
            table.turn = TurnPointer(seatIndex: index, handIndex: 0)

            let surrender: Bool
            switch seat.kind {
            case .user:
                switch await awaitUserDecision(earlySurrender: true) {
                case .abandon: throw CancellationError()
                case .action(let action): surrender = action == .surrender
                case .declineEarlySurrender: surrender = false
                }
            case .npc(let npc):
                try await pause(Timing.npcThink)
                surrender = NPCBrain.wantsEarlySurrender(profile: npc, hand: hand, dealerUpCard: upCard)
            }

            if surrender {
                try engine.applyEarlySurrender(seatIndex: index, table: &table)
                showBanner("\(seat.isUser ? "You" : seat.name) surrendered early", tone: .negative)
                if seat.isUser { updatePendingWager() }
                try await pause(Timing.afterAction)
            }
        }
        table.turn = nil
    }

    /// Returns `true` if the dealer has blackjack ( round goes straight to settlement)
    private func peekForBlackjack() async throws -> Bool {
        guard engine.dealerShouldPeek(table.dealer) else { return false }
        showBanner("Dealer checks for Blackjack...", tone: .neutral)
        try await pause(Timing.dealerStep)

        guard engine.dealerHasBlackjack(table.dealer) else {
            showBanner("No dealer Blackjack", tone: .info)
            try await pause(Timing.afterAction)
            return false
        }
        process(try engine.revealHoleCard(table: &table))
        showBanner("Dealer has Blackjack!", tone: .negative)
        try await pause(Timing.dealerStep)
        return true
    }

    private func runPlayerTurns() async throws {
        engine.beginPlayerTurns(table: &table)

        while true {
            process(try engine.advanceToNextTurn(table: &table))
            guard let pointer = table.turn else { break }
            guard let seat = table.seats[safe: pointer.seatIndex],
                  let hand = seat.hands[safe: pointer.handIndex] else {
                throw AppError.game(.noActiveHand)
            }

            let action: PlayerAction
            switch seat.kind {
            case .user:
                switch await awaitUserDecision(earlySurrender: false) {
                case .action(let chosen): action = chosen
                case .declineEarlySurrender: continue
                case .abandon: throw CancellationError()
                }
            case .npc(let npc):
                try await pause(Timing.npcThink)
                guard let upCard = table.dealer.upCard?.rank else {
                    throw AppError.game(.dealerStateInvalid("No dealer up-card."))
                }
                let legal = engine.legalActions(seat: seat, handIndex: pointer.handIndex, phase: table.phase)
                action = NPCBrain.decide(
                    profile: npc,
                    hand: hand,
                    dealerUpCard: upCard,
                    legal: legal,
                    rules: rules,
                    trueCount: services.countCalculator.trueCount
                )
            }

            process(try engine.perform(action, at: pointer, table: &table))
            announce(action, pointer: pointer)
            if seat.isUser { updatePendingWager() }
            try await pause(Timing.afterAction)
        }
    }

    private func runDealerTurn() async throws {
        engine.beginDealerTurn(table: &table)
        process(try engine.revealHoleCard(table: &table))
        showBanner("Dealer reveals \(table.dealer.value.displayText)", tone: .neutral)
        try await pause(Timing.dealerStep)

        guard engine.dealerNeedsToPlay(table) else { return }

        var draws = 0
        while engine.dealerShouldHit(table.dealer) {
            draws += 1
            guard draws <= 21 else {
                throw AppError.game(.dealerStateInvalid("The dealer drew too many cards."))
            }
            process(try engine.dealerDraw(table: &table))
            showBanner("Dealer hits - \(table.dealer.value.displayText)", tone: .neutral)
            try await pause(Timing.dealerStep)
        }

        let final = table.dealer.value
        if final.isBust {
            showBanner("Dealer busts!", bannerLifetime: Timing.bannerLifetimeRoundOver, tone: .positive)
        } else {
            showBanner("Dealer stands on \(final.total)", bannerLifetime: Timing.bannerLifetimeRoundOver, tone: .neutral)
        }
        try await pause(Timing.dealerStep)
    }

    private func settleRound() async throws {
        let results = engine.settle(table: &table)
        guard let userIndex = userSeatIndex else { throw AppError.game(.seatMissing) }

        if let start = roundStartStack {
            let delta = Money.rounded(table.seats[userIndex].stack - start)
            if let profile {
                services.ledger.applyHandResult(delta, to: profile)
            }
            roundStartStack = nil
            lastUserResult = delta

            let userOutcomes = results.first(where: { $0.isUser })?.outcomes ?? []
            showBanner(
                summary(for: delta, outcomes: userOutcomes),
                bannerLifetime: Timing.bannerLifetimeRoundOver,
                tone: delta > 0 ? .positive : (delta < 0 ? .negative : .neutral)
            )
        }
        services.countCalculator.persist()
        try await pause(Timing.roundSummary)
    }

    private func finishRound() async throws {
        engine.clearRound(table: &table)
        pendingBet = 0

        let departed = engine.removeBrokeNPCs(table: &table)
        if !departed.isEmpty {
            showBanner("\(departed.formatted(.list(type: .and))) left the table", tone: .info)
            try await pause(Timing.afterAction)
        }

        if leaveAfterHand {
            exitTable()
            return
        }

        try await prepareShoeIfNeeded()

        if userStack < AppConfig.tableMinimumBet {
            isShowingOutOfChips = true
        }
    }

    // MARK: - Error recovery

    private func recoverFromRoundFailure(_ error: Error) {
        let appError = AppError.wrap(error)
        AppLogger.game.error("Round failed: \(appError.message, privacy: .public)")

        if let continuation = decisionContinuation {
            decisionContinuation = nil
            continuation.resume(returning: .abandon)
        }

        engine.voidRound(table: &table)
        if roundStartStack != nil, let profile {
            services.ledger.setPendingWager(0, on: profile)
        }
        roundStartStack = nil
        lastUserResult = nil
        pendingBet = 0

        services.errorCenter.report(AppError.game(.handVoided(reason: appError.message)), context: "BlackjackViewModel.playRound")
    }

    /// Applies the loss of everything currently at risk.
    private func forfeitCurrentRound() {
        let loss = amountAtRisk
        if let profile {
            services.ledger.applyHandResult(-loss, to: profile)
        }
        roundStartStack = nil
        lastUserResult = -loss
        AppLogger.game.info("Player forfeited \(loss, privacy: .public)")
    }

    // MARK: - Shuffling

    /// Shuffles a fresh shoe. The order comes from the Deck of Cards API. any network failure
    /// (offline, timeout, bad data) falls back to an on-device shuffle so play never stops.
    /// Only cancellation is thrown
    private func shuffleShoe(reason: ShuffleReason) async throws {
        isShuffling = true
        defer { isShuffling = false }
        if let text = reason.bannerText {
            showBanner(text, tone: .info)
        }

        var usedRemote = false
        if table.cardsOnTableCount == 0 {
            let provider = services.deckProvider
            let deckCount = table.shoe.deckCount
            do {
                let order = try await NetworkDeadline.run(seconds: Timing.remoteShuffleDeadline) {
                    try await provider.shuffledShoe(deckCount: deckCount)
                }
                try Task.checkCancellation()
                try table.shoe.loadShuffledOrder(order, rules: rules)
                usedRemote = true
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                reportRemoteFallback(error)
            }
        }

        if !usedRemote {
            let repaired = table.shoe.shuffle(rules: rules, cardsOnTable: table.cardsOnTableCount)
            if repaired {
                services.errorCenter.report(
                    AppError.game(.invariantViolated("The shoe's card count was off, so it was rebuilt.")),
                    context: "BlackjackViewModel.shuffleShoe"
                )
            }
        }
        AppLogger.game.info("Shoe shuffled \(usedRemote ? "via Deck of Cards API" : "on device", privacy: .public)")
        services.countCalculator.reset(totalCards: table.shoe.totalCardCount, deckCount: table.shoe.deckCount)
    }

    /// Show the fallback notice once per session. Future failures are only logged
    private func reportRemoteFallback(_ error: Error) {
        let wrapped = AppError.wrap(error)
        AppLogger.game.notice("Remote shuffle failed: \(wrapped.message, privacy: .public)")
        guard !hasReportedRemoteFallback else { return }
        hasReportedRemoteFallback = true
        services.errorCenter.report(
            AppError.game(.remoteShuffleUnavailable(reason: wrapped.message)),
            context: "BlackjackViewModel.shuffleShoe"
        )
    }

    // MARK: - Helpers

    private func awaitUserDecision(earlySurrender: Bool) async -> UserDecision {
        if Task.isCancelled { return .abandon }
        if let stale = decisionContinuation {
            // Should never happen; resolve the stale wait so it can't leak.
            decisionContinuation = nil
            stale.resume(returning: .abandon)
        }
        return await withCheckedContinuation { continuation in
            decisionContinuation = continuation
            if earlySurrender {
                isAwaitingEarlySurrender = true
            } else {
                isAwaitingUserAction = true
            }
        }
    }

    private func resume(with decision: UserDecision) {
        guard let continuation = decisionContinuation else {
            services.errorCenter.report(AppError.game(.notYourTurn), context: "BlackjackViewModel.resume")
            return
        }
        decisionContinuation = nil
        isAwaitingUserAction = false
        isAwaitingEarlySurrender = false
        continuation.resume(returning: decision)
    }

    private func cancelFlow() {
        flowTask?.cancel()
        flowTask = nil
        isRoundInProgress = false
        if let continuation = decisionContinuation {
            decisionContinuation = nil
            continuation.resume(returning: .abandon)
        }
        isAwaitingUserAction = false
        isAwaitingEarlySurrender = false
    }

    private func exitTable() {
        services.persistAll(reason: "exit table")
        shouldDismiss = true
    }

    private func pause(_ seconds: Double) async throws {
        let scaled = max(seconds * timingScale, 0)
        try await Task.sleep(nanoseconds: UInt64(scaled * 1_000_000_000))
    }

    private func process(_ events: EngineEvents) {
        let calc = services.countCalculator
        for step in events.steps {
            switch step {
            case .revealed(let card):
                calc.register(card)
            case .emergencyReshuffle(let pileSize):
                calc.reset(totalCards: pileSize, deckCount: rules.deckCount)
                services.errorCenter.report(AppError.game(.shoeReshuffledMidHand), context: "BlackjackViewModel.process")
            }
        }
    }

    private func updatePendingWager() {
        guard let profile else { return }
        services.ledger.setPendingWager(amountAtRisk, on: profile)
    }

    private func announce(_ action: PlayerAction, pointer: TurnPointer) {
        guard let seat = table.seats[safe: pointer.seatIndex] else { return }
        let name = seat.isUser ? "You" : seat.name
        var text = String.localizedStringWithFormat("%@ \(action.pastTense)", name)
        var tone: Banner.Tone = .neutral

        if let hand = seat.hands[safe: pointer.handIndex] {
            switch hand.state {
            case .busted:
                text += " - bust!"
                tone = .negative
            default:
                if action == .hit || action == .doubleDown {
                    text += " - \(hand.value.displayText)"
                }
            }
        }
        if action == .surrender { tone = .negative }
        showBanner(text, tone: tone)
    }

    private func summary(for delta: Double, outcomes: [HandOutcome]) -> String {
        if outcomes.contains(.blackjackWin) && delta > 0 {
            return "Blackjack! You won \(CurrencyFormatter.string(delta))"
        }
        if delta > 0 { return "You won \(CurrencyFormatter.string(delta))" }
        if delta < 0 { return "You lost \(CurrencyFormatter.string(-delta))" }
        return outcomes.contains(.push) ? "Push - bet returned" : "You broke even"
    }

    private func showBanner(_ text: String, tone: Banner.Tone) {
        showBanner(text, bannerLifetime: Timing.bannerLifetimeDefault, tone: tone)
    }
    
    private func showBanner(_ text: String, bannerLifetime: Double, tone: Banner.Tone) {
        let newBanner = Banner(text: text, tone: tone)
        banner = newBanner
        bannerTask?.cancel()
        let lifetime = UInt64(max(bannerLifetime * timingScale, 0.5) * 1_000_000_000)
        bannerTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: lifetime)
            guard !Task.isCancelled, let self, self.banner?.id == newBanner.id else { return }
            self.banner = nil
        }
    }
}
