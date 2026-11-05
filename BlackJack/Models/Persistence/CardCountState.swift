//
//  CardCountState.swift
//  BlackJack
//
//  Created by Chris Volentine on 11/2/26.
//

import Foundation
import SwiftData

@Model
final class CardCountState {
    var runningCount: Int = 0
    var cardsSeen: Int = 0
    var totalCards: Int = 312
    var deckCount: Int = 6
    var acesSeen: Int = 0
    var tensSeen: Int = 0
    var shoesTracked: Int = 0
    var shoeStartedAt: Date = Date()
    var lastUpdated: Date = Date()

    init() {}
}
