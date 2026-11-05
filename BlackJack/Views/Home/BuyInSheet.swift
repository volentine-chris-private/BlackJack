//
//  BuyInSheet.swift
//  BlackJack
//
//  Created by Chris Volentine on 11/2/26.
//
import SwiftUI

@MainActor
struct BuyInSheet: View {
    let title: String
    let subtitle: String
    let confirmTitle: String
    let services: AppServices
    let onConfirm: (Double) -> Void

    @State private var viewModel: BuyInViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFieldFocused: Bool

    init(
        title: String,
        subtitle: String,
        confirmTitle: String,
        availableFunds: Double,
        services: AppServices,
        onConfirm: @escaping (Double) -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.confirmTitle = confirmTitle
        self.services = services
        self.onConfirm = onConfirm
        _viewModel = State(initialValue: BuyInViewModel(availableFunds: availableFunds))
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.beige.opacity(0.8))

                    HStack {
                        Text("Available")
                        Spacer()
                        Text(CurrencyFormatter.string(viewModel.availableFunds))
                            .bold()
                    }
                    .foregroundStyle(AppTheme.peach)
                    .panelStyle()

                    HStack(spacing: 4) {
                        Text("$")
                            .font(.title.bold())
                            .foregroundStyle(AppTheme.deepestTeal.opacity(0.7))
                        TextField("0", text: $viewModel.amountText)
                            .keyboardType(.decimalPad)
                            .font(.title.bold())
                            .focused($isFieldFocused)
                            .onChange(of: viewModel.amountText) { _, _ in viewModel.textChanged() }
                            .accessibilityLabel("Buy-in amount")
                            .accessibilityIdentifier("buyInAmountField")
                    }
                    .themedField(hasError: viewModel.errorMessage != nil)

                    MoneySlider(
                        value: $viewModel.sliderValue,
                        upperBound: viewModel.availableFunds,
                        accessibilityLabel: "Buy-in amount",
                        accessibilityIdentifier: "buyInSlider"
                    )

                    HStack(spacing: 8) {
                        ForEach(viewModel.presets, id: \.self) { fraction in
                            Button {
                                isFieldFocused = false
                                viewModel.applyPreset(fraction)
                            } label: {
                                Text(fraction >= 1 ? "All" : "\(Int(fraction * 100.0))%")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppTheme.beige)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .background(Capsule().fill(AppTheme.teal.opacity(0.5)))
                            }
                        }
                    }

                    if let error = viewModel.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(AppTheme.copper)
                    } else if let hint = viewModel.hint {
                        Text(hint)
                            .font(.caption)
                            .foregroundStyle(AppTheme.peach)
                            .accessibilityIdentifier("buyInHint")
                    } else {
                        Text("Table minimum bet: \(CurrencyFormatter.string(AppConfig.tableMinimumBet)). Results update your total funds after every hand.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.beige.opacity(0.55))
                    }

                    Button(confirmTitle) {
                        isFieldFocused = false
                        if let amount = viewModel.validatedAmount() {
                            onConfirm(amount)
                            dismiss()
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!viewModel.canAfford || !viewModel.isAmountValid)
                    .accessibilityIdentifier("buyInConfirmButton")
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(AppTheme.peach)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isFieldFocused = false }
                        .accessibilityIdentifier("keyboardDoneButton")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .errorPresentation(services.errorCenter)
    }
}
