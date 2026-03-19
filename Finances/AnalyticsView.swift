//
//  AnalyticsView.swift
//  Finances
//
//  Created by Андрей Матиенко on 19.03.2026.
//


import SwiftUI
import SwiftData
import Charts

struct AnalyticsView: View {
    @Query(sort: \Expense.date, order: .reverse)
    private var expenses: [Expense]

    @State private var selectedPeriod: AnalyticsPeriod = .month
    
    @State private var selectedBreakdown: AnalyticsBreakdown = .daily
    
    private var breakdownPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AnalyticsBreakdown.allCases, id: \.self) { breakdown in
                    Button {
                        selectedBreakdown = breakdown
                    } label: {
                        Text(breakdown.rawValue)
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                selectedBreakdown == breakdown
                                ? Color.primary.opacity(0.1)
                                : Color.gray.opacity(0.1)
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var filteredExpenses: [Expense] {
        expenses.filter { selectedPeriod.contains($0.date) }
    }

    private var totalExpenses: Double {
        filteredExpenses
            .filter { $0.amount < 0 }
            .reduce(0) { $0 + abs($1.amount) }
    }

    private var totalIncome: Double {
        filteredExpenses
            .filter { $0.amount > 0 }
            .reduce(0) { $0 + $1.amount }
    }

    private var netFlow: Double {
        totalIncome - totalExpenses
    }

    private var categoryTotals: [(category: String, total: Double)] {
        let grouped = Dictionary(grouping: filteredExpenses.filter { $0.amount < 0 }) { expense in
            expense.category?.title ?? "Без категории"
        }

        return grouped
            .map { key, value in
                let total = value.reduce(0) { $0 + abs($1.amount) }
                return (category: key, total: total)
            }
            .sorted { $0.total > $1.total }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    periodPicker
                    summaryCards
                    chartSection
                    breakdownPicker
                    selectedBreakdownSection
                }
                .padding()
            }
            .navigationTitle("Аналитика")
        }
    }
    
    @ViewBuilder
    private var selectedBreakdownSection: some View {
        switch selectedBreakdown {
        case .daily:
            dailySection

        case .category:
            VStack(spacing: 16) {
                categoryChartSection
                categorySection
            }

        case .merchant:
            merchantSection
        }
    }

    private var periodPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AnalyticsPeriod.allCases, id: \.self) { period in
                    Button {
                        selectedPeriod = period
                    } label: {
                        Text(period.rawValue)
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                selectedPeriod == period
                                ? Color.primary.opacity(0.1)
                                : Color.gray.opacity(0.1)
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var summaryCards: some View {
        VStack(spacing: 12) {
            AnalyticsCardView(
                title: "Расходы",
                value: formattedAmount(totalExpenses),
                systemImage: "arrow.up.circle.fill"
            )

            AnalyticsCardView(
                title: "Пополнения",
                value: formattedAmount(totalIncome),
                systemImage: "arrow.down.circle.fill"
            )

            AnalyticsCardView(
                title: "Итог",
                value: signedFormattedAmount(netFlow),
                systemImage: "equal.circle.fill"
            )
        }
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("По категориям")
                .font(.title3.bold())

            if categoryTotals.isEmpty {
                Text("Нет данных для выбранного периода")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(categoryTotals, id: \.category) { item in
                        NavigationLink {
                            ExpenseListByCategoryView(categoryTitle: item.category)
                        } label: {
                            HStack {
                                Text(item.category)
                                Spacer()
                                Text(formattedAmount(item.total))
                                    .fontWeight(.semibold)
                            }
                            .padding()
                            .background(Color.gray.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
    
    private var dailyExpenseTotals: [(date: Date, total: Double)] {
        let onlyExpenses = filteredExpenses.filter { $0.amount < 0 }

        let grouped = Dictionary(grouping: onlyExpenses) {
            Calendar.current.startOfDay(for: $0.date)
        }

        return grouped
            .map { date, expenses in
                let total = expenses.reduce(0) { $0 + abs($1.amount) }
                return (date: date, total: total)
            }
            .sorted { $0.date > $1.date }
    }
    
    private var dailySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("По дням")
                .font(.title3.bold())

            if dailyExpenseTotals.isEmpty {
                Text("Нет расходов для выбранного периода")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(dailyExpenseTotals, id: \.date) { item in
                        NavigationLink {
                            ExpenseListByDateView(date: item.date)
                        } label: {
                            HStack {
                                Text(formattedShortDate(item.date))
                                Spacer()
                                Text(formattedAmount(item.total))
                                    .fontWeight(.semibold)
                            }
                            .padding()
                            .background(Color.gray.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
    
    private var merchantTotals: [(merchant: String, total: Double)] {
        let onlyExpenses = filteredExpenses.filter { $0.amount < 0 }

        let grouped = Dictionary(grouping: onlyExpenses) { expense in
            normalizedMerchantName(expense.details)
        }

        return grouped
            .map { merchant, expenses in
                let total = expenses.reduce(0) { $0 + abs($1.amount) }
                return (merchant: merchant, total: total)
            }
            .sorted { $0.total > $1.total }
            .prefix(10)
            .map { $0 }
    }
    
    private var merchantSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Топ мест и сервисов")
                .font(.title3.bold())

            if merchantTotals.isEmpty {
                Text("Нет расходов для выбранного периода")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(merchantTotals.enumerated()), id: \.offset) { index, item in
                        NavigationLink {
                            ExpenseListByMerchantView(merchantTitle: item.merchant)
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Text("\(index + 1)")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.merchant)
                                        .font(.body)
                                        .fontWeight(.medium)
                                        .lineLimit(2)

                                    Text(formattedAmount(item.total))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()
                            }
                            .padding()
                            .background(Color.gray.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
    
    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("График расходов")
                .font(.title3.bold())

            if dailyExpenseTotals.isEmpty {
                Text("Нет расходов для выбранного периода")
                    .foregroundStyle(.secondary)
            } else {
                Chart {
                    ForEach(dailyExpenseTotals, id: \.date) { item in
                        BarMark(
                            x: .value("Дата", item.date),
                            y: .value("Расходы", item.total)
                        )
                        .annotation(position: .top, alignment: .center) {
                            if dailyExpenseTotals.count <= 7 {
                                Text(shortAmount(item.total))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(height: 240)
                .chartXAxis {
                    AxisMarks(values: .automatic) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(chartShortDate(date))
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .padding()
                .background(Color.gray.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 18))
            }
        }
    }
    
    private var categoryChartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("График по категориям")
                .font(.title3.bold())

            if categoryTotals.isEmpty {
                Text("Нет данных для выбранного периода")
                    .foregroundStyle(.secondary)
            } else {
                Chart {
                    ForEach(categoryTotals, id: \.category) { item in
                        BarMark(
                            x: .value("Сумма", item.total),
                            y: .value("Категория", item.category)
                        )
                        .annotation(position: .trailing) {
                            Text(shortAmount(item.total))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(height: chartHeightForCategories)
                .chartXAxis {
                    AxisMarks(position: .bottom)
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .padding()
                .background(Color.gray.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 18))
            }
        }
    }
    
    private var chartHeightForCategories: CGFloat {
        let count = max(categoryTotals.count, 1)
        let base = CGFloat(count) * 44
        return min(max(base, 180), 420)
    }
    
    private func chartShortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")

        switch selectedPeriod {
        case .day:
            formatter.dateFormat = "HH:mm"
        case .week, .month:
            formatter.dateFormat = "d MMM"
        case .all:
            formatter.dateFormat = "d MMM"
        }

        return formatter.string(from: date)
    }

    private func shortAmount(_ value: Double) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", value / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "%.0fK", value / 1_000)
        } else {
            return String(format: "%.0f", value)
        }
    }
    
    private func normalizedMerchantName(_ details: String) -> String {
        let uppercased = details.uppercased()

        if uppercased.hasPrefix("GRAB ") {
            return "GRAB"
        }

        if uppercased.hasPrefix("PAYOO MCDONALDS") {
            return "PAYOO MCDONALDS"
        }

        if uppercased.hasPrefix("OPENAI CHATGPT SUBSCR") {
            return "OPENAI CHATGPT SUBSCR"
        }

        if uppercased.hasPrefix("APPLE.COM BILL") {
            return "APPLE.COM BILL"
        }

        if uppercased.hasPrefix("VNPAY 43 FACTORY") {
            return "VNPAY 43 FACTORY"
        }

        if uppercased.hasPrefix("VNPAY XLIII COFFEE") {
            return "VNPAY XLIII COFFEE"
        }

        return uppercased
    }
    
    private func formattedShortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMM yyyy"
        return formatter.string(from: date)
    }

    private func formattedAmount(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.groupingSeparator = " "
        formatter.decimalSeparator = ","

        let number = formatter.string(from: NSNumber(value: value)) ?? "\(value)"
        return "\(number) ₸"
    }

    private func signedFormattedAmount(_ value: Double) -> String {
        let sign = value < 0 ? "-" : "+"
        return "\(sign) \(formattedAmount(abs(value)))"
    }
}
