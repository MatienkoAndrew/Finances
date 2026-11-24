//
//  AnalyticsPeriodComparison.swift
//  Finances
//
//  «Что изменилось»: сравнение периода с прошлым на одинаковых отрезках
//  и категории, которые сильнее всего объясняют разницу.
//

import Foundation

/// Отрезок, который участвует в сравнении.
struct AnalyticsComparisonRange {
    let start: Date
    let endExclusive: Date
    /// «1–22 ноя», «Окт. 2026».
    let title: String

    func contains(_ date: Date) -> Bool {
        date >= start && date < endExclusive
    }

    var scope: AnalyticsScope {
        let start = start
        let endExclusive = endExclusive
        return AnalyticsScope(
            title: title,
            matches: { $0.date >= start && $0.date < endExclusive },
            containsDate: { $0 >= start && $0 < endExclusive }
        )
    }
}

/// Траты одной категории за отрезок.
struct AnalyticsCategoryPeriodTotal {
    var total: Double = 0
    var count: Int = 0

    /// Средний чек; 0 — покупок не было.
    var averageCheck: Double {
        count > 0 ? total / Double(count) : 0
    }
}

/// Как изменились траты категории между отрезками.
struct AnalyticsCategoryChange: Identifiable {
    var id: String { category }
    let category: String
    let current: AnalyticsCategoryPeriodTotal
    let previous: AnalyticsCategoryPeriodTotal

    var delta: Double { current.total - previous.total }
}

struct AnalyticsPeriodComparison {
    let current: AnalyticsComparisonRange
    let previous: AnalyticsComparisonRange
    /// Текущий период ещё идёт — сравниваются одинаковые начальные отрезки.
    let isPartial: Bool

    let currentTotal: Double
    let previousTotal: Double
    let currentCount: Int
    let previousCount: Int

    /// Все категории с изменением, по убыванию влияния на разницу.
    let changes: [AnalyticsCategoryChange]

    /// Дополнительное условие выборки (фильтр списка операций); nil — все операции.
    var restrict: ((Transaction) -> Bool)? = nil

    /// Операции отрезка для перехода к списку — с учётом фильтра выборки.
    func scope(for range: AnalyticsComparisonRange) -> AnalyticsScope {
        let base = range.scope
        guard let restrict else { return base }
        return AnalyticsScope(
            title: base.title,
            matches: { base.matches($0) && restrict($0) },
            containsDate: base.containsDate
        )
    }

    var delta: Double { currentTotal - previousTotal }

    /// Изменение в долях; nil — в прошлом отрезке трат не было.
    var deltaFraction: Double? {
        previousTotal > 0 ? delta / previousTotal : nil
    }

    /// Три категории, которые сильнее всего повлияли на разницу.
    var topChanges: [AnalyticsCategoryChange] {
        Array(changes.prefix(3))
    }
}

enum AnalyticsPeriodComparisonBuilder {
    static func build(
        transactions: [Transaction],
        scale: AnalyticsTimeScale,
        page: AnalyticsPeriodPage,
        now: Date = .now,
        settings: AppSettings?,
        trackedRates: [TrackedExchangeRate],
        folded: FoldedExchangeRateDifferences,
        restrict: ((Transaction) -> Bool)? = nil
    ) -> AnalyticsPeriodComparison? {
        let index = AnalyticsIndex(
            transactions: AnalyticsSnapshotBuilder.newestFirst(transactions),
            folded: folded,
            settings: settings,
            trackedRates: trackedRates
        )
        return build(index: index, scale: scale, page: page, now: now, restrict: restrict)
    }

    /// Сравнение по готовому индексу: проходит только операции двух отрезков.
    static func build(
        index: AnalyticsIndex,
        scale: AnalyticsTimeScale,
        page: AnalyticsPeriodPage,
        now: Date = .now,
        restrict: ((Transaction) -> Bool)? = nil
    ) -> AnalyticsPeriodComparison? {
        guard let ranges = ranges(scale: scale, page: page, now: now) else { return nil }

        func totals(in range: AnalyticsComparisonRange) -> [String: AnalyticsCategoryPeriodTotal] {
            // По номерам категорий из индекса, а не по строкам на каждой операции.
            var byID = Array(repeating: AnalyticsCategoryPeriodTotal(), count: index.categoryNames.count)
            var touched = Array(repeating: false, count: index.categoryNames.count)
            for i in index.range(from: range.start, to: range.endExclusive) {
                guard let rub = index.expenseRub[i] else { continue }
                if let restrict, !restrict(index.transactions[i]) { continue }
                let id = index.categoryID[i]
                byID[id].total += rub
                byID[id].count += index.isPurchase[i] ? 1 : 0
                touched[id] = true
            }
            var result: [String: AnalyticsCategoryPeriodTotal] = [:]
            for id in byID.indices where touched[id] {
                result[index.categoryNames[id]] = byID[id]
            }
            return result
        }

        let currentTotals = totals(in: ranges.current)
        let previousTotals = totals(in: ranges.previous)

        let categories = Set(currentTotals.keys).union(previousTotals.keys)
        let changes = categories
            .map { category in
                AnalyticsCategoryChange(
                    category: category,
                    current: currentTotals[category] ?? .init(),
                    previous: previousTotals[category] ?? .init()
                )
            }
            .filter { CategoryTotalsAccumulator.isPositive(abs($0.delta)) }
            .sorted { (abs($0.delta), $1.category) > (abs($1.delta), $0.category) }

        let currentTotal = currentTotals.values.reduce(0) { $0 + $1.total }
        let previousTotal = previousTotals.values.reduce(0) { $0 + $1.total }
        guard CategoryTotalsAccumulator.isPositive(currentTotal) || CategoryTotalsAccumulator.isPositive(previousTotal) else {
            return nil
        }

        return AnalyticsPeriodComparison(
            current: ranges.current,
            previous: ranges.previous,
            isPartial: ranges.isPartial,
            currentTotal: currentTotal,
            previousTotal: previousTotal,
            currentCount: currentTotals.values.reduce(0) { $0 + $1.count },
            previousCount: previousTotals.values.reduce(0) { $0 + $1.count },
            changes: changes,
            restrict: restrict
        )
    }

    /// Отрезки сравнения. Завершённый период сравнивается с прошлым целиком,
    /// текущий — одинаковыми начальными отрезками: 1–15 ноября с 1–15 октября.
    static func ranges(
        scale: AnalyticsTimeScale,
        page: AnalyticsPeriodPage,
        now: Date
    ) -> (current: AnalyticsComparisonRange, previous: AnalyticsComparisonRange, isPartial: Bool)? {
        let calendar = Calendar.current
        guard now >= page.startDate,
              let previousAnchor = calendar.date(byAdding: scale.calendarComponent, value: -1, to: page.startDate)
        else { return nil }
        let previousPage = AnalyticsSnapshotBuilder.makePage(for: scale, anchorDate: previousAnchor)

        guard now < page.endDateExclusive else {
            return (
                AnalyticsComparisonRange(start: page.startDate, endExclusive: page.endDateExclusive, title: page.displayTitle),
                AnalyticsComparisonRange(start: previousPage.startDate, endExclusive: previousPage.endDateExclusive, title: previousPage.displayTitle),
                false
            )
        }

        // Текущий отрезок — до конца сегодняшнего дня.
        let today = calendar.startOfDay(for: now)
        let currentEnd = min(calendar.date(byAdding: .day, value: 1, to: today) ?? now, page.endDateExclusive)

        let previousEndUnclamped: Date?
        switch scale {
        case .month:
            // Столько же дней от начала: у короткого месяца отрезок упрётся в его конец.
            let days = calendar.dateComponents([.day], from: page.startDate, to: currentEnd).day ?? 0
            previousEndUnclamped = calendar.date(byAdding: .day, value: days, to: previousPage.startDate)
        case .year:
            previousEndUnclamped = calendar.date(byAdding: .year, value: -1, to: currentEnd)
        }
        let previousEnd = min(previousEndUnclamped ?? previousPage.endDateExclusive, previousPage.endDateExclusive)

        return (
            AnalyticsComparisonRange(start: page.startDate, endExclusive: currentEnd, title: rangeTitle(page.startDate, currentEnd)),
            AnalyticsComparisonRange(start: previousPage.startDate, endExclusive: previousEnd, title: rangeTitle(previousPage.startDate, previousEnd)),
            true
        )
    }

    /// «1–22 ноя», «28 окт – 3 ноя», «1 янв – 22 ноя».
    private static func rangeTitle(_ start: Date, _ endExclusive: Date) -> String {
        let calendar = Calendar.current
        let end = calendar.date(byAdding: .day, value: -1, to: endExclusive) ?? start
        let sameMonth = calendar.isDate(start, equalTo: end, toGranularity: .month)

        if calendar.isDate(start, inSameDayAs: end) {
            return AnalyticsDateFormat.dayMonth.string(from: start)
        }
        if sameMonth {
            return "\(AnalyticsDateFormat.day.string(from: start))–\(AnalyticsDateFormat.dayMonth.string(from: end))"
        }
        return "\(AnalyticsDateFormat.dayMonth.string(from: start)) – \(AnalyticsDateFormat.dayMonth.string(from: end))"
    }
}

extension AnalyticsTimeScale {
    /// Шаг календаря, на который листается страница этого масштаба.
    var calendarComponent: Calendar.Component {
        switch self {
        case .month: return .month
        case .year: return .year
        }
    }
}
