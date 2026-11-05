//
//  SeatTiles.swift
//  BlackJack
//
//  Created by Chris Volentine on 11/2/26.
//
import SwiftUI

struct PlayerTileView: View {
    let seat: Seat?
    let activeHandIndex: Int?

    var body: some View {
        GeometryReader { geo in
            if let seat {
                occupied(seat, size: geo.size)
            } else {
                emptySeat
            }
        }
    }

    // MARK: Occupied

    private func occupied(_ seat: Seat, size: CGSize) -> some View {
        let plateHeight = min(max(size.height * 0.28, 30), 40)
        let cardsHeight = max(size.height - plateHeight - 36, 16)
        let handCount = max(seat.hands.count, 1)
        let perHandWidth = (size.width - 12) / CGFloat(min(handCount, 2))
        let cardWidth = min(cardsHeight / 1.42, perHandWidth * 0.42, 46)
        let isTurn = activeHandIndex != nil

        return VStack(spacing: 4) {
            handsArea(seat, cardWidth: cardWidth, perHandWidth: perHandWidth)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            infoPlate(seat)
                .frame(height: plateHeight)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.tile, style: .continuous)
                .fill(seat.isUser ? AppTheme.teal.opacity(0.55) : AppTheme.teal.opacity(0.38))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.tile, style: .continuous)
                .strokeBorder(isTurn ? AppTheme.copper : AppTheme.peach.opacity(seat.isUser ? 0.5 : 0.2),
                              lineWidth: isTurn ? 2.5 : 1)
        )
        .shadow(color: isTurn ? AppTheme.copper.opacity(0.45) : .clear, radius: 8)
        .animation(.easeInOut(duration: 0.2), value: isTurn)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilitySummary(seat))
        .accessibilityIdentifier(seat.isUser ? "userSeatTile" : "npcSeatTile")
    }

    @ViewBuilder
    private func handsArea(_ seat: Seat, cardWidth: CGFloat, perHandWidth: CGFloat) -> some View {
        if seat.hands.isEmpty {
            Image(systemName: seat.isUser ? "dollarsign.circle" : "person.fill")
                .font(.title2)
                .foregroundStyle(AppTheme.beige.opacity(0.25))
        } else if seat.hands.count == 1, let hand = seat.hands.first {
            handColumn(hand, index: 0, cardWidth: cardWidth, maxWidth: perHandWidth - 8)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(seat.hands.enumerated()), id: \.element.id) { index, hand in
                            handColumn(hand, index: index, cardWidth: cardWidth * 0.85, maxWidth: perHandWidth - 10)
                                .id(index)
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .onChange(of: activeHandIndex) { _, newValue in
                    guard let newValue else { return }
                    withAnimation { proxy.scrollTo(newValue, anchor: .center) }
                }
            }
        }
    }

    private func handColumn(_ hand: PlayerHand, index: Int, cardWidth: CGFloat, maxWidth: CGFloat) -> some View {
        let isActive = activeHandIndex == index
        return VStack(spacing: 3) {
            HandBadge(text: hand.badgeText.isEmpty ? " " : hand.badgeText,
                      tone: isActive ? .active : hand.badgeTone)
            HandView(cards: hand.cards, cardWidth: cardWidth, maxWidth: maxWidth)
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isActive ? AppTheme.copper.opacity(0.8) : .clear, lineWidth: 1.5)
        )
    }

    private func infoPlate(_ seat: Seat) -> some View {
        VStack(spacing: 1) {
            HStack(spacing: 4) {
                if seat.isUser {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.caption2)
                }
                Text(seat.isUser ? "\(seat.name) (You)" : seat.name)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .layoutPriority(1)
                SessionNetLabel(net: seat.sessionNet)
                    .accessibilityIdentifier(seat.isUser ? "userSessionNet" : "npcSessionNet")
            }
            .foregroundStyle(AppTheme.deepestTeal)

            HStack(spacing: 6) {
                Text(CurrencyFormatter.string(seat.stack))
                    .foregroundStyle(AppTheme.teal)
                    .accessibilityIdentifier(seat.isUser ? "userStack" : "npcStack")
                if seat.inPlay > 0 {
                    Text("• \(CurrencyFormatter.string(seat.inPlay)) in play")
                        .foregroundStyle(AppTheme.darkCopper)
                }
            }
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppTheme.beige)
        )
    }

    // MARK: Empty

    private var emptySeat: some View {
        RoundedRectangle(cornerRadius: AppTheme.Radius.tile, style: .continuous)
            .strokeBorder(AppTheme.beige.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
            .overlay(
                Text("Open Seat")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.beige.opacity(0.25))
            )
            .accessibilityLabel("Empty seat")
    }

    private func accessibilitySummary(_ seat: Seat) -> String {
        var parts = ["\(seat.name)", "\(CurrencyFormatter.string(seat.stack)) at the table"]
        if seat.inPlay > 0 { parts.append("\(CurrencyFormatter.string(seat.inPlay)) in play") }
        parts.append(SessionNetLabel.spokenText(for: seat.sessionNet))
        for (index, hand) in seat.hands.enumerated() where !hand.cards.isEmpty {
            let label = seat.hands.count > 1 ? "hand \(index + 1)" : "hand"
            parts.append("\(label): \(hand.value.displayText)")
        }
        return parts.joined(separator: ", ")
    }
}

/// "+$25" in green, "−$25" in red, "$0" in regular? when even
struct SessionNetLabel: View {
    let net: Double

    var body: some View {
        Text(Self.text(for: net))
            .font(.caption.weight(.heavy).monospacedDigit())
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
            .accessibilityLabel(Self.spokenText(for: net))
    }

    static func text(for net: Double) -> String {
        let value = Money.rounded(net)
        if value > 0 { return "+" + CurrencyFormatter.string(value) }
        if value < 0 { return "-" + CurrencyFormatter.string(-value) }
        return CurrencyFormatter.string(0)
    }

    static func spokenText(for net: Double) -> String {
        let value = Money.rounded(net)
        if value > 0 { return "up \(CurrencyFormatter.string(value)) this game" }
        if value < 0 { return "down \(CurrencyFormatter.string(-value)) this game" }
        return "even this game"
    }

    private var color: Color {
        let value = Money.rounded(net)
        if value > 0 { return AppTheme.gain }
        if value < 0 { return AppTheme.loss }
        return AppTheme.deepestTeal.opacity(0.45)
    }
}

struct DealerTileView: View {
    let dealer: DealerHand
    let isActive: Bool

    var body: some View {
        GeometryReader { geo in
            let cardWidth = min((geo.size.height - 52) / 1.42, geo.size.width * 0.26, 54)
            VStack(spacing: 6) {
                Text("DEALER")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(AppTheme.deepestTeal)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(AppTheme.beige))

                if dealer.cards.isEmpty {
                    Spacer()
                    Image(systemName: "rectangle.stack.fill")
                        .font(.title)
                        .foregroundStyle(AppTheme.beige.opacity(0.2))
                    Spacer()
                } else {
                    HandView(
                        cards: dealer.cards,
                        hiddenIndices: dealer.hiddenIndices,
                        cardWidth: max(cardWidth, 20),
                        maxWidth: geo.size.width - 20
                    )
                    .frame(maxHeight: .infinity)
                }

                if let value = dealer.visibleValue {
                    HandBadge(
                        text: dealer.isHoleCardRevealed ? value.shortText : "Shows \(value.shortText)",
                        tone: value.isBust ? .positive : .neutral
                    )
                } else {
                    HandBadge(text: " ")
                        .opacity(0)
                }
            }
            .padding(8)
            .frame(width: geo.size.width, height: geo.size.height)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(AppTheme.deepTeal)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(isActive ? AppTheme.copper : AppTheme.peach.opacity(0.35), lineWidth: isActive ? 2.5 : 1)
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(dealerAccessibility)
    }

    private var dealerAccessibility: String {
        guard let value = dealer.visibleValue else { return "Dealer, no cards" }
        return dealer.isHoleCardRevealed ? "Dealer has \(value.displayText)" : "Dealer shows \(value.displayText)"
    }
}
