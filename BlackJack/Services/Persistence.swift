//
//  Persistence.swift
//  BlackJack
//
//  Created by Chris Volentine on 11/2/26.
//
import Foundation
import SwiftData
import OSLog

enum StorageMode: Equatable {
    case persistent
    case inMemoryFallback(reason: String)
}

/// Builds the SwiftData container. If the on-disk store can't be opened (corruption,
/// failed migration, full disk) the app falls back to an in-memory store and shows
/// a warning instead of crashing
enum PersistenceController {
    static let schema = Schema([
        UserProfile.self,
        GameSettings.self,
        DailyFundsRecord.self,
        CardCountState.self
    ])

    @MainActor
    static func makeContainer(inMemory: Bool = false) -> (container: ModelContainer, mode: StorageMode) {
        if !inMemory {
            do {
                let configuration = ModelConfiguration("Blackjack", schema: schema, isStoredInMemoryOnly: false)
                let container = try ModelContainer(for: schema, configurations: [configuration])
                return (container, .persistent)
            } catch {
                AppLogger.persistence.critical("Persistent store failed to open: \(error.localizedDescription, privacy: .public)")
                return makeInMemoryContainer(reason: error.localizedDescription)
            }
        }
        return makeInMemoryContainer(reason: "Requested in-memory store")
    }

    @MainActor
    private static func makeInMemoryContainer(reason: String) -> (container: ModelContainer, mode: StorageMode) {
        do {
            let configuration = ModelConfiguration("BlackjackMemory", schema: schema, isStoredInMemoryOnly: true)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let mode: StorageMode = reason == "Requested in-memory store" ? .persistent : .inMemoryFallback(reason: reason)
            return (container, mode)
        } catch {
            // No store at all, can't recover
            fatalError("In-memory SwiftData container failed: \(error)")
        }
    }
}

@MainActor
final class DataStore {
    let context: ModelContext
    private let errorCenter: ErrorCenter

    init(context: ModelContext, errorCenter: ErrorCenter) {
        self.context = context
        self.errorCenter = errorCenter
    }

    // MARK: Profile

    func fetchProfile() -> UserProfile? {
        do {
            let descriptor = FetchDescriptor<UserProfile>(sortBy: [SortDescriptor(\.createdAt, order: .forward)])
            let profiles = try context.fetch(descriptor)
            guard let primary = profiles.first else { return nil }

            if profiles.count > 1 {
                profiles.dropFirst().forEach { context.delete($0) }
                errorCenter.report(
                    AppError.persistence(.duplicateRecords(entity: "player profile", count: profiles.count)),
                    context: "DataStore.fetchProfile"
                )
                saveQuietly("dedupe profiles")
            }

            let repaired = primary.repairIfNeeded()
            if !repaired.isEmpty {
                errorCenter.report(
                    AppError.persistence(.repairedValues(entity: "profile", fields: repaired)),
                    context: "DataStore.fetchProfile"
                )
                saveQuietly("repair profile")
            }
            return primary
        } catch {
            errorCenter.report(
                AppError.persistence(.fetchFailed(entity: "your profile", reason: error.localizedDescription)),
                context: "DataStore.fetchProfile"
            )
            return nil
        }
    }

    func createProfile(name: String) throws -> UserProfile {
        if let existing = fetchProfile() {
            // Shouldn't happen (onboarding only shows with no profile) - reuse, not duplicate
            existing.name = name
            try save("rename existing profile")
            return existing
        }
        let profile = UserProfile(name: name)
        context.insert(profile)
        try save("create profile")
        return profile
    }

    // MARK: Settings

    func fetchOrCreateSettings() -> GameSettings {
        do {
            let all = try context.fetch(FetchDescriptor<GameSettings>())
            if let settings = all.first {
                if all.count > 1 {
                    all.dropFirst().forEach { context.delete($0) }
                    errorCenter.report(
                        AppError.persistence(.duplicateRecords(entity: "settings", count: all.count)),
                        context: "DataStore.fetchOrCreateSettings"
                    )
                }
                let repaired = settings.sanitize()
                if !repaired.isEmpty {
                    errorCenter.report(AppError.settings(.valuesRepaired(fields: repaired)), context: "DataStore.fetchOrCreateSettings")
                }
                saveQuietly("load settings")
                return settings
            }
        } catch {
            errorCenter.report(
                AppError.persistence(.fetchFailed(entity: "table rules", reason: error.localizedDescription)),
                context: "DataStore.fetchOrCreateSettings"
            )
        }
        let settings = GameSettings()
        context.insert(settings)
        saveQuietly("create settings")
        return settings
    }

    // MARK: Saving

    func save(_ reason: String) throws {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            AppLogger.persistence.error("Save failed (\(reason, privacy: .public)): \(error.localizedDescription, privacy: .public)")
            throw AppError.persistence(.saveFailed(reason: error.localizedDescription))
        }
    }

    /// reports failures instead of throwing. Returns `true` on success
    @discardableResult
    func saveQuietly(_ reason: String) -> Bool {
        do {
            try save(reason)
            return true
        } catch {
            errorCenter.report(error, context: "DataStore.save(\(reason))")
            return false
        }
    }

    // MARK: Reset

    /// Erases the profile and funds history, and restores default rules.
    /// All refs to the deleted profile need to be dropped BEFORE!! this func is called
    func resetAllData() throws {
        do {
            try context.delete(model: UserProfile.self)
            try context.delete(model: DailyFundsRecord.self)
        } catch {
            throw AppError.persistence(.deleteFailed(reason: error.localizedDescription))
        }
        fetchOrCreateSettings().resetToDefaults()
        try save("reset all data")
    }
}
