//
//  RecurringPayments.swift
//  Finances
//
//  Регулярные платежи: подтверждённые вручную подписки с суммой в пересчёте
//  на месяц и изменениями цены в исходной валюте.
//

import Foundation

/// Одна подписка — все покупки того же магазина в той же валюте.
struct RecurringSeries: Identifiable {
    struct PriceChange: Identifiable {
        var id: Date { date }
        let date: Date
        let oldAmount: Double
        let newAmount: Double
    }

    /// Ключ: магазин + валюта покупки.
    let id: String
    let merchantKey: String
    let currencyCode: String
    let period: RecurringPeriod
    let title: String
    let categoryName: String?
    /// Списания, новые сверху.
    let charges: [Transaction]
    /// Последнее списание в валюте покупки.
    let lastAmount: Double
    let lastRub: Double
    let lastDate: Date
    let priceChanges: [PriceChange]

    var monthlyRub: Double { lastRub * period.monthlyFactor }

    var nextExpectedDate: Date? {
        let step = period.calendarStep
        return Calendar.current.date(byAdding: step.component, value: step.value, to: lastDate)
    }

    /// Пора бы списаться, а списания нет: прошло больше полутора периодов.
    var looksStopped: Bool {
        guard let next = nextExpectedDate else { return false }
        let grace = next.timeIntervalSince(lastDate) / 2
        return Date.now.timeIntervalSince(next) > grace
    }
}

/// Похоже на подписку, но не отмечено: магазин из «Подписок и связи»
/// со списаниями в разных месяцах.
struct RecurringSuggestion: Identifiable {
    var id: String { merchantKey + "|" + currencyCode }
    let merchantKey: String
    let currencyCode: String
    let title: String
    let monthsCount: Int
    let lastCharge: Transaction
}

struct RecurringPaymentsOverview {
    static let subscriptionsCategory = "Подписки и связь"

    let series: [RecurringSeries]
    let suggestions: [RecurringSuggestion]
    /// Средние расходы в месяц за три последних полных месяца.
    let averageMonthlyExpensesRub: Double

    var monthlyTotalRub: Double {
        series.filter { !$0.looksStopped }.reduce(0) { $0 + $1.monthlyRub }
    }

    /// Какая часть месячных расходов повторяется; nil — не с чем сравнить.
    var shareOfExpenses: Double? {
        averageMonthlyExpensesRub > 0 ? monthlyTotalRub / averageMonthlyExpensesRub : nil
    }

    static func seriesKey(merchantKey: String, currencyCode: String) -> String {
        merchantKey + "|" + currencyCode
    }

    static func seriesKey(of transaction: Transaction) -> String {
        seriesKey(
            merchantKey: ExchangeRateDifferenceMatcher.merchantKey(transaction.details),
            currencyCode: purchaseCurrency(of: transaction)
        )
    }

    /// Валюта, в которой выставлен счёт: у оплаты картой за границей — валюта магазина.
    static func purchaseCurrency(of transaction: Transaction) -> String {
        CurrencyDisplay.normalizedCode(from: transaction.foreignCurrencyCode ?? transaction.currencyCode)
    }

    static func purchaseAmount(of transaction: Transaction) -> Double {
        transaction.foreignAmount ?? transaction.amount
    }

    static func make(
        transactions: [Transaction],
        settings: AppSettings?,
        trackedRates: [TrackedExchangeRate],
        folded: FoldedExchangeRateDifferences,
        now: Date = .now
    ) -> RecurringPaymentsOverview {
        let purchases = transactions.filter(\.countsAsPurchaseInAnalytics)

        var periods: [String: RecurringPeriod] = [:]
        for transaction in purchases.sorted(by: { $0.date > $1.date }) {
            guard let period = transaction.recurringPeriodRaw.flatMap(RecurringPeriod.init(rawValue:)) else { continue }
            let key = seriesKey(of: transaction)
            // Отметка на самой свежей покупке важнее старых.
            if periods[key] == nil { periods[key] = period }
        }

        let grouped = Dictionary(grouping: purchases, by: seriesKey(of:))

        let series: [RecurringSeries] = periods.compactMap { key, period in
            let charges = (grouped[key] ?? []).sorted { $0.date > $1.date }
            guard let last = charges.first else { return nil }

            let rub = AnalyticsSnapshotBuilder.expenseRub(
                for: last,
                settings: settings,
                trackedRates: trackedRates,
                folded: folded
            ) ?? 0

            // Изменения цены — по возрастанию дат, в исходной валюте.
            var changes: [RecurringSeries.PriceChange] = []
            let chronological = charges.reversed().map { ($0.date, purchaseAmount(of: $0)) }
            for (previous, current) in zip(chronological, chronological.dropFirst()) {
                let base = max(abs(previous.1), 0.01)
                if abs(current.1 - previous.1) / base > 0.005 {
                    changes.append(.init(date: current.0, oldAmount: previous.1, newAmount: current.1))
                }
            }

            return RecurringSeries(
                id: key,
                merchantKey: ExchangeRateDifferenceMatcher.merchantKey(last.details),
                currencyCode: purchaseCurrency(of: last),
                period: period,
                title: last.walletMerchant ?? last.details,
                categoryName: last.categoryName,
                charges: charges,
                lastAmount: purchaseAmount(of: last),
                lastRub: rub,
                lastDate: last.date,
                priceChanges: changes.reversed()
            )
        }
        .sorted { $0.monthlyRub > $1.monthlyRub }

        // Подсказки: подписки без отметки, со списаниями хотя бы в двух месяцах.
        let calendar = Calendar.current
        let suggestions: [RecurringSuggestion] = grouped.compactMap { key, charges in
            guard periods[key] == nil,
                  charges.contains(where: { $0.categoryName == subscriptionsCategory }) else { return nil }
            let months = Set(charges.compactMap { calendar.dateInterval(of: .month, for: $0.date)?.start })
            guard months.count >= 2, let last = charges.max(by: { $0.date < $1.date }) else { return nil }
            return RecurringSuggestion(
                merchantKey: ExchangeRateDifferenceMatcher.merchantKey(last.details),
                currencyCode: purchaseCurrency(of: last),
                title: last.walletMerchant ?? last.details,
                monthsCount: months.count,
                lastCharge: last
            )
        }
        .sorted { $0.lastCharge.date > $1.lastCharge.date }

        // Средние траты в месяц — три последних полных месяца.
        var average = 0.0
        if let thisMonth = calendar.dateInterval(of: .month, for: now)?.start,
           let start = calendar.date(byAdding: .month, value: -3, to: thisMonth) {
            let total = transactions
                .filter { $0.date >= start && $0.date < thisMonth }
                .compactMap { AnalyticsSnapshotBuilder.expenseRub(for: $0, settings: settings, trackedRates: trackedRates, folded: folded) }
                .reduce(0, +)
            average = total / 3
        }

        return RecurringPaymentsOverview(series: series, suggestions: suggestions, averageMonthlyExpensesRub: average)
    }

    /// Отметить (или снять отметку) все покупки подписки, чтобы отметка не зависела от одной операции.
    static func setPeriod(_ period: RecurringPeriod?, forSeriesOf transaction: Transaction, in transactions: [Transaction]) {
        let key = seriesKey(of: transaction)
        // Уже отмеченные покупки подписки получают то же значение — иначе старая
        // отметка вернула бы подписку или её прежний период.
        for member in transactions where member.recurringPeriodRaw != nil && seriesKey(of: member) == key {
            member.recurringPeriodRaw = period?.rawValue
        }
        transaction.recurringPeriodRaw = period?.rawValue
    }
}
