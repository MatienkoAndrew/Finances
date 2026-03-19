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

                    categorySection
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