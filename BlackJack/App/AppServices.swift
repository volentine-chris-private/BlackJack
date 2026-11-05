//
//  AppServices.swift
//  BlackJack
//
//  Created by Chris Volentine on 11/2/26.
//
import Foundation
import SwiftData

@MainActor
final class AppServices {
    let container: ModelContainer
    let storageMode: StorageMode
    let errorCenter: ErrorCenter
    let dataStore: DataStore
    let ledger: FundsLedger
    let countCalculator: TrueCountCalculator
    let networkMonitor: NetworkMonitor
    let deckService: DeckOfCardsService
    let deckProvider: any DeckProviding

    init(container: ModelContainer, storageMode: StorageMode, deckProvider: (any DeckProviding)? = nil) {
        let center = ErrorCenter()
        let context = container.mainContext
        context.autosaveEnabled = true

        self.container = container
        self.storageMode = storageMode
        self.errorCenter = center
        self.dataStore = DataStore(context: context, errorCenter: center)
        self.ledger = FundsLedger(context: context, errorCenter: center)
        self.countCalculator = TrueCountCalculator(context: context, errorCenter: center)

        let monitor = NetworkMonitor()
        let service = DeckOfCardsService(monitor: monitor)
        self.networkMonitor = monitor
        self.deckService = service
        self.deckProvider = deckProvider ?? service
    }

    func persistAll(reason: String) {
        countCalculator.persist()
        dataStore.saveQuietly(reason)
    }

    /// In-memory services for SwiftUI previews (TODO)
    static func preview(withProfile: Bool = true) -> AppServices {
        let result = PersistenceController.makeContainer(inMemory: true)
        let services = AppServices(container: result.container, storageMode: result.mode, deckProvider: StubDeckProvider())
        if withProfile, let profile = try? services.dataStore.createProfile(name: "Chris") {
            try? services.ledger.deposit(25_000, to: profile)
        }
        return services
    }
}
