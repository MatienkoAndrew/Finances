//
//  TransactionFilter.swift
//  Finances
//
//  Общий фильтр операций: период, счёт, категория, метка, валюта покупки.
//  Работает в списке операций и в аналитике по выборке.
//

import Foundation
import SwiftData

struct TransactionFilter: Equatable, Hashable {
    enum Period: String, CaseIterable, Identifiable, Hashable {
        case all
        case thisMonth
        case lastMonth
        case firstHalfOfMonth
        case custom

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return "Всё время"
            case .thisMonth: return "Этот месяц"
            case .lastMonth: return "Прошлый месяц"
            case .firstHalfOfMonth: return "1–15 число"
            case .custom: return "Свой период"
            }
        }
    }

    var period: Period = .all
    var customStart: Date = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
    var customEnd: Date = .now
    var accountID: PersistentIdentifier?
    var categoryName: String?
    var tagName: String?
    /// Валюта покупки: валюта операции, а у оплаты по карте за границей — валюта магазина.
    var currencyCode: String?

    var isActive: Bool {
        period != .all || accountID != nil || categoryName != nil || tagName != nil || currencyCode != nil
    }

    /// Отрезок периода; nil — без ограничения по датам.
    func dateInterval(now: Date = .now) -> DateInterval? {
        let calendar = Calendar.current
        let thisMonth = calendar.dateInterval(of: .month, for: now)

        switch period {
        case .all:
            return nil
        case .thisMonth:
            return thisMonth
        case .lastMonth:
            guard let start = thisMonth?.start,
                  let previous = calendar.date(byAdding: .month, value: -1, to: start) else { return nil }
            return calendar.dateInterval(of: .month, for: previous)
        case .firstHalfOfMonth:
            guard let start = thisMonth?.start,
                  let end = calendar.date(byAdding: .day, value: 15, to: start) else { return nil }
            return DateInterval(start: start, end: end)
        case .custom:
            let start = calendar.startOfDay(for: min(customStart, customEnd))
            let lastDay = calendar.startOfDay(for: max(customStart, customEnd))
            let end = calendar.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay
            return DateInterval(start: start, end: end)
        }
    }

    func matches(_ transaction: Transaction, interval: DateInterval?) -> Bool {
        if let interval, !(transaction.date >= interval.start && transaction.date < interval.end) {
            return false
        }
        if let accountID,
           transaction.fromAccount?.persistentModelID != accountID,
           transaction.toAccount?.persistentModelID != accountID {
            return false
        }
        if let categoryName, CategoryTotalsAccumulator.categoryName(of: transaction) != categoryName {
            return false
        }
        if let tagName, !transaction.hasTag(tagName) {
            return false
        }
        if let currencyCode, Self.purchaseCurrency(of: transaction) != currencyCode {
            return false
        }
        return true
    }

    func matches(_ transaction: Transaction) -> Bool {
        matches(transaction, interval: dateInterval())
    }

    static func purchaseCurrency(of transaction: Transaction) -> String {
        CurrencyDisplay.normalizedCode(from: transaction.foreignCurrencyCode ?? transaction.currencyCode)
    }

    /// «1–15 ноя», «Ноябрь», «3 окт – 12 ноя».
    func periodTitle(now: Date = .now) -> String {
        guard let interval = dateInterval(now: now) else { return Period.all.title }
        let calendar = Calendar.current
        let end = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.start
        if calendar.isDate(interval.start, inSameDayAs: end) {
            return AnalyticsDateFormat.dayMonth.string(from: interval.start)
        }
        if calendar.isDate(interval.start, equalTo: end, toGranularity: .month) {
            return "\(AnalyticsDateFormat.day.string(from: interval.start))–\(AnalyticsDateFormat.dayMonth.string(from: end))"
        }
        return "\(AnalyticsDateFormat.dayMonth.string(from: interval.start)) – \(AnalyticsDateFormat.dayMonth.string(from: end))"
    }
}

/// Итог выборки по правилам аналитики: возвраты уменьшают расходы,
/// переводы между своими счетами не считаются ни доходом, ни расходом.
struct TransactionFilterTotals {
    var count = 0
    var expensesRub = 0.0
    var incomeRub = 0.0

    static func make(
        _ transactions: [Transaction],
        settings: AppSettings?,
        trackedRates: [TrackedExchangeRate],
        folded: FoldedExchangeRateDifferences
    ) -> TransactionFilterTotals {
        var totals = TransactionFilterTotals()
        for transaction in transactions {
            totals.count += 1
            if let rub = AnalyticsSnapshotBuilder.expenseRub(
                for: transaction,
                settings: settings,
                trackedRates: trackedRates,
                folded: folded
            ) {
                totals.expensesRub += rub
            } else if let rub = AnalyticsSnapshotBuilder.incomeRub(
                for: transaction,
                settings: settings,
                trackedRates: trackedRates
            ) {
                totals.incomeRub += rub
            }
        }
        return totals
    }
}
