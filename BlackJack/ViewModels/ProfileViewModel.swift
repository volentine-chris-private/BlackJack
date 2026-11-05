//
//  ProfileViewModel.swift
//  BlackJack
//
//  Created by Chris Volentine on 11/2/26.
//
import Foundation
import Observation

struct FundsChartPoint: Identifiable, Equatable {
    var id: Date { day }
    let day: Date
    let change: Double
    let gameNet: Double
    let deposits: Double
    let closingBalance: Double
    let handsPlayed: Int
}

@Observable
@MainActor
final class ProfileViewModel {
    enum ChartMode: String, CaseIterable, Identifiable {
        case dailyChange = "Daily Change"
        case balance = "Balance"
        var id: String { rawValue }
    }

    static let chartDays = AppConfig.fundsChartDayCount

    private let services: AppServices
    let profile: UserProfile

    var chartMode: ChartMode = .dailyChange
    private(set) var includesDepositsStorage = true
    var includeDeposits: Bool {
        get { includesDepositsStorage }
        set {
            includesDepositsStorage = newValue
            rebuildPoints()
        }
    }
    private(set) var points: [FundsChartPoint] = []

    // Deposit sheet
    var isShowingDeposit = false
    var depositText = ""
    private(set) var depositError: String?

    // Rename
    var isEditingName = false
    var nameDraft = ""

    // Reset
    var isConfirmingReset = false

    @ObservationIgnored private var records: [DailyFundsRecord] = []

    init(services: AppServices, profile: UserProfile) {
        self.services = services
        self.profile = profile
        loadHistory()
    }

    // MARK: Summary

    var totalFundsText: String { CurrencyFormatter.string(profile.totalFunds) }

    var thirtyDayGameNet: Double { points.reduce(0) { $0 + $1.gameNet } }
    var thirtyDayHands: Int { points.reduce(0) { $0 + $1.handsPlayed } }
    var bestDay: FundsChartPoint? { points.filter { $0.gameNet > 0 }.max { $0.gameNet < $1.gameNet } }
    var worstDay: FundsChartPoint? { points.filter { $0.gameNet < 0 }.min { $0.gameNet < $1.gameNet } }
    var hasActivity: Bool { points.contains { $0.gameNet != 0 || $0.deposits != 0 } }

    // MARK: Chart data

    func loadHistory() {
        do {
            records = try services.ledger.allRecords()
        } catch {
            records = []
            services.errorCenter.report(error, context: "ProfileViewModel.loadHistory")
        }
        rebuildPoints()
    }

    private func rebuildPoints() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -(Self.chartDays - 1), to: today) else {
            points = []
            return
        }

        var byDay: [Date: DailyFundsRecord] = [:]
        for record in records {
            byDay[calendar.startOfDay(for: record.dayStart)] = record
        }

        /// Balance carried into the window from the most recent earlier day
        var runningBalance = records.last(where: { calendar.startOfDay(for: $0.dayStart) < start })?.closingBalance ?? 0

        var result: [FundsChartPoint] = []
        result.reserveCapacity(Self.chartDays)
        for offset in 0..<Self.chartDays {
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            let day = calendar.startOfDay(for: date)
            if let record = byDay[day] {
                runningBalance = record.closingBalance
                result.append(FundsChartPoint(
                    day: day,
                    //FOR-DEV-TEST:  DATA FOR CHART VISUALIZATION:
                    // change: [50,100,150,200,250,300,350,400,450,500,550,600,650,700,750,800,850,900,950,1000,
                    //          -50,-100,-150,-200,-250,-300,-350,-400,-450,-500,-550,-600,-650,-700,-750].randomElement()!,
                    //COMMENT-OUT START
                    change: Money.rounded(record.gameNet + (includeDeposits ? record.deposits : 0)),
                    //COMMENT-OUT END
                    gameNet: record.gameNet,
                    deposits: record.deposits,
                    closingBalance: record.closingBalance,
                    handsPlayed: record.handsPlayed
                ))
            } else {
                result.append(FundsChartPoint(
                    day: day,
                    change: 0,
                    gameNet: 0,
                    deposits: 0,
                    closingBalance: runningBalance,
                    handsPlayed: 0
                ))
            }
        }
        points = result
    }

    // MARK: Deposits

    var maximumDeposit: Double { InputValidator.maximumDeposit(currentFunds: profile.totalFunds) }
    var canDeposit: Bool { maximumDeposit >= 0.01 }
    var depositLimitText: String {
        if canDeposit {
            return "You can add up to \(CurrencyFormatter.string(maximumDeposit))."
        }
        return "Adding funds is available while your total is under \(CurrencyFormatter.string(AppConfig.depositBalanceCap))."
    }

    /// Quick pick amnts that fit under the cap and a Max amnt when it differs
    var quickDepositAmounts: [Double] {
        let limit = maximumDeposit
        var amounts = [1_000.0, 10_000, 100_000].filter { $0 < limit }
        if limit >= 0.01 { amounts.append(limit) }
        return amounts
    }

    var depositPreview: String? {
        guard case .success(let value) = InputValidator.parseAmount(depositText) else { return nil }
        if value > maximumDeposit {
            return "The most you can add is \(CurrencyFormatter.string(maximumDeposit))"
        }
        return "New total: \(CurrencyFormatter.string(profile.totalFunds + value))"
    }

    var depositPreviewIsWarning: Bool {
        guard case .success(let value) = InputValidator.parseAmount(depositText) else { return false }
        return value > maximumDeposit
    }

    func beginDeposit() {
        guard canDeposit else {
            services.errorCenter.report(
                AppError.validation(.depositsUnavailable(cap: AppConfig.depositBalanceCap)),
                context: "ProfileViewModel.beginDeposit"
            )
            return
        }
        depositText = ""
        depositError = nil
        isShowingDeposit = true
    }

    func depositChanged() { depositError = nil }

    var depositSliderValue: Double {
        get {
            guard case .success(let value) = InputValidator.parseAmount(depositText) else { return 0 }
            return value.clamped(to: 0...max(maximumDeposit, 0))
        }
        set {
            depositText = Money.fieldString(Money.sliderSnap(newValue, upperBound: maximumDeposit))
            depositError = nil
        }
    }

    func selectQuickDeposit(_ amount: Double) {
        depositText = Money.plainString(amount)
        depositError = nil
    }

    func submitDeposit() {
        let current = profile.totalFunds
        switch InputValidator.parseAmount(depositText).flatMap({ InputValidator.validateDeposit($0, currentFunds: current) }) {
        case .success(let amount):
            do {
                try services.ledger.deposit(amount, to: profile)
                isShowingDeposit = false
                loadHistory()
            } catch {
                depositError = AppError.wrap(error).message
                services.errorCenter.report(error, context: "ProfileViewModel.submitDeposit")
            }
        case .failure(let error):
            depositError = error.message
        }
    }

    // MARK: Rename

    func beginRename() {
        nameDraft = profile.name
        isEditingName = true
    }

    func saveName() {
        switch InputValidator.validateName(nameDraft) {
        case .success(let name):
            profile.name = name
            services.dataStore.saveQuietly("rename")
        case .failure(let error):
            services.errorCenter.report(error, context: "ProfileViewModel.saveName")
        }
    }
}
