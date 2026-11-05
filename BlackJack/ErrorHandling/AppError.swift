//
//  AppError.swift
//  BlackJack
//
//  Created by Chris Volentine on 11/2/26.
//

import Foundation

enum ErrorSeverity: Int, Comparable {
    case info = 0 /// should only be logged
    case warning  /// banner alert
    case error    /// present modal popup
    case critical /// present modal popup

    static func < (lhs: ErrorSeverity, rhs: ErrorSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum AppError: Error, Equatable {
    case persistence(PersistenceIssue)
    case validation(ValidationIssue)
    case game(GameIssue)
    case settings(SettingsIssue)
    case funds(FundsIssue)
    case network(NetworkError)
    case unexpected(String)

    /// Convert any thrown error into an AppError
    static func wrap(_ error: Error) -> AppError {
        if let appError = error as? AppError { return appError }
        if let networkError = error as? NetworkError { return .network(networkError) }
        let nsError = error as NSError
        return .unexpected("\(nsError.domain) (\(nsError.code)): \(nsError.localizedDescription)")
    }

    var code: String {
        switch self {
        case .persistence(let issue): return "PER-\(issue.code)"
        case .validation(let issue): return "VAL-\(issue.code)"
        case .game(let issue): return "GAM-\(issue.code)"
        case .settings(let issue): return "SET-\(issue.code)"
        case .funds(let issue): return "FUN-\(issue.code)"
        case .network(let issue): return "NET-\(issue.code)"
        case .unexpected: return "UNX-000"
        }
    }

    var severity: ErrorSeverity {
        switch self {
        case .persistence(let issue): return issue.severity
        case .validation: return .warning
        case .game(let issue): return issue.severity
        case .settings(let issue): return issue.severity
        case .funds(let issue): return issue.severity
        case .network(let issue): return issue.severity
        case .unexpected: return .error
        }
    }

    var title: String {
        switch self {
        case .persistence: return "Storage Problem"
        case .validation: return "Check Your Entry"
        case .game(let issue): return issue.title
        case .settings: return "Table Rules"
        case .funds(let issue): return issue.title
        case .network: return "Connection Problem"
        case .unexpected: return "Something Went Wrong"
        }
    }

    var message: String {
        switch self {
        case .persistence(let issue): return issue.message
        case .validation(let issue): return issue.message
        case .game(let issue): return issue.message
        case .settings(let issue): return issue.message
        case .funds(let issue): return issue.message
        case .network(let issue): return issue.message
        case .unexpected(let detail): return "An unexpected error occurred. (\(detail))"
        }
    }

    var suggestion: String? {
        switch self {
        case .persistence(let issue): return issue.suggestion
        case .validation: return nil
        case .game(let issue): return issue.suggestion
        case .settings(let issue): return issue.suggestion
        case .funds(let issue): return issue.suggestion
        case .network(let issue): return issue.suggestion
        case .unexpected: return "Please try again. If the problem continues, restart the app."
        }
    }

    var fullMessage: String {
        guard let suggestion else { return message }
        return "\(message)\n\n\(suggestion)"
    }
}

extension AppError: LocalizedError {
    var errorDescription: String? { message }
    var recoverySuggestion: String? { suggestion }
}

// MARK: - Persistence

enum PersistenceIssue: Equatable {
    case runningInMemory(reason: String)
    case fetchFailed(entity: String, reason: String)
    case saveFailed(reason: String)
    case deleteFailed(reason: String)
    case duplicateRecords(entity: String, count: Int)
    case profileMissing
    case repairedValues(entity: String, fields: [String])

    var code: String {
        switch self {
        case .runningInMemory: return "001"
        case .fetchFailed: return "002"
        case .saveFailed: return "003"
        case .deleteFailed: return "004"
        case .duplicateRecords: return "005"
        case .profileMissing: return "006"
        case .repairedValues: return "007"
        }
    }

    var severity: ErrorSeverity {
        switch self {
        case .runningInMemory: return .critical
        case .fetchFailed, .saveFailed, .deleteFailed, .profileMissing: return .error
        case .duplicateRecords: return .info
        case .repairedValues: return .warning
        }
    }

    var message: String {
        switch self {
        case .runningInMemory(let reason):
            return "Your saved data couldn't be opened, so the app is running in temporary mode. Nothing you do this session will be saved. (\(reason))"
        case .fetchFailed(let entity, let reason):
            return "Couldn't load \(entity). (\(reason))"
        case .saveFailed(let reason):
            return "Your latest changes couldn't be saved. (\(reason))"
        case .deleteFailed(let reason):
            return "Couldn't erase your data. (\(reason))"
        case .duplicateRecords(let entity, let count):
            return "Found \(count) copies of \(entity); extra copies were removed."
        case .profileMissing:
            return "Your player profile couldn't be found."
        case .repairedValues(let entity, let fields):
            return "Some saved \(entity) values were invalid and have been reset: \(fields.joined(separator: ", "))."
        }
    }

    var suggestion: String? {
        switch self {
        case .runningInMemory: return "Free up storage space and restart the app."
        case .saveFailed: return "Your progress will be saved again on the next successful change."
        case .profileMissing: return "Return to the home screen to set up your profile again."
        case .fetchFailed, .deleteFailed: return "Try again in a moment."
        case .duplicateRecords, .repairedValues: return nil
        }
    }
}

// MARK: - Validation

enum ValidationIssue: Equatable {
    case emptyName
    case nameTooLong(max: Int)
    case nameInvalidCharacters
    case amountMissing
    case amountNotANumber
    case amountNotPositive
    case tooManyDecimalPlaces
    case amountExceedsCap(cap: Double)
    case amountExceedsAvailable(available: Double)
    case amountBelowMinimum(minimum: Double)
    case depositsUnavailable(cap: Double)
    case depositExceedsBalanceCap(maxAllowed: Double, cap: Double)

    var code: String {
        switch self {
        case .emptyName: return "001"
        case .nameTooLong: return "002"
        case .nameInvalidCharacters: return "003"
        case .amountMissing: return "004"
        case .amountNotANumber: return "005"
        case .amountNotPositive: return "006"
        case .tooManyDecimalPlaces: return "007"
        case .amountExceedsCap: return "008"
        case .amountExceedsAvailable: return "009"
        case .amountBelowMinimum: return "010"
        case .depositsUnavailable: return "011"
        case .depositExceedsBalanceCap: return "012"
        }
    }

    var message: String {
        switch self {
        case .emptyName: return "Please enter your name."
        case .nameTooLong(let max): return "Names can be at most \(max) characters."
        case .nameInvalidCharacters: return "Names can only use letters, numbers, spaces, apostrophes, hyphens and periods."
        case .amountMissing: return "Please enter an amount."
        case .amountNotANumber: return "That doesn't look like a dollar amount."
        case .amountNotPositive: return "The amount must be greater than zero."
        case .tooManyDecimalPlaces: return "Amounts can't go below whole cents."
        case .amountExceedsCap(let cap): return "The most you can deposit at once is \(CurrencyFormatter.string(cap))."
        case .amountExceedsAvailable(let available): return "You only have \(CurrencyFormatter.string(available)) available."
        case .amountBelowMinimum(let minimum): return "The minimum is \(CurrencyFormatter.string(minimum))."
        case .depositsUnavailable(let cap):
            return "You can only add funds while your total is under \(CurrencyFormatter.string(cap))."
        case .depositExceedsBalanceCap(let maxAllowed, let cap):
            return "Deposits can't take your total above \(CurrencyFormatter.string(cap)). The most you can add right now is \(CurrencyFormatter.string(maxAllowed))."
        }
    }
}

// MARK: - Game

enum GameIssue: Equatable {
    case shoeExhausted
    case shoeReshuffledMidHand
    case illegalAction(action: String, reason: String)
    case notYourTurn
    case wrongPhase(expected: String, actual: String)
    case insufficientChips(needed: Double, available: Double)
    case betBelowMinimum(minimum: Double)
    case noBetsPlaced
    case noActiveHand
    case dealerStateInvalid(String)
    case invariantViolated(String)
    case handVoided(reason: String)
    case countDesynchronized
    case seatMissing
    case remoteShuffleUnavailable(reason: String)

    var code: String {
        switch self {
        case .shoeExhausted: return "001"
        case .shoeReshuffledMidHand: return "002"
        case .illegalAction: return "003"
        case .notYourTurn: return "004"
        case .wrongPhase: return "005"
        case .insufficientChips: return "006"
        case .betBelowMinimum: return "007"
        case .noBetsPlaced: return "008"
        case .noActiveHand: return "009"
        case .dealerStateInvalid: return "010"
        case .invariantViolated: return "011"
        case .handVoided: return "012"
        case .countDesynchronized: return "013"
        case .seatMissing: return "014"
        case .remoteShuffleUnavailable: return "015"
        }
    }

    var severity: ErrorSeverity {
        switch self {
        case .countDesynchronized, .wrongPhase, .notYourTurn: return .info
        case .illegalAction, .insufficientChips, .betBelowMinimum, .shoeReshuffledMidHand,
             .remoteShuffleUnavailable:
            return .warning
        case .shoeExhausted, .noBetsPlaced, .noActiveHand, .dealerStateInvalid,
             .invariantViolated, .handVoided, .seatMissing:
            return .error
        }
    }

    var title: String {
        switch self {
        case .illegalAction: return "Not Allowed"
        case .handVoided: return "Hand Voided"
        case .insufficientChips: return "Not Enough Chips"
        default: return "Table Problem"
        }
    }

    var message: String {
        switch self {
        case .shoeExhausted: return "The shoe ran out of cards."
        case .shoeReshuffledMidHand: return "The shoe ran low, so the discard tray was reshuffled mid-hand."
        case .illegalAction(let action, let reason): return "\(action): \(reason)"
        case .notYourTurn: return "It isn't your turn yet."
        case .wrongPhase(let expected, let actual): return "That can only happen during \(expected) (currently \(actual))."
        case .insufficientChips(let needed, let available):
            return "That needs \(CurrencyFormatter.string(needed)), but only \(CurrencyFormatter.string(available)) is on the table."
        case .betBelowMinimum(let minimum): return "The table minimum is \(CurrencyFormatter.string(minimum))."
        case .noBetsPlaced: return "No bets were placed, so the hand couldn't start."
        case .noActiveHand: return "There's no active hand to act on."
        case .dealerStateInvalid(let detail): return "The dealer's hand is in an unexpected state. (\(detail))"
        case .invariantViolated(let detail): return "The table reached an inconsistent state. (\(detail))"
        case .handVoided(let reason): return "The hand couldn't be completed and has been voided. All wagers were returned. (\(reason))"
        case .countDesynchronized: return "The card counter saw more cards than the shoe holds."
        case .seatMissing: return "Your seat at the table couldn't be found."
        case .remoteShuffleUnavailable(let reason):
            return "\(reason) The shoe was shuffled on your device instead."
        }
    }

    var suggestion: String? {
        switch self {
        case .handVoided: return "You can keep playing - the next hand will start fresh."
        case .seatMissing, .invariantViolated, .dealerStateInvalid: return "Leave the table and start a new game if this keeps happening."
        default: return nil
        }
    }
}

// MARK: - Settings

enum SettingsIssue: Equatable {
    case deckCountAdjusted(from: Int, to: Int)
    case invalidRange(name: String)
    case valuesRepaired(fields: [String])

    var code: String {
        switch self {
        case .deckCountAdjusted: return "001"
        case .invalidRange: return "002"
        case .valuesRepaired: return "003"
        }
    }

    var severity: ErrorSeverity {
        switch self {
        case .deckCountAdjusted, .invalidRange, .valuesRepaired: return .warning
        }
    }

    var message: String {
        switch self {
        case .deckCountAdjusted(let from, let to):
            return "Deck count changed from \(from) to \(to) to fit the number of players."
        case .invalidRange(let name):
            return "The \(name) range was invalid and has been corrected."
        case .valuesRepaired(let fields):
            return "Some table rules were invalid and were restored to safe values: \(fields.joined(separator: ", "))."
        }
    }

    var suggestion: String? { nil }
}

// MARK: - Funds

enum FundsIssue: Equatable {
    case negativeBalancePrevented(attempted: Double)
    case abandonedWagerForfeited(amount: Double)
    case insufficientFundsToPlay(minimum: Double)
    case invalidAmount
    case buyInAdjusted(to: Double)

    var code: String {
        switch self {
        case .negativeBalancePrevented: return "001"
        case .abandonedWagerForfeited: return "002"
        case .insufficientFundsToPlay: return "003"
        case .invalidAmount: return "004"
        case .buyInAdjusted: return "005"
        }
    }

    var severity: ErrorSeverity {
        switch self {
        case .negativeBalancePrevented, .invalidAmount: return .error
        case .abandonedWagerForfeited, .insufficientFundsToPlay: return .error
        case .buyInAdjusted: return .warning
        }
    }

    var title: String {
        switch self {
        case .abandonedWagerForfeited: return "Unfinished Hand"
        case .insufficientFundsToPlay: return "Not Enough Funds"
        default: return "Account Problem"
        }
    }

    var message: String {
        switch self {
        case .negativeBalancePrevented(let attempted):
            return "A transaction would have left your balance at \(CurrencyFormatter.string(attempted)). Your balance was set to $0 instead."
        case .abandonedWagerForfeited(let amount):
            return "The app closed in the middle of a hand, so the \(CurrencyFormatter.string(amount)) you had in play was forfeited."
        case .insufficientFundsToPlay(let minimum):
            return "You need at least \(CurrencyFormatter.string(minimum)) to sit down at a table."
        case .invalidAmount:
            return "A transaction had an invalid amount and was ignored."
        case .buyInAdjusted(let amount):
            return "Your buy-in was adjusted to \(CurrencyFormatter.string(amount)) to match your available funds."
        }
    }

    var suggestion: String? {
        switch self {
        case .insufficientFundsToPlay: return "Add funds from your profile to keep playing."
        default: return nil
        }
    }
}
