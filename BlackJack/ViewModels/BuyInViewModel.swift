//
//  BuyInViewModel.swift
//  BlackJack
//
//  Created by Chris Volentine on 11/2/26.
//
import Foundation
import Observation

@Observable
@MainActor
final class BuyInViewModel {
    let availableFunds: Double
    let minimum = AppConfig.tableMinimumBet
    let presets: [Double] = [0.25, 0.5, 0.75, 1.0]

    var amountText = ""
    private(set) var errorMessage: String?

    init(availableFunds: Double) {
        self.availableFunds = max(0, Money.rounded(availableFunds))
    }

    // MARK: Derived

    var parsedAmount: Double? {
        let trimmed = amountText.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return 0 }
        if case .success(let value) = InputValidator.parseAmount(trimmed) { return value }
        return nil
    }

    var amount: Double { parsedAmount ?? 0 }

    var canAfford: Bool { availableFunds >= minimum }

    /// Enables the confirm button
    var isAmountValid: Bool {
        guard let parsedAmount else { return false }
        return parsedAmount >= minimum && parsedAmount.isWithinToleranceOf(availableFunds)
    }

    var hint: String? {
        guard canAfford else { return nil }
        guard let parsedAmount else { return ValidationIssue.amountNotANumber.message }
        if parsedAmount == 0 { return "Slide or type an amount - at least \(CurrencyFormatter.string(minimum))." }
        if parsedAmount < minimum { return ValidationIssue.amountBelowMinimum(minimum: minimum).message }
        if !parsedAmount.isWithinToleranceOf(availableFunds) { return ValidationIssue.amountExceedsAvailable(available: availableFunds).message }
        return nil
    }

    // MARK: Slider

    var sliderValue: Double {
        get { amount.clamped(to: 0...max(availableFunds, 0)) }
        set {
            amountText = Money.fieldString(Money.sliderSnap(newValue, upperBound: availableFunds))
            errorMessage = nil
        }
    }

    // MARK: Other

    func applyPreset(_ fraction: Double) {
        let raw = fraction >= 1 ? availableFunds : (availableFunds * fraction).rounded(.down)
        amountText = Money.fieldString(raw)
        errorMessage = nil
    }

    func textChanged() { errorMessage = nil }

    func validatedAmount() -> Double? {
        guard let value = parsedAmount, value > 0 else {
            errorMessage = ValidationIssue.amountBelowMinimum(minimum: minimum).message
            return nil
        }
        switch InputValidator.validateBuyIn(value, available: availableFunds) {
        case .success(let valid):
            errorMessage = nil
            return valid
        case .failure(let error):
            errorMessage = error.message
            return nil
        }
    }
}
