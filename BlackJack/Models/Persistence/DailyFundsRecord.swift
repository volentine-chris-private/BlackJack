//
//  DailyFundsRecord.swift
//  BlackJack
//
//  Created by Chris Volentine on 11/2/26.
//

import Foundation
import SwiftData


@Model
final class DailyFundsRecord {
    @Attribute(.unique) var dayStart: Date
    var openingBalance: Double
    var closingBalance: Double
    var gameNet: Double  /// Net won/lost hands
    var deposits: Double /// Money deposited that day
    var handsPlayed: Int

    init(dayStart: Date, openingBalance: Double) {
        self.dayStart = dayStart
        self.openingBalance = openingBalance
        self.closingBalance = openingBalance
        self.gameNet = 0
        self.deposits = 0
        self.handsPlayed = 0
    }

    var totalChange: Double { gameNet + deposits }
}
