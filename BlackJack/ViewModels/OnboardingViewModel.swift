//
//  OnboardingViewModel.swift
//  BlackJack
//
//  Created by Chris Volentine on 11/2/26.
//
import Foundation
import Observation

@Observable
@MainActor
final class OnboardingViewModel {
    private let services: AppServices

    var name = ""
    var depositText = ""
    private(set) var nameError: String?
    private(set) var depositError: String?
    private(set) var isSubmitting = false

    let quickAmounts: [Double] = [100, 250, 500, 1_000]

    init(services: AppServices) {
        self.services = services
    }

    var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !depositText.isEmpty && !isSubmitting
    }

    var remainingNameCharacters: Int {
        AppConfig.nameMaxLength - name.trimmingCharacters(in: .whitespaces).count
    }

    var depositPreview: String? {
        guard !depositText.isEmpty else { return nil }
        switch InputValidator.parseAmount(depositText) {
        case .success(let value):
            if value > AppConfig.depositBalanceCap {
                return "Deposits are capped at \(CurrencyFormatter.string(AppConfig.depositBalanceCap))"
            }
            return "Depositing \(CurrencyFormatter.string(value))"
        case .failure:
            return nil
        }
    }

    var depositPreviewIsWarning: Bool {
        if case .success(let value) = InputValidator.parseAmount(depositText) {
            return value > AppConfig.depositBalanceCap
        }
        return false
    }

    func nameChanged() { nameError = nil }
    func depositChanged() { depositError = nil }

    var depositSliderValue: Double {
        get {
            guard case .success(let value) = InputValidator.parseAmount(depositText) else { return 0 }
            return value.clamped(to: 0...AppConfig.depositBalanceCap)
        }
        set {
            depositText = Money.fieldString(Money.sliderSnap(newValue, upperBound: AppConfig.depositBalanceCap))
            depositError = nil
        }
    }

    func selectQuickAmount(_ amount: Double) {
        depositText = Money.plainString(amount)
        depositError = nil
    }

    func submit() -> Bool {
        guard !isSubmitting else { return false }
        isSubmitting = true
        defer { isSubmitting = false }

        var validName: String?
        var validAmount: Double?

        switch InputValidator.validateName(name) {
        case .success(let value): validName = value
        case .failure(let error): nameError = error.message
        }

        switch InputValidator.parseAmount(depositText).flatMap({ InputValidator.validateDeposit($0, currentFunds: 0) }) {
        case .success(let value): validAmount = value
        case .failure(let error): depositError = error.message
        }

        guard let validName, let validAmount else { return false }

        do {
            let profile = try services.dataStore.createProfile(name: validName)
            try services.ledger.deposit(validAmount, to: profile)
            return true
        } catch {
            services.errorCenter.report(error, context: "OnboardingViewModel.submit")
            return false
        }
    }
}
