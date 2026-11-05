//
//  BlackJackApp.swift
//  BlackJack
//
//  Created by Chris Volentine on 11/2/26.
//
import SwiftUI
import SwiftData
import UIKit

@main
@MainActor
struct BlackjackApp: App {
    @State private var services: AppServices

    init() {
        let result = PersistenceController.makeContainer(inMemory: LaunchOptions.usesInMemoryStore)
        let deckProvider: (any DeckProviding)? = LaunchOptions.usesStubDeck
            ? StubDeckProvider(failure: LaunchOptions.stubDeckFails ? .offline : nil)
            : nil
        let services = AppServices(container: result.container, storageMode: result.mode, deckProvider: deckProvider)

        if LaunchOptions.isUITesting {
            UIView.setAnimationsEnabled(false)
            if let seed = LaunchOptions.seedProfile,
               let profile = try? services.dataStore.createProfile(name: seed.name) {
                try? services.ledger.deposit(seed.funds, to: profile)
            }
        }
        _services = State(initialValue: services)
        
        NameGenerationService.load()
    }

    var body: some Scene {
        WindowGroup {
            MainContentView(services: services)
                .preferredColorScheme(.dark)
                .tint(AppTheme.copper)
        }
        .modelContainer(services.container)
    }
}
