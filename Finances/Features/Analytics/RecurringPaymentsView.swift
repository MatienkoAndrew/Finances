//
//  RecurringPaymentsView.swift
//  Finances
//
//  Обзор регулярных платежей: сумма в пересчёте на месяц, доля в расходах,
//  изменения цены и подсказки из «Подписок и связи».
//

import SwiftUI
import SwiftData

struct RecurringPaymentsView: View {
    @Environment(\.modelContext) private var modelContext

    @AllTransactions
    private var transactions: [Transaction]

    @Environment(\.allTransactionsSnapshot) private var transactionsSnapshot

    @Query(sort: \ExpenseCategoryItem.name, order: .forward)
    private var categories: [ExpenseCategoryItem]

    @Query(sort: \TrackedExchangeRate.code, order: .forward)
    private var trackedRates: [TrackedExchangeRate]

    @Query
    private var settingsList: [AppSettings]

    var body: some View {
        let overview = RecurringPaymentsOverview.make(
            transactions: transactions,
            settings: settingsList.first,
            trackedRates: trackedRates,
            folded: FoldedDifferencesCache.current(transactionsSnapshot)
        )

        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("В МЕСЯЦ")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(TagFormatting.rub(overview.monthlyTotalRub))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    if let share = overview.shareOfExpenses {
                        Text("\(share.formatted(.percent.precision(.fractionLength(0)))) средних расходов за месяц")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            } footer: {
                Text("Годовые и недельные платежи пересчитаны на месяц по последнему списанию. Подписки, которые давно не списывались, в сумму не входят.")
            }

            if overview.series.isEmpty {
                Section {
                    Text("Отметь покупку регулярным платежом в её карточке — или выбери из подсказок ниже.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Подписки") {
                    ForEach(overview.series) { series in
                        NavigationLink {
                            RecurringSeriesView(seriesID: series.id)
                        } label: {
                            seriesRow(series)
                        }
                    }
                }
            }

            if !overview.suggestions.isEmpty {
                Section {
                    ForEach(overview.suggestions) { suggestion in
                        suggestionRow(suggestion)
                    }
                } header: {
                    Text("Похоже на регулярные")
                } footer: {
                    Text("Из категории «\(RecurringPaymentsOverview.subscriptionsCategory)»: списания хотя бы в двух месяцах.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Регулярные платежи")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func seriesRow(_ series: RecurringSeries) -> some View {
        HStack(spacing: 12) {
            AnalyticsCategoryIcon(category: CategoryLookup.findCategory(named: series.categoryName, in: categories))

            VStack(alignment: .leading, spacing: 2) {
                Text(series.title)
                    .lineLimit(1)
                Text(subtitle(series))
                    .font(.caption)
                    .foregroundStyle(series.looksStopped ? Color.orange : Color.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(TagFormatting.rub(series.monthlyRub))
                    .fontWeight(.semibold)
                    .monospacedDigit()
                Text("в месяц")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func subtitle(_ series: RecurringSeries) -> String {
        var parts = ["\(RecurringFormat.amount(series.lastAmount, series.currencyCode)) \(series.period.shortTitle)"]
        if let change = series.priceChanges.first {
            parts.append(change.newAmount > change.oldAmount ? "подорожала" : "подешевела")
        }
        if series.looksStopped {
            parts.append("давно не списывалась")
        }
        return parts.joined(separator: " · ")
    }

    private func suggestionRow(_ suggestion: RecurringSuggestion) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.title)
                    .lineLimit(1)
                Text("\(RecurringFormat.amount(RecurringPaymentsOverview.purchaseAmount(of: suggestion.lastCharge), suggestion.currencyCode)) · \(suggestion.monthsCount) мес.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Отметить") {
                RecurringPaymentsOverview.setPeriod(.monthly, forSeriesOf: suggestion.lastCharge, in: transactions)
                try? modelContext.save()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}

/// Одна подписка: период, списания и изменения цены в исходной валюте.
struct RecurringSeriesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let seriesID: String

    @AllTransactions
    private var transactions: [Transaction]

    @Environment(\.allTransactionsSnapshot) private var transactionsSnapshot

    @Query(sort: \TrackedExchangeRate.code, order: .forward)
    private var trackedRates: [TrackedExchangeRate]

    @Query
    private var settingsList: [AppSettings]

    var body: some View {
        let overview = RecurringPaymentsOverview.make(
            transactions: transactions,
            settings: settingsList.first,
            trackedRates: trackedRates,
            folded: FoldedDifferencesCache.current(transactionsSnapshot)
        )

        if let series = overview.series.first(where: { $0.id == seriesID }) {
            List {
                Section {
                    LabeledContent("Последнее списание", value: RecurringFormat.amount(series.lastAmount, series.currencyCode))
                    LabeledContent("В рублях", value: TagFormatting.rub(series.lastRub))
                    LabeledContent("В пересчёте на месяц", value: TagFormatting.rub(series.monthlyRub))
                    if let next = series.nextExpectedDate {
                        LabeledContent("Следующее", value: next.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "ru_RU"))))
                    }
                    Picker("Периодичность", selection: Binding(
                        get: { series.period },
                        set: { newValue in
                            if let last = series.charges.first {
                                RecurringPaymentsOverview.setPeriod(newValue, forSeriesOf: last, in: transactions)
                                try? modelContext.save()
                            }
                        }
                    )) {
                        ForEach(RecurringPeriod.allCases) { period in
                            Text(period.title).tag(period)
                        }
                    }
                }
                .monospacedDigit()

                if !series.priceChanges.isEmpty {
                    Section("Изменения цены") {
                        ForEach(series.priceChanges) { change in
                            HStack {
                                Text(change.date.formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "ru_RU"))))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(RecurringFormat.amount(change.oldAmount, series.currencyCode)) → \(RecurringFormat.amount(change.newAmount, series.currencyCode))")
                                    .foregroundStyle(change.newAmount > change.oldAmount ? Color.red : Color.green)
                                    .monospacedDigit()
                            }
                        }
                    }
                }

                Section("Списания") {
                    ForEach(series.charges) { charge in
                        NavigationLink {
                            TransactionDetailView(transaction: charge)
                        } label: {
                            HStack {
                                Text(charge.date.formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "ru_RU"))))
                                Spacer()
                                Text(RecurringFormat.amount(RecurringPaymentsOverview.purchaseAmount(of: charge), series.currencyCode))
                                    .monospacedDigit()
                            }
                        }
                    }
                }

                Section {
                    Button("Не регулярный платёж", role: .destructive) {
                        if let last = series.charges.first {
                            RecurringPaymentsOverview.setPeriod(nil, forSeriesOf: last, in: transactions)
                            try? modelContext.save()
                        }
                        dismiss()
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(series.title)
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("Подписка снята", systemImage: "repeat")
        }
    }
}

enum RecurringFormat {
    /// «11,99 $», «2 990 ₸».
    static func amount(_ value: Double, _ currencyCode: String) -> String {
        let number = value.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "ru_RU")))
        return "\(number) \(CurrencyDisplay.symbol(for: currencyCode))"
    }
}
