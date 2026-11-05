//
//  RuleOptions.swift
//  BlackJack
//
//  Created by Chris Volentine on 11/2/26.
//

enum ShuffleMethod: String, CaseIterable, Identifiable, Codable {
    case penetrationRange
    case timedInterval
    case hotDeck
    case continuous

    var id: String { rawValue }

    var title: String {
        switch self {
        case .penetrationRange: return "After a % of the shoe"
        case .timedInterval: return "After a set time"
        case .hotDeck: return "When the deck runs hot"
        case .continuous: return "Continuous shuffler"
        }
    }

    var detail: String {
        switch self {
        case .penetrationRange:
            return "A cut card is placed at a random point between the two percentages. The shoe is shuffled once it's reached."
        case .timedInterval:
            return "The shoe is shuffled after a random amount of time between the two values."
        case .hotDeck:
            return "The dealer shuffles whenever the true count reaches +\(Int(AppConfig.hotDeckTrueCount)) (rich in 10s and Aces). If it never gets hot, the percentage range below is used."
        case .continuous:
            return "Every card goes back in and the shoe is fully shuffled after every hand. Counting is useless."
        }
    }

    var usesPenetrationRange: Bool { self == .penetrationRange || self == .hotDeck }
}


enum DoubleDownRule: String, CaseIterable, Identifiable, Codable {
    case anyHand
    case anyHardHand
    case anyNineToEleven
    case hardNineToEleven

    var id: String { rawValue }

    var title: String {
        switch self {
        case .anyHand: return "Any hand"
        case .anyHardHand: return "Any hard hand"
        case .anyNineToEleven: return "9-11 (hard or soft)"
        case .hardNineToEleven: return "Hard 9-11 only"
        }
    }

    var restrictionDescription: String {
        switch self {
        case .anyHand: return "any hand"
        case .anyHardHand: return "hard totals"
        case .anyNineToEleven: return "totals of 9-11"
        case .hardNineToEleven: return "hard totals of 9-11"
        }
    }

    func permits(_ value: HandValue) -> Bool {
        let lowTotal = value.isSoft ? value.total - 10 : value.total
        switch self {
        case .anyHand:
            return true
        case .anyHardHand:
            return !value.isSoft
        case .anyNineToEleven:
            return (9...11).contains(value.total) || (value.isSoft && (9...11).contains(lowTotal))
        case .hardNineToEleven:
            return !value.isSoft && (9...11).contains(value.total)
        }
    }
}


enum ReSplitRule: String, CaseIterable, Identifiable, Codable {
    case fourHandMax
    case noReSplits
    case infiniteReSplits

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fourHandMax: return "Up to 4 hands"
        case .noReSplits: return "No re-splits"
        case .infiniteReSplits: return "Unlimited"
        }
    }

    // Max # of hands a single seat can hold
    var maxHands: Int {
        switch self {
        case .fourHandMax: return 4
        case .noReSplits: return 2
        case .infiniteReSplits: return Int.max
        }
    }

    var limitDescription: String {
        switch self {
        case .fourHandMax: return "You can split up to four hands."
        case .noReSplits: return "Re-splitting isn't allowed at this table."
        case .infiniteReSplits: return "There's no split limit."
        }
    }
}

struct TableRules: Equatable {
    var npcCount: Int
    var deckCount: Int
    var shuffleMethod: ShuffleMethod
    var penetrationRange: ClosedRange<Int>
    var shuffleMinutesRange: ClosedRange<Int>
    var dealerStandsOnSoft17: Bool
    var blackjackPaysSixToFive: Bool
    var canDoubleAfterSplit: Bool
    var canDoubleAfterHit: Bool
    var canReDouble: Bool
    var canReSplitAces: Bool
    var canEarlySurrender: Bool
    var canLateSurrender: Bool
    var enforceSameRankSplits: Bool
    var doubleDownRule: DoubleDownRule
    var reSplitRule: ReSplitRule
    var blackjackPayout: Double { blackjackPaysSixToFive ? 1.2 : 1.5 }

    static let standard = TableRules(
        npcCount: 0,
        deckCount: 6,
        shuffleMethod: .penetrationRange,
        penetrationRange: 65...80,
        shuffleMinutesRange: 30...45,
        dealerStandsOnSoft17: true,
        blackjackPaysSixToFive: false,
        canDoubleAfterSplit: true,
        canDoubleAfterHit: false,
        canReDouble: false,
        canReSplitAces: false,
        canEarlySurrender: false,
        canLateSurrender: true,
        enforceSameRankSplits: false,
        doubleDownRule: .anyHand,
        reSplitRule: .fourHandMax
    )
}

extension TableRules {
    init(settings: GameSettings) {
        let npcs = settings.npcCount.clamped(to: AppConfig.npcRange)
        let decks = settings.deckCount.clamped(to: AppConfig.deckRange(forNPCCount: npcs))
        let penLow = settings.penetrationMinPercent.clamped(to: AppConfig.penetrationBounds)
        let penHigh = settings.penetrationMaxPercent.clamped(to: AppConfig.penetrationBounds)
        let minLow = settings.shuffleMinMinutes.clamped(to: AppConfig.minuteBounds)
        let minHigh = settings.shuffleMaxMinutes.clamped(to: AppConfig.minuteBounds)

        self.init(
            npcCount: npcs,
            deckCount: decks,
            shuffleMethod: settings.shuffleMethod,
            penetrationRange: min(penLow, penHigh)...max(penLow, penHigh),
            shuffleMinutesRange: min(minLow, minHigh)...max(minLow, minHigh),
            dealerStandsOnSoft17: settings.dealerStandSoftSeventeen,
            blackjackPaysSixToFive: settings.payoutSixFiveNotThreeTwo,
            canDoubleAfterSplit: settings.canDoubleAfterSplit,
            canDoubleAfterHit: settings.canDoubleAfterHit,
            canReDouble: settings.canReDouble,
            canReSplitAces: settings.canReSplitAces,
            canEarlySurrender: settings.canEarlySurrender,
            canLateSurrender: settings.canLateSurrender,
            enforceSameRankSplits: settings.enforceSameRankSplits,
            doubleDownRule: settings.allowableDoubleDownHands,
            reSplitRule: settings.reSplitRule
        )
    }
}
