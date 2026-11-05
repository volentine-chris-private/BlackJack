//
//  Utilities.swift
//  BlackJack
//
//  Created by Chris Volentine on 11/2/26.
//

import Foundation
import OSLog

// MARK: - Logging

enum AppLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? AppConfig.bundleIdBackup

    static let app = Logger(subsystem: subsystem, category: "app")
    static let persistence = Logger(subsystem: subsystem, category: "persistence")
    static let game = Logger(subsystem: subsystem, category: "game")
    static let funds = Logger(subsystem: subsystem, category: "funds")
    static let counting = Logger(subsystem: subsystem, category: "counting")
}

// MARK: - Money

/// All money is stored as `Double` dollars, always rounded to whole cents
enum Money {
    static func rounded(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return (value * 100).rounded() / 100
    }

    static func floor(_ value: Double, toMultipleOf step: Double) -> Double {
        guard value.isFinite, step > 0 else { return 0 }
        return (value / step).rounded(.down) * step
    }

    static func sliderSnap(_ value: Double, upperBound: Double) -> Double {
        guard value.isFinite, upperBound.isFinite, upperBound > 0 else { return 0 }
        let clampedValue = min(max(value, 0), upperBound)
        if clampedValue >= upperBound { return rounded(upperBound) }
        let exponent = log10(upperBound).rounded(.down) - 3
        let step = max(1, pow(10, exponent))
        return min(rounded((clampedValue / step).rounded() * step), rounded(upperBound))
    }

    static func fieldString(_ value: Double) -> String {
        rounded(value) == 0 ? "" : plainString(value)
    }

    static func plainString(_ value: Double) -> String {
        let cents = rounded(value)
        if cents.rounded() == cents {
            return String(Int(cents))
        }
        return String(format: "%.2f", cents)
    }
}

enum CurrencyFormatter {
    static func string(_ amount: Double) -> String {
        let value = Money.rounded(amount)
        let isWhole = value.rounded() == value
        return value.formatted(.currency(code: "USD").precision(.fractionLength(isWhole ? 0 : 2)))
    }

    static func signed(_ amount: Double) -> String {
        let value = Money.rounded(amount)
        if value > 0 { return "+" + string(value) }
        if value < 0 { return "−" + string(abs(value)) }
        return string(0)
    }

    /// short format: 950, 12.5K, 1.2M
    static func compact(_ amount: Double) -> String {
        let magnitude = abs(amount)
        let sign = amount < 0 ? "−" : ""
        switch magnitude {
        case 1_000_000...:
            return "\(sign)$\(trimmed(magnitude / 1_000_000))M"
        case 1_000...:
            return "\(sign)$\(trimmed(magnitude / 1_000))K"
        default:
            return "\(sign)$\(Int(magnitude.rounded()))"
        }
    }

    private static func trimmed(_ value: Double) -> String {
        let oneDecimal = (value * 10).rounded() / 10
        if oneDecimal.rounded() == oneDecimal { return String(Int(oneDecimal)) }
        return String(format: "%.1f", oneDecimal)
    }
}

// MARK: - Collection helpers

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - Double: comparison helper

extension Double {
    /// Compares if this value is less than or equal to another value
    /// accounting for floating-point precision errors using a specific tolerance
    /// - Parameters:
    ///   - other: The value to compare against
    ///   - tolerance: The maximum allowable variance (defaults to 0.000_1)
    /// - Returns: A boolean indicating if the value is less than or close enough to be considered equal
    func isWithinToleranceOf(_ other: Double, tolerance: Double = 0.000_1) -> Bool {
        return (self < other) || (abs(self - other) < tolerance)
    }
}
