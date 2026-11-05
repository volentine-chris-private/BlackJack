//
//  CardViews.swift
//  BlackJack
//
//  Created by Chris Volentine on 11/2/26.
//
import SwiftUI

struct CardView: View {
    let card: Card?
    let isFaceUp: Bool
    let width: CGFloat

    private var height: CGFloat { width * 1.42 }
    private var corner: CGFloat { max(width * 0.12, 3) }

    var body: some View {
        ZStack {
            if isFaceUp, let card {
                face(card)
                    .transition(.opacity)
            } else {
                back
                    .transition(.opacity)
            }
        }
        .frame(width: width, height: height)
        .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
        .animation(.easeInOut(duration: 0.25), value: isFaceUp)
        .accessibilityElement()
        .accessibilityLabel(isFaceUp ? (card?.accessibilityLabel ?? "Card") : "Face-down card")
    }

    private func face(_ card: Card) -> some View {
        let color = card.suit.isRed ? AppTheme.darkCopper : AppTheme.deepestTeal
        return RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(AppTheme.beige)
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(AppTheme.peach, lineWidth: 1)
            )
            .overlay(alignment: .topLeading) {
                VStack(spacing: -2) {
                    Text(card.rank.label)
                        .font(.system(size: width * 0.30, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text(card.suit.symbol)
                        .font(.system(size: width * 0.24))
                }
                .foregroundStyle(color)
                .padding(.leading, width * 0.07)
                .padding(.top, width * 0.05)
            }
            .overlay(alignment: .bottomTrailing) {
                Text(card.suit.symbol)
                    .font(.system(size: width * 0.52))
                    .foregroundStyle(color)
                    .padding(.trailing, width * 0.06)
                    .padding(.bottom, width * 0.02)
            }
    }

    private var back: some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(AppTheme.deepTeal)
            .overlay(
                CardBackPattern()
                    .stroke(AppTheme.copper.opacity(0.55), lineWidth: 1)
                    .clipShape(RoundedRectangle(cornerRadius: corner * 0.6, style: .continuous))
                    .padding(width * 0.09)
            )
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(AppTheme.peach, lineWidth: 1.5)
            )
    }
}

struct CardBackPattern: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let step = max(rect.width / 5, 3)
        var offset = -rect.height
        while offset < rect.width + rect.height {
            path.move(to: CGPoint(x: rect.minX + offset, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + offset + rect.height, y: rect.minY))
            path.move(to: CGPoint(x: rect.minX + offset, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX + offset + rect.height, y: rect.maxY))
            offset += step
        }
        return path
    }
}

struct HandView: View {
    let cards: [Card]
    var hiddenIndices: Set<Int> = []
    let cardWidth: CGFloat
    let maxWidth: CGFloat

    var body: some View {
        let count = max(cards.count, 1)
        let available = max(maxWidth - cardWidth, 0)
        let spacing: CGFloat = count > 1
            ? min(cardWidth * 0.45, available / CGFloat(count - 1))
            : 0
        let totalWidth = cardWidth + spacing * CGFloat(count - 1)
        let middle = Double(count - 1) / 2

        ZStack(alignment: .leading) {
            ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                CardView(card: card, isFaceUp: !hiddenIndices.contains(index), width: cardWidth)
                    .rotationEffect(.degrees((Double(index) - middle) * 3))
                    .offset(x: spacing * CGFloat(index))
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .opacity
                        )
                    )
            }
        }
        .frame(width: totalWidth, height: cardWidth * 1.42, alignment: .leading)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: cards.map(\.id))
    }
}

struct HandBadge: View {
    let text: String
    var tone: Tone = .neutral

    enum Tone { case neutral, active, positive, negative }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(foreground)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(background))
    }

    private var background: Color {
        switch tone {
        case .neutral: return AppTheme.deeperTeal.opacity(0.85)
        case .active: return AppTheme.copper
        case .positive: return AppTheme.peach
        case .negative: return AppTheme.darkCopper
        }
    }

    private var foreground: Color {
        switch tone {
        case .neutral, .negative: return AppTheme.beige
        case .active, .positive: return AppTheme.deepestTeal
        }
    }
}

extension PlayerHand {
    var badgeTone: HandBadge.Tone {
        if let outcome {
            switch outcome {
            case .blackjackWin, .win: return .positive
            case .loss, .surrendered: return .negative
            case .push: return .neutral
            }
        }
        switch state {
        case .busted, .surrendered: return .negative
        case .blackjack: return .positive
        case .playing, .stood: return .neutral
        }
    }
}
