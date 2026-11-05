//
//  ProfileView.swift
//  BlackJack
//
//  Created by Chris Volentine on 11/2/26.
//
import SwiftUI

/// Name, total funds and a 30-day chart of daily changes.
/// Also hosts deposits, renaming and a full data reset.
@MainActor
struct ProfileView: View {
    let services: AppServices
    let onRequestReset: () -> Void

    @State private var viewModel: ProfileViewModel
    @Environment(\.dismiss) private var dismiss

    init(services: AppServices, profile: UserProfile, onRequestReset: @escaping () -> Void) {
        self.services = services
        self.onRequestReset = onRequestReset
        _viewModel = State(initialValue: ProfileViewModel(services: services, profile: profile))
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    chartCard
                    statsGrid
                    actions
                }
                .padding(20)
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppTheme.deeperTeal, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(AppTheme.peach)
                }
            }
            .sheet(isPresented: $viewModel.isShowingDeposit) {
                DepositSheet(viewModel: viewModel, services: services)
            }
            .alert("Change Name", isPresented: $viewModel.isEditingName) {
                TextField("Name", text: $viewModel.nameDraft)
                    .textInputAutocapitalization(.words)
                Button("Save") { viewModel.saveName() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Up to \(AppConfig.nameMaxLength) characters.")
            }
            .confirmationDialog(
                "Erase all data?",
                isPresented: $viewModel.isConfirmingReset,
                titleVisibility: .visible
            ) {
                Button("Erase Everything", role: .destructive) { onRequestReset() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your profile, funds and history will be deleted and the rules reset. This can't be undone.")
            }
        }
        .errorPresentation(services.errorCenter)
    }

    // MARK: Sections

    private var header: some View {
        VStack(spacing: 10) {
            Text(viewModel.profile.initials)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.deepestTeal)
                .frame(width: 76, height: 76)
                .background(Circle().fill(AppTheme.peach))
                .overlay(Circle().strokeBorder(AppTheme.copper, lineWidth: 3))
                .accessibilityHidden(true)

            Button {
                viewModel.beginRename()
            } label: {
                HStack(spacing: 6) {
                    Text(viewModel.profile.name)
                        .font(.title2.bold())
                    Image(systemName: "pencil")
                        .font(.footnote)
                }
                .foregroundStyle(AppTheme.beige)
            }
            .accessibilityHint("Change your name")

            VStack(spacing: 2) {
                Text("Total Funds")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.beige.opacity(0.6))
                    .textCase(.uppercase)
                Text(viewModel.totalFundsText)
                    .accessibilityIdentifier("profileTotalFunds")
                    .font(.system(size: 36, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppTheme.peach)
                    .contentTransition(.numericText())
            }
        }
        .frame(maxWidth: .infinity)
        .panelStyle()
    }

    private var chartCard: some View {
        @Bindable var viewModel = viewModel

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Last 30 Days")
                    .font(.headline)
                    .foregroundStyle(AppTheme.beige)
                Spacer()
                Picker("Chart", selection: $viewModel.chartMode) {
                    ForEach(ProfileViewModel.ChartMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 210)
            }

            if viewModel.hasActivity {
                FundsChartView(points: viewModel.points, mode: viewModel.chartMode)
                    .frame(height: 220)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.largeTitle)
                    Text("Play a few hands and your daily results will show up here.")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(AppTheme.beige.opacity(0.5))
                .frame(maxWidth: .infinity, minHeight: 180)
            }

            if viewModel.chartMode == .dailyChange {
                Toggle("Include deposits", isOn: $viewModel.includeDeposits)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.beige.opacity(0.8))
            }
        }
        .panelStyle()
    }

    private var statsGrid: some View {
        let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        return LazyVGrid(columns: columns, spacing: 12) {
            statTile(title: "30-Day Result", value: CurrencyFormatter.signed(viewModel.thirtyDayGameNet))
            statTile(title: "Hands (30 days)", value: "\(viewModel.thirtyDayHands)")
            statTile(
                title: "Best Day",
                value: viewModel.bestDay.map { CurrencyFormatter.signed($0.gameNet) } ?? "-"
            )
            statTile(
                title: "Worst Day",
                value: viewModel.worstDay.map { CurrencyFormatter.signed($0.gameNet) } ?? "-"
            )
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button {
                viewModel.beginDeposit()
            } label: {
                Label("Add Funds", systemImage: "plus.circle.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!viewModel.canDeposit)
            .accessibilityIdentifier("addFundsButton")
            .accessibilityHint(viewModel.depositLimitText)

            Text(viewModel.depositLimitText)
                .font(.caption)
                .foregroundStyle(viewModel.canDeposit ? AppTheme.beige.opacity(0.6) : AppTheme.peach)
                .multilineTextAlignment(.center)

            Button(role: .destructive) {
                viewModel.isConfirmingReset = true
            } label: {
                Text("Erase All Data")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.copper)
                    .padding(.vertical, 8)
            }
        }
        .padding(.top, 4)
    }

    private func statTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(AppTheme.beige.opacity(0.6))
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(AppTheme.beige)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.teal.opacity(0.28))
        )
    }
}

@MainActor
struct DepositSheet: View {
    @Bindable var viewModel: ProfileViewModel
    let services: AppServices
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 4) {
                    Text("$")
                        .font(.title.bold())
                        .foregroundStyle(AppTheme.deepestTeal.opacity(0.7))
                    TextField("0", text: $viewModel.depositText)
                        .keyboardType(.decimalPad)
                        .font(.title.bold())
                        .onChange(of: viewModel.depositText) { _, _ in viewModel.depositChanged() }
                        .accessibilityLabel("Deposit amount")
                        .accessibilityIdentifier("depositAmountField")
                        .focused($isFieldFocused)
                }
                .themedField(hasError: viewModel.depositError != nil || viewModel.depositPreviewIsWarning)

                MoneySlider(
                    value: $viewModel.depositSliderValue,
                    upperBound: viewModel.maximumDeposit,
                    accessibilityLabel: "Deposit amount",
                    accessibilityIdentifier: "depositSlider"
                )

                Text(viewModel.depositLimitText)
                    .font(.caption)
                    .foregroundStyle(AppTheme.beige.opacity(0.7))
                    .accessibilityIdentifier("depositLimitText")

                HStack(spacing: 8) {
                    ForEach(viewModel.quickDepositAmounts, id: \.self) { amount in
                        let isMax = amount == viewModel.maximumDeposit
                        Button {
                            viewModel.selectQuickDeposit(amount)
                        } label: {
                            Text(isMax ? "Max" : CurrencyFormatter.compact(amount))
                                .accessibilityLabel(isMax ? "Maximum, \(CurrencyFormatter.string(amount))" : CurrencyFormatter.string(amount))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.beige)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Capsule().fill(AppTheme.teal.opacity(0.5)))
                        }
                    }
                }

                if let error = viewModel.depositError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(AppTheme.copper)
                } else if let preview = viewModel.depositPreview {
                    Text(preview)
                        .font(.caption)
                        .foregroundStyle(viewModel.depositPreviewIsWarning ? AppTheme.copper : AppTheme.peach)
                }

                Button("Deposit") { viewModel.submitDeposit() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(viewModel.depositText.isEmpty || viewModel.depositPreviewIsWarning)
                    .accessibilityIdentifier("depositConfirmButton")

                Spacer()
            }
            .padding(20)
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("Add Funds")
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
        .errorPresentation(services.errorCenter)
    }
}
