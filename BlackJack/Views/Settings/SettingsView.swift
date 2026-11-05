//
//  SettingsView.swift
//  BlackJack
//
//  Created by Chris Volentine on 11/2/26.
//
import SwiftUI

/// The adjustable table options. Each change validated and saved in real-time
@MainActor
struct SettingsView: View {
    let services: AppServices
    @State private var viewModel: SettingsViewModel
    @State private var isConfirmingReset = false

    init(services: AppServices) {
        self.services = services
        _viewModel = State(initialValue: SettingsViewModel(services: services))
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        Form {
            Section {
                Stepper(value: $viewModel.npcCount, in: AppConfig.npcRange) {
                    settingRow("Number of NPCs", value: "\(viewModel.npcCount)")
                }
                Stepper(value: $viewModel.deckCount, in: viewModel.deckRange) {
                    settingRow("Number of Decks", value: "\(viewModel.deckCount)")
                }
            } header: {
                sectionHeader("Table")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.deckRangeFooter)
                    if let note = viewModel.deckAdjustmentNote {
                        Text(note).foregroundStyle(AppTheme.copper)
                    }
                }
            }
            .listRowBackground(rowBackground)

            Section {
                Picker("Shuffle Rate", selection: $viewModel.shuffleMethod) {
                    ForEach(ShuffleMethod.allCases) { method in
                        Text(method.title).tag(method)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()

                if viewModel.shuffleMethod.usesPenetrationRange {
                    Stepper(value: $viewModel.penetrationMin, in: AppConfig.penetrationBounds) {
                        settingRow(
                            viewModel.shuffleMethod == .hotDeck ? "Fallback: no earlier than" : "No earlier than",
                            value: "\(viewModel.penetrationMin)%"
                        )
                    }
                    Stepper(value: $viewModel.penetrationMax, in: AppConfig.penetrationBounds) {
                        settingRow(
                            viewModel.shuffleMethod == .hotDeck ? "Fallback: no later than" : "No later than",
                            value: "\(viewModel.penetrationMax)%"
                        )
                    }
                }

                if viewModel.shuffleMethod == .timedInterval {
                    Stepper(value: $viewModel.minutesMin, in: AppConfig.minuteBounds, step: AppConfig.minuteStep) {
                        settingRow("No sooner than", value: "\(viewModel.minutesMin) min")
                    }
                    Stepper(value: $viewModel.minutesMax, in: AppConfig.minuteBounds, step: AppConfig.minuteStep) {
                        settingRow("No later than", value: "\(viewModel.minutesMax) min")
                    }
                }
            } header: {
                sectionHeader("Shuffle Rate")
            } footer: {
                Text(viewModel.shuffleMethod.detail)
            }
            .listRowBackground(rowBackground)

            Section {
                Toggle("Dealer stands on soft 17", isOn: viewModel.toggle(\.dealerStandSoftSeventeen))
                Toggle("Blackjack pays 6:5 (instead of 3:2)", isOn: viewModel.toggle(\.payoutSixFiveNotThreeTwo))
            } header: {
                sectionHeader("Dealer & Payouts")
            } footer: {
                Text("Hitting soft 17 and 6:5 payouts both favour the house.")
            }
            .listRowBackground(rowBackground)

            Section {
                Picker("Allowed hands", selection: $viewModel.doubleDownRule) {
                    ForEach(DoubleDownRule.allCases) { rule in
                        Text(rule.title).tag(rule)
                    }
                }
                .pickerStyle(.menu)
                Toggle("Double after split", isOn: viewModel.toggle(\.canDoubleAfterSplit))
                Toggle("Double after hitting", isOn: viewModel.toggle(\.canDoubleAfterHit))
                Toggle("Re-double", isOn: viewModel.toggle(\.canReDouble))
            } header: {
                sectionHeader("Doubling Down")
            } footer: {
                Text("Re-doubling lets you double again after receiving your double-down card (up to \(AppConfig.maxDoublesPerHand) times).")
            }
            .listRowBackground(rowBackground)

            Section {
                Picker("Re-splits", selection: $viewModel.reSplitRule) {
                    ForEach(ReSplitRule.allCases) { rule in
                        Text(rule.title).tag(rule)
                    }
                }
                .pickerStyle(.menu)
                Toggle("Re-split aces", isOn: viewModel.toggle(\.canReSplitAces))
                Toggle("Same-rank splits only", isOn: viewModel.toggle(\.enforceSameRankSplits))
            } header: {
                sectionHeader("Splitting")
            } footer: {
                Text("With same-rank splits on, K-K can be split but K-Q can't.")
            }
            .listRowBackground(rowBackground)

            Section {
                Toggle("Early surrender 10-A", isOn: viewModel.toggle(\.canEarlySurrender))
                Toggle("Late surrender", isOn: viewModel.toggle(\.canLateSurrender))
            } header: {
                sectionHeader("Surrender")
            } footer: {
                Text("Early surrender is offered before the dealer checks for Blackjack; late surrender after.")
            }
            .listRowBackground(rowBackground)

            if !viewModel.ruleNotes.isEmpty {
                Section {
                    ForEach(viewModel.ruleNotes, id: \.self) { note in
                        Label(note, systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.peach)
                    }
                } header: {
                    sectionHeader("Notes")
                }
                .listRowBackground(rowBackground)
            }

            Section {
                Button("Restore Default Rules", role: .destructive) {
                    isConfirmingReset = true
                }
                .frame(maxWidth: .infinity)
            } footer: {
                Text("Rule changes apply the next time you sit down at a table.")
            }
            .listRowBackground(rowBackground)
        }
        .foregroundStyle(AppTheme.beige)
        .scrollContentBackground(.hidden)
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(AppTheme.deeperTeal, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .confirmationDialog("Restore the default table rules?", isPresented: $isConfirmingReset, titleVisibility: .visible) {
            Button("Restore Defaults", role: .destructive) {
                viewModel.resetToDefaults()
            }
            Button("Cancel", role: .cancel) {}
        }
        .onDisappear { viewModel.tearDown() }
    }

    private var rowBackground: some View {
        AppTheme.teal.opacity(0.28)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.peach)
    }

    private func settingRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .monospacedDigit()
                .foregroundStyle(AppTheme.peach)
        }
    }
}
