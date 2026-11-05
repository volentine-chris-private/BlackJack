//
//  BlackjackTableView.swift
//  BlackJack
//
//  Created by Chris Volentine on 11/2/26.
//
import SwiftUI

/// dealer at the top, up to five player tiles (the player at the bottom center),
/// a center banner announcing actions, fixed controls at the bottom
@MainActor
struct BlackjackTableView: View {
    let services: AppServices
    let onExit: () -> Void

    @State private var viewModel: BlackjackViewModel

    init(services: AppServices, config: GameSessionConfig, onExit: @escaping () -> Void) {
        self.services = services
        self.onExit = onExit
        _viewModel = State(initialValue: BlackjackViewModel(services: services, config: config))
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        VStack(spacing: 0) {
            tableArea
            BettingTrayView(viewModel: viewModel)
            ActionBarView(
                available: viewModel.availableActions,
                isBetting: viewModel.isBetting,
                canDeal: viewModel.canDeal,
                dealTotal: viewModel.pendingBet,
                leaveTitle: viewModel.leaveButtonTitle,
                isLeavePending: viewModel.leaveAfterHand,
                onAction: { viewModel.perform($0) },
                onDeal: { viewModel.deal() },
                onLeave: { viewModel.leaveButtonTapped() }
            )
        }
        .background(AppTheme.felt.ignoresSafeArea())
        .sheet(isPresented: $viewModel.isShowingForfeitConfirmation) {
            ForfeitConfirmationView(
                amountAtRisk: viewModel.amountAtRisk,
                onConfirm: { viewModel.confirmForfeit() },
                onCancel: { viewModel.isShowingForfeitConfirmation = false }
            )
        }
        .fullScreenCover(isPresented: $viewModel.isShowingRebuy) {
            BuyInSheet(
                title: "Buy More Chips",
                subtitle: "Bring more of your funds to the table.",
                confirmTitle: "Add Chips",
                availableFunds: viewModel.rebuyAvailable,
                services: services
            ) { amount in
                viewModel.rebuy(amount)
            }
        }
        .alert("Out of Chips", isPresented: $viewModel.isShowingOutOfChips) {
            if viewModel.rebuyAvailable >= AppConfig.tableMinimumBet {
                Button("Buy More Chips") { viewModel.isShowingRebuy = true }
            }
            Button("Leave Table", role: .cancel) { viewModel.leaveButtonTapped() }
        } message: {
            Text(viewModel.rebuyAvailable >= AppConfig.tableMinimumBet
                 ? "You don't have enough chips for the \(CurrencyFormatter.string(AppConfig.tableMinimumBet)) minimum. You have \(CurrencyFormatter.string(viewModel.rebuyAvailable)) more in your account."
                 : "You don't have enough funds left for another hand.")
        }
        .onChange(of: viewModel.shouldDismiss) { _, shouldDismiss in
            if shouldDismiss { onExit() }
        }
        .task { await viewModel.start() }
        .onDisappear { viewModel.tearDown() }
        .errorPresentation(services.errorCenter)
    }

    // MARK: Table layout

    private var tableArea: some View {
        GeometryReader { geo in
            let horizontalPadding: CGFloat = 12
            let usableHeight = geo.size.height - 14
            let centerGap = geo.size.width * 0.12
            let tileWidth = (geo.size.width - horizontalPadding * 2 - centerGap) / 2
            let dealerHeight = usableHeight * 0.27
            let rowHeight = usableHeight * 0.225

            VStack(spacing: 4) {
                ZStack(alignment: .top) {
                    DealerTileView(
                        dealer: viewModel.table.dealer,
                        isActive: viewModel.phase == .dealerTurn
                    )
                    .frame(width: min(geo.size.width * 0.48, 230), height: dealerHeight)

                    HStack(alignment: .top) {
                        backButton
                        Spacer()
                        countHUD
                    }
                }
                .frame(height: dealerHeight)

                HStack(spacing: centerGap) {
                    tile(.topLeft, width: tileWidth)
                    tile(.topRight, width: tileWidth)
                }
                .frame(height: rowHeight)

                HStack(spacing: centerGap) {
                    tile(.midLeft, width: tileWidth)
                    tile(.midRight, width: tileWidth)
                }
                .frame(height: rowHeight)

                tile(.bottom, width: tileWidth)
                    .frame(height: rowHeight)
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.top, 4)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            .overlay {
                ActionBannerView(banner: viewModel.banner)
            }
        }
    }

    private func tile(_ position: SeatPosition, width: CGFloat) -> some View {
        let seat = viewModel.seat(at: position)
        return PlayerTileView(seat: seat, activeHandIndex: viewModel.activeHandIndex(for: seat))
            .frame(width: width)
    }

    private var backButton: some View {
        Button {
            viewModel.requestReturnHome()
        } label: {
            Image(systemName: "arrow.left")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(AppTheme.beige)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AppTheme.deeperTeal.opacity(0.6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(AppTheme.beige.opacity(0.4), lineWidth: 1.5)
                )
        }
        .accessibilityLabel("Return to home")
        .accessibilityIdentifier("tableBackButton")
    }

    private var countHUD: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Button {
                viewModel.isCountVisible.toggle()
            } label: {
                Image(systemName: viewModel.isCountVisible ? "eye.fill" : "eye.slash")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.peach)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AppTheme.deeperTeal.opacity(0.6))
                    )
            }
            .accessibilityLabel(viewModel.isCountVisible ? "Hide count" : "Show count")

            if viewModel.isCountVisible {
                Text(viewModel.countSummary)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppTheme.beige)
                    .multilineTextAlignment(.trailing)
                    .padding(6)
                    .frame(maxWidth: 92, alignment: .trailing)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(AppTheme.deeperTeal.opacity(0.75))
                    )
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.isCountVisible)
    }
}
