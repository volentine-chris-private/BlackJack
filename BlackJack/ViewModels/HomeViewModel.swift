//
//  HomeViewModel.swift
//  BlackJack
//
//  Created by Chris Volentine on 11/2/26.
//
import Foundation
import Observation

@Observable
@MainActor
final class HomeViewModel {
    private let services: AppServices

    private(set) var profile: UserProfile?
    private(set) var hasLoaded = false

    var isShowingProfile = false
    var isShowingBuyIn = false
    var isShowingSettings = false
    var activeSession: GameSessionConfig?

    @ObservationIgnored private var pendingSession: GameSessionConfig?
    @ObservationIgnored private var pendingDataReset = false
    @ObservationIgnored private var didRunLaunchChecks = false

    init(services: AppServices) {
        self.services = services
        reload()
    }

    // MARK: Display

    var needsOnboarding: Bool { hasLoaded && profile == nil }

    var welcomeText: String {
        guard let name = profile?.name, !name.isEmpty else { return "Welcome!" }
        return "Welcome, \(name)!"
    }

    var fundsText: String { CurrencyFormatter.string(profile?.totalFunds ?? 0) }

    // MARK: Loading

    func reload() {
        profile = services.dataStore.fetchProfile()
        hasLoaded = true
    }

    func performLaunchChecks() {
        guard !didRunLaunchChecks else { return }
        didRunLaunchChecks = true

        if case .inMemoryFallback(let reason) = services.storageMode {
            services.errorCenter.report(AppError.persistence(.runningInMemory(reason: reason)), context: "Launch")
        }
        if let profile, let forfeited = services.ledger.recoverAbandonedWager(for: profile) {
            services.errorCenter.report(AppError.funds(.abandonedWagerForfeited(amount: forfeited)), context: "Launch")
        }
    }

    // MARK: Play

    func playTapped() {
        //FOR-DEV-TEST:  DATA FOR CHART VISUALIZATION - Upon app launch, tap the play btn on the homescreen to populate chart data, then go to user profile view
        // let prfl = services.dataStore.fetchProfile()
        // let ldgr = services.ledger
        // do { try ldgr.testDayRecord(for: prfl!) } catch { }
        //COMMENT-OUT START
        guard let profile else {
            services.errorCenter.report(AppError.persistence(.profileMissing), context: "HomeViewModel.playTapped")
            return
        }
        guard profile.totalFunds >= AppConfig.tableMinimumBet else {
            services.errorCenter.report(
                AppError.funds(.insufficientFundsToPlay(minimum: AppConfig.tableMinimumBet)),
                context: "HomeViewModel.playTapped",
                recovery: RecoveryOption(title: "Add Funds") { [weak self] in
                    self?.isShowingProfile = true
                }
            )
            return
        }
        isShowingBuyIn = true
        //COMMENT-OUT END
    }

    var availableFunds: Double { profile?.totalFunds ?? 0 }

    func confirmBuyIn(_ amount: Double) {
        switch InputValidator.validateBuyIn(amount, available: availableFunds) {
        case .success(let value):
            let settings = services.dataStore.fetchOrCreateSettings()
            pendingSession = GameSessionConfig(buyIn: value, rules: TableRules(settings: settings))
            isShowingBuyIn = false
        case .failure(let error):
            services.errorCenter.report(error, context: "HomeViewModel.confirmBuyIn")
        }
    }

    func buyInSheetDismissed() {
        guard let session = pendingSession else { return }
        pendingSession = nil
        activeSession = session
    }

    func sessionEnded() {
        activeSession = nil
        reload()
    }

    // MARK: Profile / reset

    func requestDataReset() {
        pendingDataReset = true
        isShowingProfile = false
    }

    func profileSheetDismissed() {
        guard pendingDataReset else {
            reload()
            return
        }
        pendingDataReset = false
        profile = nil /// Drop every reference to the profile before it's deleted
        do {
            try services.dataStore.resetAllData()
            let decks = TableRules.standard.deckCount
            services.countCalculator.reset(totalCards: decks * Shoe.cardsPerDeck, deckCount: decks)
            services.countCalculator.persist()
        } catch {
            services.errorCenter.report(error, context: "HomeViewModel.reset")
        }
        reload()
    }
}
