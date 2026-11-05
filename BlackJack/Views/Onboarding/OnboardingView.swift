//
//  OnboardingView.swift
//  BlackJack
//
//  Created by Chris Volentine on 11/2/26.
//
import SwiftUI

@MainActor
struct OnboardingView: View {
    let services: AppServices
    let onComplete: () -> Void

    @State private var viewModel: OnboardingViewModel
    @FocusState private var focusedField: Field?

    private enum Field { case name, deposit }

    init(services: AppServices, onComplete: @escaping () -> Void) {
        self.services = services
        self.onComplete = onComplete
        _viewModel = State(initialValue: OnboardingViewModel(services: services))
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            ForEach(Suit.allCases, id: \.self) { suit in
                                Text(suit.symbol)
                                    .foregroundStyle(suit.isRed ? AppTheme.copper : AppTheme.beige)
                            }
                        }
                        .font(.title2)
                        .accessibilityHidden(true)

                        Text("Welcome to the table")
                            .font(.system(.largeTitle, design: .rounded).bold())
                            .foregroundStyle(AppTheme.beige)
                        Text("Tell us your name and how much you'd like to deposit to get started.")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.beige.opacity(0.75))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        fieldLabel("Your name")
                        TextField("Name", text: $viewModel.name)
                            .textContentType(.givenName)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .submitLabel(.next)
                            .focused($focusedField, equals: .name)
                            .onSubmit { focusedField = .deposit }
                            .onChange(of: viewModel.name) { _, _ in viewModel.nameChanged() }
                            .accessibilityIdentifier("onboardingNameField")
                            .themedField(hasError: viewModel.nameError != nil)

                        HStack {
                            if let error = viewModel.nameError {
                                errorText(error)
                            }
                            Spacer()
                            Text("\(max(viewModel.remainingNameCharacters, 0)) left")
                                .font(.caption)
                                .foregroundStyle(viewModel.remainingNameCharacters < 0 ? AppTheme.copper : AppTheme.beige.opacity(0.5))
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        fieldLabel("Opening deposit")
                        HStack(spacing: 4) {
                            Text("$")
                                .font(.title3.bold())
                                .foregroundStyle(AppTheme.deepestTeal.opacity(0.7))
                            TextField("0", text: $viewModel.depositText)
                                .keyboardType(.decimalPad)
                                .focused($focusedField, equals: .deposit)
                                .onChange(of: viewModel.depositText) { _, _ in viewModel.depositChanged() }
                                .accessibilityLabel("Opening deposit")
                                .accessibilityIdentifier("onboardingDepositField")
                        }
                        .font(.title3)
                        .themedField(hasError: viewModel.depositError != nil || viewModel.depositPreviewIsWarning)

                        MoneySlider(
                            value: $viewModel.depositSliderValue,
                            upperBound: AppConfig.depositBalanceCap,
                            accessibilityLabel: "Opening deposit",
                            accessibilityIdentifier: "onboardingDepositSlider"
                        )

                        HStack(spacing: 8) {
                            ForEach(viewModel.quickAmounts, id: \.self) { amount in
                                Button {
                                    viewModel.selectQuickAmount(amount)
                                } label: {
                                    Text(CurrencyFormatter.compact(amount))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(AppTheme.beige)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(Capsule().fill(AppTheme.teal.opacity(0.5)))
                                }
                            }
                        }

                        if let error = viewModel.depositError {
                            errorText(error)
                        } else if let preview = viewModel.depositPreview {
                            Text(preview)
                                .font(.caption)
                                .foregroundStyle(viewModel.depositPreviewIsWarning ? AppTheme.copper : AppTheme.peach)
                        } else {
                            Text("Maximum deposit: \(CurrencyFormatter.string(AppConfig.depositBalanceCap))")
                                .font(.caption)
                                .foregroundStyle(AppTheme.beige.opacity(0.5))
                        }
                    }

                    Button {
                        focusedField = nil
                        if viewModel.submit() {
                            onComplete()
                        }
                    } label: {
                        if viewModel.isSubmitting {
                            ProgressView().tint(AppTheme.deepestTeal)
                        } else {
                            Text("Start Playing")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!viewModel.canSubmit)
                    .accessibilityIdentifier("onboardingStartButton")
                    .padding(.top, 8)
                }
                .padding(24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppTheme.background.ignoresSafeArea())
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                        .accessibilityIdentifier("keyboardDoneButton")
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .onAppear { focusedField = .name }
        .errorPresentation(services.errorCenter)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(1)
            .foregroundStyle(AppTheme.peach)
    }

    private func errorText(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(AppTheme.copper)
    }
}
