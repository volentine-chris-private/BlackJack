//
//  TableControls.swift
//  BlackJack
//
//  Created by Chris Volentine on 11/2/26.
//
import SwiftUI

/// Fixed controls at the bottom of the table:
/// - During play: buttons for Hit, Stand, Double, Split, Surrender
/// - During betting: a single 'Place Bet' button
/// - Always: a wider 'leave table 'button at the bottom
struct ActionBarView: View {
    let available: Set<PlayerAction>
    let isBetting: Bool
    let canDeal: Bool
    let dealTotal: Double
    let leaveTitle: String
    let isLeavePending: Bool
    let onAction: (PlayerAction) -> Void
    let onDeal: () -> Void
    let onLeave: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Group {
                if isBetting {
                    dealButton
                } else {
                    HStack(spacing: 10) {
                        ForEach(PlayerAction.allCases) { action in
                            ActionButton(action: action, isEnabled: available.contains(action)) {
                                onAction(action)
                            }
                        }
                    }
                }
            }
            .frame(height: 64)
            .animation(.easeInOut(duration: 0.2), value: isBetting)

            Button(action: onLeave) {
                HStack(spacing: 8) {
                    Image(systemName: isLeavePending ? "clock.arrow.circlepath" : "rectangle.portrait.and.arrow.right")
                    Text(leaveTitle)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isLeavePending ? AppTheme.deepestTeal : AppTheme.beige)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    Capsule().fill(isLeavePending ? AppTheme.peach : AppTheme.beige.opacity(0.14))
                )
                .overlay(Capsule().strokeBorder(AppTheme.peach.opacity(0.5), lineWidth: 1))
            }
            .padding(.horizontal, 30)
            .accessibilityIdentifier("leaveTableButton")
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 6)
        .background(
            AppTheme.deeperTeal
                .overlay(alignment: .top) {
                    Rectangle().fill(AppTheme.peach.opacity(0.35)).frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private var dealButton: some View {
        Button(action: onDeal) {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.portrait.on.rectangle.portrait.angled.fill")
                    .font(.system(size: 20, weight: .semibold))
                Text(dealTotal > 0 ? "Place Bet · \(CurrencyFormatter.string(dealTotal))" : "Place Bet")
                    .font(.title3.bold())
                    .monospacedDigit()
            }
            .foregroundStyle(canDeal ? AppTheme.deepestTeal : AppTheme.beige.opacity(0.4))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(canDeal ? AppTheme.copper : AppTheme.teal.opacity(0.3))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(canDeal ? AppTheme.peach : AppTheme.beige.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!canDeal)
        .accessibilityLabel(dealTotal > 0 ? "Deal, total bet \(CurrencyFormatter.string(dealTotal))" : "Place Bet")
        .accessibilityIdentifier("dealButton")
        .accessibilityHint(canDeal ? "Starts the hand" : "Place a bet first")
    }
}

private struct ActionButton: View {
    let action: PlayerAction
    let isEnabled: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                Image(systemName: action.systemImage)
                    .font(.system(size: 20, weight: .semibold))
                Text(action.title)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(isEnabled ? AppTheme.deepestTeal : AppTheme.beige.opacity(0.35))
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isEnabled ? AppTheme.copper : AppTheme.teal.opacity(0.3))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isEnabled ? AppTheme.peach : AppTheme.beige.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .animation(.easeInOut(duration: 0.15), value: isEnabled)
        .accessibilityLabel(action.title)
        .accessibilityIdentifier("action\(action.title)")
    }
}

/// Context strip above the action bar. Either:
///   - bet controls and chips while betting
///   - early-surrender prompt when offered
struct BettingTrayView: View {
    @Bindable var viewModel: BlackjackViewModel

    var body: some View {
        Group {
            if viewModel.isAwaitingEarlySurrender {
                earlySurrenderPrompt
            } else if viewModel.isBetting {
                bettingControls
            } else {
                statusLine
            }
        }
        .frame(height: 112)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isBetting)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isAwaitingEarlySurrender)
    }

    // MARK: Betting

    private var bettingControls: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                BetControlButton(
                    title: "Clear",
                    systemImage: "trash",
                    isEnabled: viewModel.canClearBet,
                    accessibilityHint: "Sets your bet back to zero",
                    accessibilityIdentifier: "clearBetButton"
                ) {
                    viewModel.clearBet()
                }

                VStack(spacing: 2) {
                    Text("Bet")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.beige.opacity(0.65))
                    Text(CurrencyFormatter.string(viewModel.pendingBet))
                        .font(.title2.bold().monospacedDigit())
                        .foregroundStyle(AppTheme.peach)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if let hint = viewModel.dealHint {
                        Text(hint)
                            .font(.caption2)
                            .foregroundStyle(AppTheme.beige.opacity(0.6))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Current bet \(CurrencyFormatter.string(viewModel.pendingBet))")
                .accessibilityIdentifier("pendingBetAmount")

                BetControlButton(
                    title: "Max",
                    systemImage: "arrow.up.to.line",
                    isEnabled: viewModel.canMaxBet,
                    accessibilityHint: "Bets all of your chips",
                    accessibilityIdentifier: "maxBetButton"
                ) {
                    viewModel.maxBet()
                }
            }

            HStack(spacing: 0) {
                ForEach(BlackjackViewModel.chipValues, id: \.self) { value in
                    ChipButton(value: value, isEnabled: viewModel.canAddChip(value)) {
                        viewModel.addChip(value)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: Other states

    private var earlySurrenderPrompt: some View {
        VStack(spacing: 10) {
            Text(viewModel.statusText)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.beige)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            HStack(spacing: 10) {
                Button("Surrender") { viewModel.perform(.surrender) }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.deepestTeal)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Capsule().fill(AppTheme.copper))
                Button("Play On") { viewModel.declineEarlySurrender() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.deepestTeal)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Capsule().fill(AppTheme.peach))
            }
        }
    }

    private var statusLine: some View {
        HStack(spacing: 8) {
            if viewModel.isShuffling {
                ProgressView()
                    .tint(AppTheme.peach)
            }
            Text(viewModel.statusText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(viewModel.isAwaitingUserAction ? AppTheme.peach : AppTheme.beige.opacity(0.75))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
        }
    }
}

/// Clear / Max bet buttons
private struct BetControlButton: View {
    let title: String
    let systemImage: String
    let isEnabled: Bool
    let accessibilityHint: String
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(isEnabled ? AppTheme.beige : AppTheme.beige.opacity(0.35))
                .frame(minWidth: 88, minHeight: 44)
                .padding(.horizontal, 4)
                .background(
                    Capsule().fill(AppTheme.deeperTeal.opacity(isEnabled ? 0.7 : 0.35))
                )
                .overlay(
                    Capsule().strokeBorder(isEnabled ? AppTheme.peach.opacity(0.7) : AppTheme.beige.opacity(0.15), lineWidth: 1.5)
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityHint(accessibilityHint)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private struct ChipButton: View {
    let value: Double
    let isEnabled: Bool
    let onTap: () -> Void

    private var colors: (fill: Color, text: Color) {
        switch value {
            case ..<10: return (AppTheme.beige, AppTheme.deepestTeal)
            case ..<50: return (AppTheme.mutedTeal, AppTheme.beige)
            case ..<200: return (AppTheme.teal, AppTheme.peach)
            case ..<1_000: return (AppTheme.copper, AppTheme.deeperTeal)
            default: return (AppTheme.peach, AppTheme.deepestTeal)
        }
    }

    var body: some View {
        Button(action: onTap) {
            Text(value >= 1_000 ? "1K" : "\(Int(value))")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(colors.text)
                .frame(width: 44, height: 44)
                .background(Circle().fill(colors.fill))
                .overlay(
                    Circle()
                        .strokeBorder(colors.text.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                        .padding(3)
                )
                .overlay(Circle().strokeBorder(AppTheme.deeperTeal.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .accessibilityLabel("Add \(CurrencyFormatter.string(value)) chip")
        .accessibilityIdentifier("chip\(Int(value))")
    }
}

struct ActionBannerView: View {
    let banner: BlackjackViewModel.Banner?

    var body: some View {
        ZStack {
            if let banner {
                Text(banner.text)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(AppTheme.deepestTeal)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(fill(for: banner.tone))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(AppTheme.deepestTeal.opacity(0.2), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
                    .padding(.horizontal, 40)
                    .id(banner.id)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                    .accessibilityAddTraits(.updatesFrequently)
                    .accessibilityIdentifier("actionBanner")
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: banner?.id)
        .allowsHitTesting(false)
    }

    private func fill(for tone: BlackjackViewModel.Banner.Tone) -> Color {
        switch tone {
        case .neutral, .info: return AppTheme.beige
        case .positive: return AppTheme.peach
        case .negative: return AppTheme.copper
        }
    }
}

struct ForfeitConfirmationView: View {
    let amountAtRisk: Double
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(AppTheme.copper)

            Text("Return to Home?")
                .font(.title2.bold())
                .foregroundStyle(AppTheme.beige)

            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(AppTheme.beige.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 10) {
                Button(amountAtRisk > 0 ? "Forfeit & Leave" : "Leave Table", action: onConfirm)
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("forfeitConfirmButton")
                Button("Keep Playing", action: onCancel)
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("forfeitCancelButton")
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background.ignoresSafeArea())
        .presentationDetents([.height(360)])
        .presentationDragIndicator(.visible)
    }

    private var message: String {
        if amountAtRisk > 0 {
            return "You'll forfeit your current hand and lose the \(CurrencyFormatter.string(amountAtRisk)) you have in play."
        }
        return "No wager is in play right now. Your chips go back into your total funds."
    }
}
