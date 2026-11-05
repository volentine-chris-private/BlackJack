//
//  UserProfile.swift
//  BlackJack
//
//  Created by Chris Volentine on 11/2/26.
//

import Foundation
import SwiftData

@Model
final class UserProfile {
    var name: String = ""
    var totalFunds: Double = 0
    var pendingWager: Double = 0
    var lifetimeDeposits: Double = 0
    var handsPlayed: Int = 0
    var createdAt: Date = Date()

    init(name: String) {
        self.name = name
        self.totalFunds = 0
        self.pendingWager = 0
        self.lifetimeDeposits = 0
        self.handsPlayed = 0
        self.createdAt = Date()
    }

    var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { part -> String? in
            guard let first = part.first else { return nil }
            return String(first)
        }.joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }

    @discardableResult
    func repairIfNeeded() -> [String] {
        var repaired: [String] = []
        if !totalFunds.isFinite || totalFunds < 0 {
            totalFunds = 0
            repaired.append("totalFunds")
        }
        if !pendingWager.isFinite || pendingWager < 0 {
            pendingWager = 0
            repaired.append("pendingWager")
        }
        if pendingWager > totalFunds {
            pendingWager = totalFunds
            repaired.append("pendingWager")
        }
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            name = "Player"
            repaired.append("name")
        }
        if handsPlayed < 0 {
            handsPlayed = 0
            repaired.append("handsPlayed")
        }
        return repaired
    }
}
