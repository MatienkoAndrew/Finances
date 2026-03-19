//
//  AnalyticsView.swift
//  Finances
//
//  Created by Андрей Матиенко on 19.03.2026.
//


import SwiftUI
import SwiftData

struct AnalyticsView: View {
    @Query(sort: \Expense.date, order: .reverse)
    private var expenses: [Expense]

    @State private var selectedPeriod: AnalyticsPeriod = .month

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
                    dailySection
                    categorySection
                    merchantSection
                }
                .padding()
            }
            .navigationTitle("Аналитика")
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
                }
            }
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
