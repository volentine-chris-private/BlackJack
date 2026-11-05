//
//  AppTheme.swift
//  BlackJack
//
//  Created by Chris Volentine on 11/2/26.
//

import SwiftUI

enum AppTheme {
    /// Core palette
    static let deepTeal = Color(hex: 0x0D4954)
    static let teal = Color(hex: 0x247684)
    static let copper = Color(hex: 0xCD8157)
    static let peach = Color(hex: 0xDFA989)
    static let beige = Color(hex: 0xE3D7D0)

    /// Variants
    static let deeperTeal = Color(hex: 0x072C33)
    static let deepestTeal = Color(hex: 0x08262C)
    static let mutedTeal = Color(hex: 0x4E7979)
    static let darkCopper = Color(hex: 0x9E4B26)

    static let positive = beige
    static let negative = copper

    static let gain = Color(hex: 0x1D6B32) /// green
    static let loss = Color(hex: 0xA3231A) /// red

    static let background = LinearGradient(
        colors: [deepTeal, deeperTeal],
        startPoint: .top,
        endPoint: .bottom
    )

    static let felt = RadialGradient(
        colors: [teal.opacity(0.55), deepTeal, deeperTeal],
        center: .center,
        startRadius: 30,
        endRadius: 560
    )

    enum Radius {
        static let tile: CGFloat = 20
        static let button: CGFloat = 14
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }
}

// MARK: - Button styles

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(AppTheme.deepestTeal)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.button, style: .continuous)
                    .fill(AppTheme.copper)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(AppTheme.beige)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.button, style: .continuous)
                    .fill(AppTheme.teal.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.button, style: .continuous)
                    .strokeBorder(AppTheme.peach.opacity(0.6), lineWidth: 1)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct PanelBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.tile, style: .continuous)
                    .fill(AppTheme.teal.opacity(0.28))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.tile, style: .continuous)
                    .strokeBorder(AppTheme.peach.opacity(0.25), lineWidth: 1)
            )
    }
}

extension View {
    func panelStyle() -> some View { modifier(PanelBackground()) }
}

struct ThemedFieldStyle: ViewModifier {
    var hasError: Bool

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .foregroundStyle(AppTheme.deepestTeal)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppTheme.beige)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(hasError ? AppTheme.copper : Color.clear, lineWidth: 2)
            )
    }
}

extension View {
    func themedField(hasError: Bool = false) -> some View {
        modifier(ThemedFieldStyle(hasError: hasError))
    }
}
