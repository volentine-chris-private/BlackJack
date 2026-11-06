//
//  TrueCountCalculator.swift
//  BlackJack
//
//  Created by Chris Volentine on 11/2/26.
//
import Foundation
import Observation
import SwiftData
import OSLog

/// Hi-Lo running/true count calculator backed by SwiftData (`CardCountState`)
///
/// A single instance lives in `AppServices` and can be used anywhere:
/// - Instance API - `register(_:)`, `reset(totalCards:deckCount:)`, `trueCount`, `isHot`...
/// - Static API - `TrueCountCalculator.trueCount(runningCount:decksRemaining:)` and
///   `hiLoValue(for:)` for pure calculations that don't touch stored state.
///
/// Only face-up cards are registered. The dealer's hole card is registered when revealed

@Observable
@MainActor
final class TrueCountCalculator {
    static let cardsPerDeck = 52
    /// Decks remaining never drops below half a deck, avoiding wild swings late in the shoe
    static let minimumDecksRemaining = 0.5

    private let context: ModelContext
    private let errorCenter: ErrorCenter
    private(set) var state: CardCountState

    init(context: ModelContext, errorCenter: ErrorCenter) {
        self.context = context
        self.errorCenter = errorCenter
        self.state = TrueCountCalculator.loadOrCreateState(context: context, errorCenter: errorCenter)
        validateState()
    }

    // MARK: - Reads

    var runningCount: Int { state.runningCount }
    var cardsSeen: Int { state.cardsSeen }
    var totalCards: Int { state.totalCards }
    var cardsRemaining: Int { max(state.totalCards - state.cardsSeen, 0) }

    var decksRemaining: Double {
        max(Double(cardsRemaining) / Double(Self.cardsPerDeck), Self.minimumDecksRemaining)
    }

    var trueCount: Double {
        Self.trueCount(runningCount: state.runningCount, decksRemaining: decksRemaining)
    }

    var flooredTrueCount: Int { Int(trueCount.rounded(.down)) }

    /// "Hot" = rich in 10s and Aces, per the threshold in `AppConfig`
    var isHot: Bool {
        state.cardsSeen >= AppConfig.hotDeckMinimumCardsSeen
            && trueCount >= AppConfig.hotDeckTrueCount
    }

    var trueCountText: String { String(format: "%+.1f", trueCount) }
    var runningCountText: String { state.runningCount > 0 ? "+\(state.runningCount)" : "\(state.runningCount)" }

    // MARK: - Writes

    func register(_ card: Card) {
        guard state.cardsSeen < state.totalCards else {
            // More cards than the shoe holds means the count is out of sync. Ignore the card
            // rather than letting decks-remaining go to zero
            errorCenter.report(AppError.game(.countDesynchronized), context: "TrueCountCalculator.register")
            return
        }
        state.runningCount += card.rank.hiLoValue
        state.cardsSeen += 1
        if card.rank == .ace { state.acesSeen += 1 }
        if card.rank.isTenValue { state.tensSeen += 1 }
        state.lastUpdated = Date()
    }

    func register(_ cards: [Card]) {
        cards.forEach { register($0) }
    }

    /// Starts counting a newly shuffled shoe or a reshuffled discard pile
    func reset(totalCards: Int, deckCount: Int) {
        state.runningCount = 0
        state.cardsSeen = 0
        state.acesSeen = 0
        state.tensSeen = 0
        state.totalCards = max(totalCards, 1)
        state.deckCount = max(deckCount, 1)
        state.shoesTracked += 1
        state.shoeStartedAt = Date()
        state.lastUpdated = Date()
        AppLogger.counting.debug("Count reset for \(totalCards) cards")
    }

    /// Saves the current count. Called at the end of each hand and when the app backgrounds
    func persist() {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            errorCenter.report(
                AppError.persistence(.saveFailed(reason: error.localizedDescription)),
                context: "TrueCountCalculator.persist"
            )
        }
    }

    // MARK: - Pure helpers

    nonisolated static func trueCount(runningCount: Int, decksRemaining: Double) -> Double {
        guard decksRemaining.isFinite, decksRemaining > 0 else { return 0 }
        return Double(runningCount) / decksRemaining
    }

    nonisolated static func hiLoValue(for rank: Rank) -> Int { rank.hiLoValue }

    nonisolated static func runningCount(for cards: [Card]) -> Int {
        cards.reduce(0) { $0 + $1.rank.hiLoValue }
    }

    // MARK: - Private

    private static func loadOrCreateState(context: ModelContext, errorCenter: ErrorCenter) -> CardCountState {
        do {
            let states = try context.fetch(FetchDescriptor<CardCountState>())
            if let first = states.first {
                if states.count > 1 {
                    states.dropFirst().forEach { context.delete($0) }
                    errorCenter.report(
                        AppError.persistence(.duplicateRecords(entity: "CardCountState", count: states.count)),
                        context: "TrueCountCalculator.load"
                    )
                }
                return first
            }
        } catch {
            errorCenter.report(
                AppError.persistence(.fetchFailed(entity: "card count", reason: error.localizedDescription)),
                context: "TrueCountCalculator.load"
            )
        }
        let state = CardCountState()
        context.insert(state)
        return state
    }

    private func validateState() {
        let invalid = state.totalCards <= 0
            || state.cardsSeen < 0
            || state.cardsSeen > state.totalCards
            || abs(state.runningCount) > state.totalCards
        if invalid {
            AppLogger.counting.notice("Stored count state was invalid; resetting.")
            reset(totalCards: max(state.deckCount, 1) * Self.cardsPerDeck, deckCount: max(state.deckCount, 1))
        }
    }
}
