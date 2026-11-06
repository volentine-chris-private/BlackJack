//
//  FundsLedger.swift
//  BlackJack
//
//  Created by Chris Volentine on 11/2/26.
//
import Foundation
import SwiftData
import OSLog

/// The only place that changes `UserProfile.totalFunds`. Every change also updates the
/// matching `DailyFundsRecord` so the 30-day chart stays accurate
@MainActor
final class FundsLedger {
    private let context: ModelContext
    private let errorCenter: ErrorCenter

    init(context: ModelContext, errorCenter: ErrorCenter) {
        self.context = context
        self.errorCenter = errorCenter
    }

    // MARK: Deposits

    func deposit(_ amount: Double, to profile: UserProfile) throws {
        let validated = try InputValidator.validateDeposit(amount, currentFunds: profile.totalFunds).get()
        let record = try dayRecord(for: profile)
        profile.totalFunds = Money.rounded(profile.totalFunds + validated)
        profile.lifetimeDeposits = Money.rounded(profile.lifetimeDeposits + validated)
        record.deposits = Money.rounded(record.deposits + validated)
        record.closingBalance = profile.totalFunds
        try save("deposit")
        AppLogger.funds.info("Deposited \(validated, privacy: .public)")
    }

    // MARK: Hand results

    /// Applies the net result of a finished/forfeited hand and clears the pending wager.
    /// - Returns: the amount actually applied (may be clamped to prevent a negative balance)
    @discardableResult
    func applyHandResult(_ delta: Double, to profile: UserProfile, countsAsHand: Bool = true) -> Double {
        guard delta.isFinite else {
            errorCenter.report(AppError.funds(.invalidAmount), context: "FundsLedger.applyHandResult")
            return 0
        }

        var applied = Money.rounded(delta)
        let projected = profile.totalFunds + applied
        if projected < 0 {
            errorCenter.report(AppError.funds(.negativeBalancePrevented(attempted: projected)), context: "FundsLedger.applyHandResult")
            applied = -profile.totalFunds
        }

        do {
            let record = try dayRecord(for: profile)
            profile.totalFunds = Money.rounded(profile.totalFunds + applied)
            record.gameNet = Money.rounded(record.gameNet + applied)
            record.closingBalance = profile.totalFunds
            if countsAsHand { record.handsPlayed += 1 }
        } catch {
            // apply the funds change even if the chart row failed
            profile.totalFunds = Money.rounded(profile.totalFunds + applied)
            errorCenter.report(error, context: "FundsLedger.applyHandResult")
        }

        if countsAsHand { profile.handsPlayed += 1 }
        profile.pendingWager = 0
        saveQuietly("hand result")
        AppLogger.funds.info("Hand result applied: \(applied, privacy: .public)")
        return applied
    }

    func setPendingWager(_ amount: Double, on profile: UserProfile) {
        let clean = amount.isFinite ? max(0, Money.rounded(amount)) : 0
        guard profile.pendingWager != clean else { return }
        profile.pendingWager = min(clean, profile.totalFunds)
        saveQuietly("pending wager")
    }

    /// If the app was terminated mid-hand, forfeits the wager that was in play.
    /// - Returns: the forfeited amount, or `nil` if there was nothing pending
    func recoverAbandonedWager(for profile: UserProfile) -> Double? {
        let pending = profile.pendingWager
        guard pending > 0 else { return nil }
        let applied = applyHandResult(-pending, to: profile)
        return abs(applied)
    }

    // MARK: History

    func allRecords() throws -> [DailyFundsRecord] {
        do {
            let descriptor = FetchDescriptor<DailyFundsRecord>(sortBy: [SortDescriptor(\.dayStart, order: .forward)])
            return try context.fetch(descriptor)
        } catch {
            throw AppError.persistence(.fetchFailed(entity: "funds history", reason: error.localizedDescription))
        }
    }

     //FOR-DEV-TEST:  DATA FOR CHART VISUALIZATION:
     // func testDayRecord(for profile: UserProfile) throws {
     //     let testData: [Double] = [900, 800, 620, 730, 600, 480, 320, 290, 260, 320, 300,270, 240, 250, 270,
     //                               250, 230, 200, 260, 240, 250, 240, 220, 210, 200, 190, 150, 170, 80]
     //     for indx in 0...(testData.count - 1) {
     //         profile.totalFunds = testData[indx]
     //         let day = Calendar.current.date(byAdding: .day, value: -(indx + 1), to: Date())!
     //         let dayStart = Calendar.current.startOfDay(for: day)
     //         let descriptor = FetchDescriptor<DailyFundsRecord>(predicate: #Predicate { record in
     //             record.dayStart == dayStart
     //         })
     //         do {
     //             if let existing = try context.fetch(descriptor).first { }
     //         } catch {
     //             throw AppError.persistence(.fetchFailed(entity: "today's funds record", reason: error.localizedDescription))
     //         }
     //         let record = DailyFundsRecord(dayStart: dayStart, openingBalance: profile.totalFunds)
     //         context.insert(record)
     //     }
     // }

    // MARK: Private

    private func dayRecord(for profile: UserProfile, now: Date = Date()) throws -> DailyFundsRecord {
        let day = Calendar.current.startOfDay(for: now)
        let descriptor = FetchDescriptor<DailyFundsRecord>(predicate: #Predicate { record in
            record.dayStart == day
        })
        do {
            if let existing = try context.fetch(descriptor).first {
                return existing
            }
        } catch {
            throw AppError.persistence(.fetchFailed(entity: "today's funds record", reason: error.localizedDescription))
        }
        let record = DailyFundsRecord(dayStart: day, openingBalance: profile.totalFunds)
        context.insert(record)
        return record
    }

    private func save(_ reason: String) throws {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            throw AppError.persistence(.saveFailed(reason: error.localizedDescription))
        }
    }

    private func saveQuietly(_ reason: String) {
        do {
            try save(reason)
        } catch {
            errorCenter.report(error, context: "FundsLedger.save(\(reason))")
        }
    }
}
