//
//  InputValidator.swift
//  BlackJack
//
//  Created by Chris Volentine on 11/2/26.
//

import Foundation

enum InputValidator {
    private static let allowedNameCharacters: CharacterSet = {
        var set = CharacterSet.letters
        set.formUnion(.decimalDigits)
        set.insert(charactersIn: " '’-.")
        return set
    }()

    // MARK: Names

    static func validateName(_ raw: String) -> Result<String, AppError> {
        let collapsed = raw
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")

        guard !collapsed.isEmpty else {
            return .failure(.validation(.emptyName))
        }
        guard collapsed.count <= AppConfig.nameMaxLength else {
            return .failure(.validation(.nameTooLong(max: AppConfig.nameMaxLength)))
        }
        guard collapsed.unicodeScalars.allSatisfy({ allowedNameCharacters.contains($0) }) else {
            return .failure(.validation(.nameInvalidCharacters))
        }
        return .success(collapsed)
    }

    // MARK: Amounts

    static func parseAmount(_ raw: String, locale: Locale = .current) -> Result<Double, AppError> {
        let decimalSeparator = locale.decimalSeparator ?? "."
        let groupingSeparator = locale.groupingSeparator ?? ","

        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.replacingOccurrences(of: "$", with: "")
        cleaned = cleaned.replacingOccurrences(of: " ", with: "")
        if let symbol = locale.currencySymbol {
            cleaned = cleaned.replacingOccurrences(of: symbol, with: "")
        }
        if groupingSeparator != decimalSeparator {
            cleaned = cleaned.replacingOccurrences(of: groupingSeparator, with: "")
        }
        if decimalSeparator != "." {
            cleaned = cleaned.replacingOccurrences(of: decimalSeparator, with: ".")
        }

        guard !cleaned.isEmpty else { return .failure(.validation(.amountMissing)) }
        guard let value = Double(cleaned), value.isFinite else {
            return .failure(.validation(.amountNotANumber))
        }
        guard value > 0 else { return .failure(.validation(.amountNotPositive)) }

        let cents = Money.rounded(value)
        guard abs(cents - value) < 0.000_001 else {
            return .failure(.validation(.tooManyDecimalPlaces))
        }
        return .success(cents)
    }

    static func maximumDeposit(currentFunds: Double) -> Double {
        let funds = currentFunds.isFinite ? max(currentFunds, 0) : 0
        return Money.rounded(max(AppConfig.depositBalanceCap - funds, 0))
    }

    static func validateDeposit(_ amount: Double, currentFunds: Double) -> Result<Double, AppError> {
        let cap = AppConfig.depositBalanceCap
        guard amount.isFinite, amount > 0 else { return .failure(.validation(.amountNotPositive)) }

        let maxAllowed = maximumDeposit(currentFunds: currentFunds)
        guard maxAllowed > 0 else {
            return .failure(.validation(.depositsUnavailable(cap: cap)))
        }
        guard Money.rounded(amount) <= maxAllowed else {
            if maxAllowed >= cap {
                return .failure(.validation(.amountExceedsCap(cap: cap)))
            }
            return .failure(.validation(.depositExceedsBalanceCap(maxAllowed: maxAllowed, cap: cap)))
        }
        return .success(Money.rounded(amount))
    }

    static func validateBuyIn(_ amount: Double, available: Double) -> Result<Double, AppError> {
        guard amount.isFinite, amount > 0 else { return .failure(.validation(.amountNotPositive)) }
        guard amount >= AppConfig.tableMinimumBet else {
            return .failure(.validation(.amountBelowMinimum(minimum: AppConfig.tableMinimumBet)))
        }
        guard amount.isWithinToleranceOf(available) else {
            return .failure(.validation(.amountExceedsAvailable(available: available)))
        }
        return .success(Money.rounded(amount))
    }

    static func validateBet(_ amount: Double, stack: Double) -> Result<Double, AppError> {
        guard amount.isFinite, amount > 0 else {
            return .failure(.game(.betBelowMinimum(minimum: AppConfig.tableMinimumBet)))
        }
        guard amount >= AppConfig.tableMinimumBet else {
            return .failure(.game(.betBelowMinimum(minimum: AppConfig.tableMinimumBet)))
        }
        guard amount.isWithinToleranceOf(stack) else {
            return .failure(.game(.insufficientChips(needed: amount, available: stack)))
        }
        return .success(Money.rounded(amount))
    }
}
