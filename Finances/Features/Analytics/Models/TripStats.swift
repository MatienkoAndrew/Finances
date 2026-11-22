//
//  TripStats.swift
//  Finances
//
//  Цифры поездки (метки): полная стоимость вместе с заранее купленными
//  билетами и траты в день только за дни пребывания.
//

import Foundation

struct TripStats {
    /// Дни пребывания: даты метки (до сегодня), а без них — даты её операций.
    let stayStart: Date
    let stayEndExclusive: Date
    let stayDays: Int

    /// Вся стоимость поездки, включая билеты и брони, купленные заранее.
    let totalRub: Double
    /// Потрачено в дни пребывания.
    let onSiteRub: Double
    /// Куплено до начала поездки (билеты, жильё).
    let beforeRub: Double
    /// После окончания (поздние списания, возвраты).
    let afterRub: Double
    let purchaseCount: Int

    /// Категории по полной стоимости, по убыванию.
    let categories: [AnalyticsCategoryTotal]

    var perDayOnSite: Double {
        stayDays > 0 ? onSiteRub / Double(stayDays) : 0
    }

    static func make(
        tag: TransactionTag,
        transactions: [Transaction],
        settings: AppSettings?,
        trackedRates: [TrackedExchangeRate],
        folded: FoldedExchangeRateDifferences
    ) -> TripStats? {
        let calendar = Calendar.current
        let tagged = transactions.filter { $0.hasTag(tag.name) }
        guard let effective = TagAnalyticsBuilder.effectivePeriod(for: tag, taggedTransactions: tagged) else { return nil }

        let today = calendar.startOfDay(for: .now)
        let stayStart: Date
        let stayEndExclusive: Date
        if let start = tag.startDate, let end = tag.endDate, start <= end {
            stayStart = calendar.startOfDay(for: start)
            let lastDay = min(calendar.startOfDay(for: end), today)
            stayEndExclusive = max(calendar.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay, stayStart)
        } else {
            stayStart = effective.start
            stayEndExclusive = effective.endExclusive
        }
        let stayDays = max(calendar.dateComponents([.day], from: stayStart, to: stayEndExclusive).day ?? 0, 0)

        var total = 0.0
        var onSite = 0.0
        var before = 0.0
        var after = 0.0
        var count = 0
        var categories = CategoryTotalsAccumulator()

        for transaction in tagged where transaction.date >= effective.start && transaction.date < effective.endExclusive {
            guard let rub = AnalyticsSnapshotBuilder.expenseRub(
                for: transaction,
                settings: settings,
                trackedRates: trackedRates,
                folded: folded
            ) else { continue }

            let isPurchase = transaction.countsAsPurchaseInAnalytics
            total += rub
            if isPurchase { count += 1 }
            categories.addExpense(transaction, rub: rub, isPurchase: isPurchase)

            if transaction.date < stayStart {
                before += rub
            } else if transaction.date >= stayEndExclusive {
                after += rub
            } else {
                onSite += rub
            }
        }

        return TripStats(
            stayStart: stayStart,
            stayEndExclusive: stayEndExclusive,
            stayDays: stayDays,
            totalRub: total,
            onSiteRub: onSite,
            beforeRub: before,
            afterRub: after,
            purchaseCount: count,
            categories: categories.result()
        )
    }
}
