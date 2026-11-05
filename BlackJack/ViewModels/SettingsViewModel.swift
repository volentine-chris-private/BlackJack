//
//  SettingsViewModel.swift
//  BlackJack
//
//  Created by Chris Volentine on 11/2/26.
//
import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class SettingsViewModel {
    private let services: AppServices
    let settings: GameSettings

    private(set) var deckAdjustmentNote: String?
    
    private var npcCountUpdated: Bool

    init(services: AppServices) {
        self.services = services
        self.settings = services.dataStore.fetchOrCreateSettings()
        self.npcCountUpdated = false
    }

    // MARK: Table size

    var npcCount: Int {
        get { settings.npcCount }
        set {
            let clamped = newValue.clamped(to: AppConfig.npcRange)
            settings.npcCount = clamped
            npcCountUpdated = true
            let allowed = AppConfig.deckRange(forNPCCount: clamped)
            if !allowed.contains(settings.deckCount) {
                let previous = settings.deckCount
                settings.deckCount = settings.deckCount.clamped(to: allowed)
                deckAdjustmentNote = "Decks raised from \(previous) to \(settings.deckCount) for \(clamped + 1) players."
                services.errorCenter.report(
                    AppError.settings(.deckCountAdjusted(from: previous, to: settings.deckCount)),
                    context: "SettingsViewModel.npcCount"
                )
            } else {
                deckAdjustmentNote = nil
            }
            persist()
        }
    }

    var deckRange: ClosedRange<Int> { AppConfig.deckRange(forNPCCount: settings.npcCount) }

    var deckCount: Int {
        get { settings.deckCount }
        set {
            settings.deckCount = newValue.clamped(to: deckRange)
            deckAdjustmentNote = nil
            persist()
        }
    }

    var deckRangeFooter: String {
        let range = deckRange
        let players = settings.npcCount + 1
        if range.lowerBound == AppConfig.absoluteDeckRange.lowerBound {
            return "With \(players) total player\(players == 1 ? "" : "s") you can use 1-8 decks."
        }
        return "With \(players) total players the shoe needs at least \(range.lowerBound) decks so it doesn't run dry mid-round."
    }

    // MARK: Shuffling

    var shuffleMethod: ShuffleMethod {
        get { settings.shuffleMethod }
        set {
            settings.shuffleMethod = newValue
            persist()
        }
    }

    var penetrationMin: Int {
        get { settings.penetrationMinPercent }
        set {
            settings.penetrationMinPercent = newValue.clamped(to: AppConfig.penetrationBounds)
            if settings.penetrationMaxPercent < settings.penetrationMinPercent {
                settings.penetrationMaxPercent = settings.penetrationMinPercent
            }
            persist()
        }
    }

    var penetrationMax: Int {
        get { settings.penetrationMaxPercent }
        set {
            settings.penetrationMaxPercent = newValue.clamped(to: AppConfig.penetrationBounds)
            if settings.penetrationMinPercent > settings.penetrationMaxPercent {
                settings.penetrationMinPercent = settings.penetrationMaxPercent
            }
            persist()
        }
    }

    var minutesMin: Int {
        get { settings.shuffleMinMinutes }
        set {
            settings.shuffleMinMinutes = newValue.clamped(to: AppConfig.minuteBounds)
            if settings.shuffleMaxMinutes < settings.shuffleMinMinutes {
                settings.shuffleMaxMinutes = settings.shuffleMinMinutes
            }
            persist()
        }
    }

    var minutesMax: Int {
        get { settings.shuffleMaxMinutes }
        set {
            settings.shuffleMaxMinutes = newValue.clamped(to: AppConfig.minuteBounds)
            if settings.shuffleMinMinutes > settings.shuffleMaxMinutes {
                settings.shuffleMinMinutes = settings.shuffleMaxMinutes
            }
            persist()
        }
    }

    // MARK: Pickers

    var doubleDownRule: DoubleDownRule {
        get { settings.allowableDoubleDownHands }
        set {
            settings.allowableDoubleDownHands = newValue
            persist()
        }
    }

    var reSplitRule: ReSplitRule {
        get { settings.reSplitRule }
        set {
            settings.reSplitRule = newValue
            persist()
        }
    }

    // MARK: Toggles

    /// Binding to any Bool rule that saves on change
    func toggle(_ keyPath: ReferenceWritableKeyPath<GameSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { self.settings[keyPath: keyPath] },
            set: { newValue in
                self.settings[keyPath: keyPath] = newValue
                self.persist()
            }
        )
    }

    /// Nonblocking notes about rule combinations that dont do anything
    var ruleNotes: [String] {
        var notes: [String] = []
        if settings.canReSplitAces && settings.reSplitRule == .noReSplits {
            notes.append("Re-splitting aces has no effect while re-splits are turned off.")
        }
        if settings.canEarlySurrender && settings.canLateSurrender {
            notes.append("With both surrender types on, early surrender is offered before the dealer peeks and late surrender after.")
        }
        if settings.canDoubleAfterHit && settings.allowableDoubleDownHands == .hardNineToEleven {
            notes.append("Doubling after a hit still requires a hard 9-11.")
        }
        if settings.shuffleMethod == .continuous {
            notes.append("With a continuous shuffler the true count resets every hand, so counting NPCs bet flat.")
        }
        return notes
    }

    // MARK: Persistence

    func resetToDefaults() {
        settings.resetToDefaults()
        deckAdjustmentNote = nil
        persist()
    }
    
    func tearDown() {
        if (npcCountUpdated) {
            NameGenerationService.reload()
        }
        persist()
    }

    func persist() {
        settings.updatedAt = Date()
        services.dataStore.saveQuietly("settings")
    }
}
