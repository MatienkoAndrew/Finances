//
//  AnalyticsIndex.swift
//  Finances
//
//  Данные аналитики, подготовленные один раз на ревизию операций и общие
//  для всех экранов: пары «покупка — курсовая разница / возврат», вклад каждой
//  операции в расходы и доходы в рублях, её категория и место — обычными
//  массивами, плюс итоги расходов по дням.
//
//  Раньше каждый экран и каждый отчёт заново искал пары и читал поля моделей
//  SwiftData по всей истории (а чтение поля модели — медленное). Теперь отчёт
//  за месяц берёт из индекса только операции своего отрезка, а график и год —
//  готовые итоги по дням.
//

import Foundation
import SwiftData

@MainActor
final class AnalyticsIndex {
    /// Операции, новые сверху (как их держит `TransactionsStore`).
    let transactions: [Transaction]
    let dates: [Date]
    let folded: FoldedExchangeRateDifferences

    /// Вклад в расходы, ₽ (`AnalyticsSnapshotBuilder.expenseRub`); nil — не расход.
    let expenseRub: [Double?]
    /// Доход, ₽ (`AnalyticsSnapshotBuilder.incomeRub`); nil — не доход.
    let incomeRub: [Double?]
    /// Покупка (расход или оплата переводом) — считается в числе покупок.
    let isPurchase: [Bool]
    let category: [String]
    let subcategory: [String?]
    let merchant: [String]

    // Те же категория, пара «категория + подкатегория» и место — номерами:
    // отчёт складывает суммы в массивы, а не в словари со строковыми ключами.
    // У операций, которые не расходы, номер -1.
    let categoryID: [Int]
    let categoryNames: [String]
    let subcategoryID: [Int]
    /// Номер категории и подкатегория для каждого номера пары.
    let subcategoryKeys: [(category: Int, name: String?)]
    let merchantID: [Int]
    let merchantNames: [String]

    /// Начало дня → расходы за день, ₽.
    let dailyExpense: [Date: Double]
    /// Самый ранний день с расходом — левая граница ленты графика.
    let earliestExpenseDate: Date?

    init(
        transactions: [Transaction],
        folded: FoldedExchangeRateDifferences,
        settings: AppSettings?,
        trackedRates: [TrackedExchangeRate]
    ) {
        let calendar = Calendar.current
        let count = transactions.count
        var dates: [Date] = []
        var expense: [Double?] = []
        var income: [Double?] = []
        var purchase: [Bool] = []
        var category: [String] = []
        var subcategory: [String?] = []
        var merchant: [String] = []
        dates.reserveCapacity(count)
        expense.reserveCapacity(count)
        income.reserveCapacity(count)
        purchase.reserveCapacity(count)
        category.reserveCapacity(count)
        subcategory.reserveCapacity(count)
        merchant.reserveCapacity(count)

        var daily: [Date: Double] = [:]
        var earliest: Date?

        var categoryID: [Int] = []
        var subcategoryID: [Int] = []
        var merchantID: [Int] = []
        categoryID.reserveCapacity(count)
        subcategoryID.reserveCapacity(count)
        merchantID.reserveCapacity(count)
        var categoryIDs: [String: Int] = [:]
        var categoryNames: [String] = []
        var subcategoryIDs: [String: Int] = [:]
        var subcategoryKeys: [(category: Int, name: String?)] = []
        var merchantIDs: [String: Int] = [:]
        var merchantNames: [String] = []

        for transaction in transactions {
            let date = transaction.date
            dates.append(date)

            let rub = AnalyticsSnapshotBuilder.expenseRub(
                for: transaction,
                settings: settings,
                trackedRates: trackedRates,
                folded: folded
            )
            expense.append(rub)
            income.append(rub == nil
                ? AnalyticsSnapshotBuilder.incomeRub(for: transaction, settings: settings, trackedRates: trackedRates)
                : nil)

            if let rub {
                let categoryName = CategoryTotalsAccumulator.categoryName(of: transaction)
                let subcategoryName = CategoryTotalsAccumulator.subcategoryName(of: transaction)
                let merchantName = AnalyticsSnapshotBuilder.normalizedMerchantName(transaction.details)
                purchase.append(transaction.countsAsPurchaseInAnalytics)
                category.append(categoryName)
                subcategory.append(subcategoryName)
                merchant.append(merchantName)
                daily[calendar.startOfDay(for: date), default: 0] += rub
                earliest = min(earliest ?? date, date)

                let cid: Int
                if let known = categoryIDs[categoryName] {
                    cid = known
                } else {
                    cid = categoryNames.count
                    categoryIDs[categoryName] = cid
                    categoryNames.append(categoryName)
                }
                categoryID.append(cid)

                let subKey = "\(cid)|\(subcategoryName ?? "\u{0}")"
                if let known = subcategoryIDs[subKey] {
                    subcategoryID.append(known)
                } else {
                    subcategoryIDs[subKey] = subcategoryKeys.count
                    subcategoryID.append(subcategoryKeys.count)
                    subcategoryKeys.append((cid, subcategoryName))
                }

                if let known = merchantIDs[merchantName] {
                    merchantID.append(known)
                } else {
                    merchantIDs[merchantName] = merchantNames.count
                    merchantID.append(merchantNames.count)
                    merchantNames.append(merchantName)
                }
            } else {
                // Для доходов и переводов эти поля не нужны — не читаем их из модели.
                purchase.append(false)
                category.append("")
                subcategory.append(nil)
                merchant.append("")
                categoryID.append(-1)
                subcategoryID.append(-1)
                merchantID.append(-1)
            }
        }

        self.transactions = transactions
        self.dates = dates
        self.folded = folded
        expenseRub = expense
        incomeRub = income
        isPurchase = purchase
        self.category = category
        self.subcategory = subcategory
        self.merchant = merchant
        dailyExpense = daily
        earliestExpenseDate = earliest
        self.categoryID = categoryID
        self.categoryNames = categoryNames
        self.subcategoryID = subcategoryID
        self.subcategoryKeys = subcategoryKeys
        self.merchantID = merchantID
        self.merchantNames = merchantNames
    }

    /// Метка → её операции (новые сверху). Считается при первом обращении.
    private var taggedCache: [String: [Transaction]]?

    /// Операции с меткой — без прохода по всей истории на каждый отчёт.
    func tagged(_ name: String) -> [Transaction] {
        if taggedCache == nil {
            var result: [String: [Transaction]] = [:]
            for transaction in transactions {
                for tag in transaction.tagNames ?? [] {
                    result[tag, default: []].append(transaction)
                }
            }
            taggedCache = result
        }
        return taggedCache?[name] ?? []
    }

    /// Индексы операций с датой в [start, endExclusive). Операции идут новыми
    /// сверху, поэтому отрезок находится двумя двоичными поисками.
    func range(from start: Date, to endExclusive: Date) -> Range<Int> {
        // Первая операция раньше конца отрезка.
        let lower = firstIndex { $0 < endExclusive }
        // Первая операция раньше начала отрезка — уже за его пределами.
        let upper = firstIndex { $0 < start }
        return lower..<max(lower, upper)
    }

    /// Первый индекс, для даты которого условие выполнено (даты идут по убыванию).
    private func firstIndex(where predicate: (Date) -> Bool) -> Int {
        var low = 0
        var high = dates.count
        while low < high {
            let mid = (low + high) / 2
            if predicate(dates[mid]) {
                high = mid
            } else {
                low = mid + 1
            }
        }
        return low
    }

    // MARK: - Shared instance

    private struct Key: Equatable {
        let revision: Int
        let count: Int
        let kztPerRub: Double?
        let rates: [String: Double]
    }

    private static var cache: (key: Key, index: AnalyticsIndex)?

    /// Индекс всех операций приложения: строится один раз, пока операции,
    /// курсы и настройки не поменялись.
    static func current(
        _ snapshot: AllTransactionsSnapshot,
        settings: AppSettings?,
        trackedRates: [TrackedExchangeRate]
    ) -> AnalyticsIndex {
        let key = Key(
            revision: snapshot.revision,
            count: snapshot.items.count,
            kztPerRub: settings?.kztPerRub,
            rates: Dictionary(trackedRates.map { ($0.code, $0.rubPerUnit) }, uniquingKeysWith: { first, _ in first })
        )
        if let cache, cache.key == key { return cache.index }

        let index = AnalyticsIndex(
            transactions: snapshot.items,
            folded: FoldedDifferencesCache.current(snapshot),
            settings: settings,
            trackedRates: trackedRates
        )
        cache = (key, index)
        return index
    }
}

/// Пары «покупка — курсовая разница / возврат» по всем операциям — одни на
/// ревизию данных. Нужны и спискам, и аналитике, и деталям операций.
@MainActor
enum FoldedDifferencesCache {
    private static var cache: (revision: Int, count: Int, folded: FoldedExchangeRateDifferences)?

    static func current(_ snapshot: AllTransactionsSnapshot) -> FoldedExchangeRateDifferences {
        if let cache, cache.revision == snapshot.revision, cache.count == snapshot.items.count {
            return cache.folded
        }
        let folded = ExchangeRateDifferenceMatcher.fold(snapshot.items)
        cache = (snapshot.revision, snapshot.items.count, folded)
        return folded
    }
}
