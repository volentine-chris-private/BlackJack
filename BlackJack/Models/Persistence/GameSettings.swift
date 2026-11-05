//
//  GameSettings.swift
//  BlackJack
//
//  Created by Chris Volentine on 11/2/26.
//

import Foundation
import SwiftData

@Model
final class GameSettings {
    // Table
    var npcCount: Int = 0
    var deckCount: Int = 6

    // Shuffling
    var shuffleMethodRaw: String = "penetrationRange"
    var penetrationMinPercent: Int = 65
    var penetrationMaxPercent: Int = 80
    var shuffleMinMinutes: Int = 30
    var shuffleMaxMinutes: Int = 45

    // Rule variants
    var dealerStandSoftSeventeen: Bool = true
    var payoutSixFiveNotThreeTwo: Bool = false
    var canDoubleAfterSplit: Bool = true
    var canDoubleAfterHit: Bool = false
    var canReDouble: Bool = false
    var canReSplitAces: Bool = false
    var canEarlySurrender: Bool = false
    var canLateSurrender: Bool = true
    var enforceSameRankSplits: Bool = false
    var allowableDoubleDownHandsRaw: String = "anyHand"
    var reSplitRuleRaw: String = "fourHandMax"

    var updatedAt: Date = Date()

    init() {}

    var shuffleMethod: ShuffleMethod {
        get { ShuffleMethod(rawValue: shuffleMethodRaw) ?? .penetrationRange }
        set { shuffleMethodRaw = newValue.rawValue }
    }

    var allowableDoubleDownHands: DoubleDownRule {
        get { DoubleDownRule(rawValue: allowableDoubleDownHandsRaw) ?? .anyHand }
        set { allowableDoubleDownHandsRaw = newValue.rawValue }
    }

    var reSplitRule: ReSplitRule {
        get { ReSplitRule(rawValue: reSplitRuleRaw) ?? .fourHandMax }
        set { reSplitRuleRaw = newValue.rawValue }
    }

    /// Clamps every value into its allowed range
    @discardableResult
    func sanitize() -> [String] {
        var repaired: [String] = []

        if !AppConfig.npcRange.contains(npcCount) {
            npcCount = npcCount.clamped(to: AppConfig.npcRange)
            repaired.append("number of NPCs")
        }
        let deckRange = AppConfig.deckRange(forNPCCount: npcCount)
        if !deckRange.contains(deckCount) {
            deckCount = deckCount.clamped(to: deckRange)
            repaired.append("number of decks")
        }
        if ShuffleMethod(rawValue: shuffleMethodRaw) == nil {
            shuffleMethodRaw = ShuffleMethod.penetrationRange.rawValue
            repaired.append("shuffle rate")
        }
        if !AppConfig.penetrationBounds.contains(penetrationMinPercent)
            || !AppConfig.penetrationBounds.contains(penetrationMaxPercent)
            || penetrationMinPercent > penetrationMaxPercent {
            penetrationMinPercent = 65
            penetrationMaxPercent = 80
            repaired.append("shuffle percentage")
        }
        if !AppConfig.minuteBounds.contains(shuffleMinMinutes)
            || !AppConfig.minuteBounds.contains(shuffleMaxMinutes)
            || shuffleMinMinutes > shuffleMaxMinutes {
            shuffleMinMinutes = 30
            shuffleMaxMinutes = 45
            repaired.append("shuffle minutes")
        }
        if DoubleDownRule(rawValue: allowableDoubleDownHandsRaw) == nil {
            allowableDoubleDownHandsRaw = DoubleDownRule.anyHand.rawValue
            repaired.append("allowable double-down hands")
        }
        if ReSplitRule(rawValue: reSplitRuleRaw) == nil {
            reSplitRuleRaw = ReSplitRule.fourHandMax.rawValue
            repaired.append("re-split rule")
        }
        if !repaired.isEmpty { updatedAt = Date() }
        return repaired
    }

    func resetToDefaults() {
        let defaults = TableRules.standard
        npcCount = defaults.npcCount
        deckCount = defaults.deckCount
        shuffleMethodRaw = defaults.shuffleMethod.rawValue
        penetrationMinPercent = defaults.penetrationRange.lowerBound
        penetrationMaxPercent = defaults.penetrationRange.upperBound
        shuffleMinMinutes = defaults.shuffleMinutesRange.lowerBound
        shuffleMaxMinutes = defaults.shuffleMinutesRange.upperBound
        dealerStandSoftSeventeen = defaults.dealerStandsOnSoft17
        payoutSixFiveNotThreeTwo = defaults.blackjackPaysSixToFive
        canDoubleAfterSplit = defaults.canDoubleAfterSplit
        canDoubleAfterHit = defaults.canDoubleAfterHit
        canReDouble = defaults.canReDouble
        canReSplitAces = defaults.canReSplitAces
        canEarlySurrender = defaults.canEarlySurrender
        canLateSurrender = defaults.canLateSurrender
        enforceSameRankSplits = defaults.enforceSameRankSplits
        allowableDoubleDownHandsRaw = defaults.doubleDownRule.rawValue
        reSplitRuleRaw = defaults.reSplitRule.rawValue
        updatedAt = Date()
    }
}
