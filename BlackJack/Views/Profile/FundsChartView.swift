//
//  FundsChartView.swift
//  BlackJack
//
//  Created by Chris Volentine on 11/2/26.
//
import SwiftUI
import Charts

/// 30-day chart of daily changes in total funds (bars) or closing balance (line).
/// Tap or drag across the chart to inspect a day
struct FundsChartView: View {
    let points: [FundsChartPoint]
    let mode: ProfileViewModel.ChartMode

    @State private var selectedDate: Date?

    private var selectedPoint: FundsChartPoint? {
        guard let selectedDate else { return nil }
        return points.first { Calendar.current.isDate($0.day, inSameDayAs: selectedDate) }
    }

    var body: some View {
        Chart {
            if mode == .dailyChange {
                RuleMark(y: .value("Zero", 0.0))
                    .foregroundStyle(AppTheme.beige.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1))

                ForEach(points) { point in
                    BarMark(
                        x: .value("Day", point.day, unit: .day),
                        y: .value("Change", point.change)
                    )
                    .foregroundStyle(point.change >= 0 ? AppTheme.peach : AppTheme.copper)
                    .cornerRadius(3)
                }
            } else {
                ForEach(points) { point in
                    AreaMark(
                        x: .value("Day", point.day, unit: .day),
                        y: .value("Balance", point.closingBalance)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [AppTheme.teal.opacity(0.7), AppTheme.teal.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.monotone)

                    LineMark(
                        x: .value("Day", point.day, unit: .day),
                        y: .value("Balance", point.closingBalance)
                    )
                    .foregroundStyle(AppTheme.peach)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .interpolationMethod(.monotone)
                }
            }

            if let selectedPoint {
                RuleMark(x: .value("Selected", selectedPoint.day, unit: .day))
                    .foregroundStyle(AppTheme.beige.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(
                        position: .top,
                        spacing: 4,
                        overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                    ) {
                        annotation(for: selectedPoint)
                    }
            }
        }
        .chartXSelection(value: $selectedDate)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                AxisGridLine()
                    .foregroundStyle(AppTheme.beige.opacity(0.08))
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .foregroundStyle(AppTheme.beige.opacity(0.7))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                    .foregroundStyle(AppTheme.beige.opacity(0.08))
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(CurrencyFormatter.compact(amount))
                            .foregroundStyle(AppTheme.beige.opacity(0.7))
                    }
                }
            }
        }
        .accessibilityLabel(mode == .dailyChange ? "Daily change in total funds" : "Total funds balance")
    }

    private func annotation(for point: FundsChartPoint) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(point.day, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                .font(.caption2.weight(.semibold))
            if mode == .dailyChange {
                Text(CurrencyFormatter.signed(point.change))
                    .font(.caption.bold())
                if point.deposits > 0 {
                    Text("incl. \(CurrencyFormatter.string(point.deposits)) deposited")
                        .font(.caption2)
                }
            } else {
                Text(CurrencyFormatter.string(point.closingBalance))
                    .font(.caption.bold())
            }
            if point.handsPlayed > 0 {
                Text("\(point.handsPlayed) hand\(point.handsPlayed == 1 ? "" : "s")")
                    .font(.caption2)
            }
        }
        .foregroundStyle(AppTheme.deepestTeal)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(AppTheme.beige))
    }
}
