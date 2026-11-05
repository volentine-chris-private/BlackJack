//
//  AppConfig.swift
//  BlackJack
//
//  Created by Chris Volentine on 11/2/26.
//
import Foundation

enum AppConfig {
    static let bundleIdBackup = "com.chrisvolentine.BlackJack"

    static let npcRange = 0...4
    
    static let absoluteDeckRange = 1...8
    
    static let penetrationBounds = 40...95
    
    static let minuteBounds = 5...180
    
    static let minuteStep = 5

    static let depositBalanceCap: Double = 1_000
    
    static let tableMinimumBet: Double = 5

    static let hotDeckTrueCount: Double = 2.5
    
    static let hotDeckMinimumCardsSeen = 20

    static let maxDoublesPerHand = 3
    
    static let nameMaxLength = 20      /// User profile config

    static let fundsChartDayCount = 30 /// User profile config

    static func deckRange(forNPCCount count: Int) -> ClosedRange<Int> {
        switch count {
        case ...1: return 1...8   // 1-2 players: single deck is fine
        case 2...3: return 2...8  // 3-4 players: at least a double deck
        default: return 4...8     // full table: 4+ decks
        }
    }
}

nonisolated enum LaunchOptions {
    static let arguments = ProcessInfo.processInfo.arguments

    /// in-memory store, stubbed deck, no animations
    static var isUITesting: Bool { arguments.contains("-UITesting") }

    static var usesInMemoryStore: Bool { isUITesting }

    static var usesStubDeck: Bool { isUITesting }

    static var stubDeckFails: Bool { arguments.contains("-UITestDeckFailure") }

    /// multiplier for every delay at the table
    static var timingScale: Double { arguments.contains("-UITestFastTiming") ? 0.1 : 1 }

    /// start with an existing profile and funds
    static var seedProfile: (name: String, funds: Double)? {
        guard let index = arguments.firstIndex(of: "-UITestSeedProfile"),
              arguments.indices.contains(index + 2),
              let funds = Double(arguments[index + 2]) else { return nil }
        return (arguments[index + 1], funds)
    }
}
