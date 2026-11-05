//
//  MoneySlider.swift
//  BlackJack
//
//  Created by Chris Volentine on 11/2/26.
//
import SwiftUI

struct MoneySlider: View {
    @Binding var value: Double
    let upperBound: Double
    let accessibilityLabel: String
    var accessibilityIdentifier: String = "moneySlider"

    var body: some View {
        VStack(spacing: 4) {
            Slider(value: $value, in: 0...max(upperBound, 1))
                .tint(AppTheme.copper)
                .disabled(upperBound <= 0)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityValue(CurrencyFormatter.string(value))
                .accessibilityIdentifier(accessibilityIdentifier)

            HStack {
                Text(CurrencyFormatter.string(0))
                Spacer()
                Text(CurrencyFormatter.string(upperBound))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(AppTheme.beige.opacity(0.55))
            .accessibilityHidden(true)
        }
    }
}
//TODO: #Preview { MoneySlider() }
