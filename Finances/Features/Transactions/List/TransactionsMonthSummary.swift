//
//  TransactionsMonthSummary.swift
//  Finances
//
//  Сводка текущего месяца над списком операций: сколько потрачено, тренд
//  к прошлому месяцу, доход и остаток. Цифры — те же, что в аналитике.
//

import SwiftUI

struct TransactionsMonthSummary: View {
    let current: AnalyticsSnapshot
    let previous: AnalyticsSnapshot

    /// Тренд как в аналитике: средние траты в день к прошлому месяцу.
    private var trendDelta: Double? {
        // Пока в месяце нет трат, «−100 %» ничего не говорит.
        guard current.totalExpensesRub > 0, previous.averageExpensePerBin > 0 else { return nil }
        let delta = (current.averageExpensePerBin - previous.averageExpensePerBin) / previous.averageExpensePerBin
        return abs(delta) >= 0.005 ? delta : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(Self.monthTitle(current.page.startDate))
                    .font(.headline)

                Spacer()

                HStack(spacing: 4) {
                    Text("Аналитика")
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("ПОТРАЧЕНО")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(TagFormatting.rub(current.totalExpensesRub))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText(value: current.totalExpensesRub))

                if let trendDelta {
                    HStack(spacing: 6) {
                        AnalyticsTrendBadge(delta: trendDelta)
                        Text("в день к прошлому месяцу")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            }

            HStack(spacing: 8) {
                AnalyticsMetricTile(
                    value: current.totalIncomeRub > 0 ? "+" + TagFormatting.rub(current.totalIncomeRub) : "—",
                    title: "доход"
                )
                AnalyticsMetricTile(
                    value: signedRub(current.netFlowRub),
                    title: "остаток"
                )
                AnalyticsMetricTile(
                    value: "\(current.expenseCount)",
                    title: operationsWord(current.expenseCount)
                )
            }
        }
        .padding(16)
        .background(AnalyticsHeroBackground(color: .red))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Открывает аналитику за месяц")
    }

    /// «Ноябрь 2026» — полное название месяца, без сокращения.
    private static func monthTitle(_ date: Date) -> String {
        monthFormatter.string(from: date).capitalized(with: Locale(identifier: "ru_RU"))
    }

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "LLLL yyyy"
        return formatter
    }()

    private func signedRub(_ value: Double) -> String {
        guard value.rounded() != 0 else { return TagFormatting.rub(0) }
        return (value > 0 ? "+" : "−") + TagFormatting.rub(abs(value))
    }

    private func operationsWord(_ count: Int) -> String {
        let mod10 = count % 10
        let mod100 = count % 100
        if mod10 == 1 && mod100 != 11 { return "покупка" }
        if (2...4).contains(mod10) && !(12...14).contains(mod100) { return "покупки" }
        return "покупок"
    }
}
