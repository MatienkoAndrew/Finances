//
//  TagAnalyticsBuilder.swift
//  Finances
//
//  Builds an analytics snapshot specifically for a single tag.
//  Unlike the time-mode builder, this one:
//   • Uses the tag's effective period (or the date range of its tagged
//     transactions when the tag has no explicit dates).
//   • Caps the period at "today" so ongoing trips don't show empty future bars.
//   • Picks bin granularity automatically based on the duration:
//        ≤ 14 days → daily
//        15…77 days (~ 2.5 months) → weekly
//        78+ days → monthly
//   • Produces only the bins that actually fall inside the tag period —
//     no padding to a calendar week / month / year.
//

import Foundation

enum TagBinGranularity {
    case daily
    case weekly
    case monthly

    var sectionTitle: String {
        switch self {
        case .daily: return "По дням"
        case .weekly: return "По неделям"
        case .monthly: return "По месяцам"
        }
    }

    var selectedPointTitle: String {
        switch self {
        case .daily: return "ДЕНЬ"
        case .weekly: return "НЕДЕЛЯ"
        case .monthly: return "МЕСЯЦ"
        }
    }
}

enum TagAnalyticsBuilder {

    // MARK: - Public

    /// Returns an effective `[start, endExclusive)` interval for the tag.
    /// Uses the tag's explicit start/end if set, otherwise the min/max date of
    /// the tagged transactions. The end is capped at today so we don't paint
    /// empty future bars for an ongoing trip.
    static func effectivePeriod(
        for tag: TransactionTag,
        taggedTransactions: [Transaction]
    ) -> (start: Date, endExclusive: Date)? {
        let calendar = Calendar.current
        let now = Date()

        let inclusiveStart: Date
        let inclusiveEnd: Date

        if let start = tag.startDate, let end = tag.endDate, start <= end {
            // Расширяем период тега до объединения с датами помеченных транзакций.
            // Это нужно для случая, когда пользователь вручную добавил трату
            // (например, наличкой) с датой вне явного диапазона тега.
            let txDates = taggedTransactions.map(\.date)
            let minTxDate = txDates.min()
            let maxTxDate = txDates.max()
            let effectiveStart = [start, minTxDate].compactMap { $0 }.min() ?? start
            let effectiveEnd   = [end,   maxTxDate].compactMap { $0 }.max() ?? end
            inclusiveStart = calendar.startOfDay(for: effectiveStart)
            inclusiveEnd   = calendar.startOfDay(for: effectiveEnd)
        } else if let minDate = taggedTransactions.map(\.date).min(),
                  let maxDate = taggedTransactions.map(\.date).max() {
            inclusiveStart = calendar.startOfDay(for: minDate)
            inclusiveEnd = calendar.startOfDay(for: maxDate)
        } else {
            return nil
        }

        let today = calendar.startOfDay(for: now)
        let cappedEndInclusive = min(inclusiveEnd, today)

        guard cappedEndInclusive >= inclusiveStart else {
            return nil
        }

        let endExclusive = calendar.date(
            byAdding: .day,
            value: 1,
            to: cappedEndInclusive
        ) ?? cappedEndInclusive

        return (inclusiveStart, endExclusive)
    }

    /// Picks the bin granularity for a tag with the given duration in days.
    static func granularity(durationInDays days: Int) -> TagBinGranularity {
        switch days {
        case ..<15: return .daily
        case 15..<78: return .weekly
        default: return .monthly
        }
    }

    /// Convenience wrapper around `effectivePeriod` + `granularity`.
    static func granularity(
        for tag: TransactionTag,
        taggedTransactions: [Transaction]
    ) -> TagBinGranularity? {
        guard let period = effectivePeriod(for: tag, taggedTransactions: taggedTransactions) else {
            return nil
        }
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: period.start, to: period.endExclusive).day ?? 1
        return granularity(durationInDays: max(days, 1))
    }

    /// Builds a full `AnalyticsSnapshot` for the given tag.
    static func buildSnapshot(
        tag: TransactionTag,
        transactions: [Transaction],
        settings: AppSettings?,
        trackedRates: [TrackedExchangeRate]
    ) -> AnalyticsSnapshot {
        let calendar = Calendar.current
        let tagged = transactions.filter { $0.hasTag(tag.name) }

        guard let period = effectivePeriod(for: tag, taggedTransactions: tagged) else {
            let page = AnalyticsPeriodPage(
                startDate: .now,
                endDateExclusive: .now,
                displayTitle: tag.name,
                binCount: 0
            )
            return AnalyticsSnapshot.empty(for: page)
        }

        let durationDays = max(
            calendar.dateComponents([.day], from: period.start, to: period.endExclusive).day ?? 1,
            1
        )
        let chosenGranularity = granularity(durationInDays: durationDays)
        let bins = makeBins(
            start: period.start,
            endExclusive: period.endExclusive,
            granularity: chosenGranularity,
            calendar: calendar
        )

        var chartTotals = Array(repeating: 0.0, count: bins.count)
        var totalExpensesRub = 0.0
        var totalIncomeRub = 0.0
        var expenseCount = 0
        var incomeCount = 0
        var categoryMap: [String: Double] = [:]
        var categoryCountMap: [String: Int] = [:]
        var merchantMap: [String: Double] = [:]
        var merchantByCategory: [String: [String: Double]] = [:]

        for transaction in tagged {
            // Только транзакции внутри эффективного периода метки.
            guard transaction.date >= period.start && transaction.date < period.endExclusive else {
                continue
            }
            guard let rub = TransactionRubConverter.displayRubAmount(
                for: transaction,
                settings: settings,
                trackedRates: trackedRates
            ) else { continue }

            switch transaction.kind {
            case .expense:
                totalExpensesRub += rub
                expenseCount += 1

                if let idx = bins.firstIndex(where: {
                    transaction.date >= $0.start && transaction.date < $0.endExclusive
                }) {
                    chartTotals[idx] += rub
                }

                let category = transaction.categoryName ?? "Без категории"
                categoryMap[category, default: 0] += rub
                categoryCountMap[category, default: 0] += 1

                let merchant = normalizedMerchantName(transaction.details)
                merchantMap[merchant, default: 0] += rub
                merchantByCategory[category, default: [:]][merchant, default: 0] += rub

            case .income:
                totalIncomeRub += rub
                incomeCount += 1

            case .transfer:
                break
            }
        }

        let chartPoints = bins.enumerated().map { index, bin in
            AnalyticsChartPoint(
                id: "tag-\(tag.name)-\(bin.start.timeIntervalSince1970)",
                index: index,
                date: bin.start,
                axisLabel: bin.axisLabel,
                title: bin.title,
                total: chartTotals[index]
            )
        }

        let lowerTimeTotals = chartPoints.reversed().map {
            AnalyticsTimeTotal(id: $0.id, date: $0.date, title: $0.title, total: $0.total)
        }

        let categoryTotals = categoryMap
            .map { AnalyticsCategoryTotal(category: $0.key, total: $0.value, count: categoryCountMap[$0.key] ?? 0) }
            .sorted { $0.total > $1.total }

        let merchantTotals = Array(
            merchantMap
                .map { AnalyticsMerchantTotal(merchant: $0.key, total: $0.value) }
                .sorted { $0.total > $1.total }
                .prefix(10)
        )

        let topMerchantByCategory = merchantByCategory.mapValues { merchants in
            merchants.max(by: { $0.value < $1.value })?.key ?? ""
        }

        let page = AnalyticsPeriodPage(
            startDate: period.start,
            endDateExclusive: period.endExclusive,
            displayTitle: formattedDateRange(start: period.start, endExclusive: period.endExclusive),
            binCount: bins.count
        )

        return AnalyticsSnapshot(
            page: page,
            chartPoints: chartPoints,
            lowerTimeTotals: lowerTimeTotals,
            totalExpensesRub: totalExpensesRub,
            totalIncomeRub: totalIncomeRub,
            expenseCount: expenseCount,
            incomeCount: incomeCount,
            categoryTotals: categoryTotals,
            merchantTotals: merchantTotals,
            topMerchantByCategory: topMerchantByCategory,
            effectiveBinCount: max(bins.count, 1)
        )
    }

    // MARK: - Bins

    private struct TagBin {
        let start: Date
        let endExclusive: Date
        let axisLabel: String
        let title: String
    }

    private static func makeBins(
        start: Date,
        endExclusive: Date,
        granularity: TagBinGranularity,
        calendar: Calendar
    ) -> [TagBin] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        var bins: [TagBin] = []

        switch granularity {
        case .daily:
            var current = start
            while current < endExclusive {
                let next = calendar.date(byAdding: .day, value: 1, to: current) ?? endExclusive

                formatter.dateFormat = "d"
                let axis = formatter.string(from: current)
                formatter.dateFormat = "d MMM yyyy"
                let title = formatter.string(from: current)

                bins.append(TagBin(start: current, endExclusive: next, axisLabel: axis, title: title))
                current = next
            }

        case .weekly:
            var current = start
            while current < endExclusive {
                let nextRaw = calendar.date(byAdding: .day, value: 7, to: current) ?? endExclusive
                let next = min(nextRaw, endExclusive)
                let lastDayInBin = calendar.date(byAdding: .day, value: -1, to: next) ?? current

                formatter.dateFormat = "d"
                let axis = formatter.string(from: current)

                formatter.dateFormat = "d MMM"
                let title = "\(formatter.string(from: current))–\(formatter.string(from: lastDayInBin))"

                bins.append(TagBin(start: current, endExclusive: next, axisLabel: axis, title: title))
                current = next
            }

        case .monthly:
            var current = calendar.dateInterval(of: .month, for: start)?.start ?? start
            while current < endExclusive {
                let nextRaw = calendar.date(byAdding: .month, value: 1, to: current) ?? endExclusive
                let next = min(nextRaw, endExclusive)

                formatter.dateFormat = "MMM"
                let axis = formatter.string(from: current).capitalized
                formatter.dateFormat = "LLL yyyy"
                let title = formatter.string(from: current).capitalized

                bins.append(TagBin(start: current, endExclusive: next, axisLabel: axis, title: title))
                current = next
            }
        }

        return bins
    }

    // MARK: - Helpers

    private static func normalizedMerchantName(_ details: String) -> String {
        let uppercased = details.uppercased()
        if uppercased.hasPrefix("GRAB ") { return "GRAB" }
        if uppercased.hasPrefix("PAYOO MCDONALDS") { return "PAYOO MCDONALDS" }
        if uppercased.hasPrefix("OPENAI CHATGPT SUBSCR") { return "OPENAI CHATGPT SUBSCR" }
        if uppercased.hasPrefix("APPLE.COM BILL") { return "APPLE.COM BILL" }
        if uppercased.hasPrefix("VNPAY 43 FACTORY") { return "VNPAY 43 FACTORY" }
        if uppercased.hasPrefix("VNPAY XLIII COFFEE") { return "VNPAY XLIII COFFEE" }
        return uppercased
    }

    private static func formattedDateRange(start: Date, endExclusive: Date) -> String {
        let calendar = Calendar.current
        let endInclusive = calendar.date(byAdding: .day, value: -1, to: endExclusive) ?? endExclusive
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")

        let startMonth = calendar.component(.month, from: start)
        let endMonth = calendar.component(.month, from: endInclusive)
        let startYear = calendar.component(.year, from: start)
        let endYear = calendar.component(.year, from: endInclusive)

        if calendar.isDate(start, inSameDayAs: endInclusive) {
            formatter.dateFormat = "d MMM yyyy"
            return formatter.string(from: start)
        }

        if startYear == endYear && startMonth == endMonth {
            formatter.dateFormat = "d"
            let startDay = formatter.string(from: start)
            formatter.dateFormat = "d MMM yyyy"
            return "\(startDay)–\(formatter.string(from: endInclusive))"
        }

        if startYear == endYear {
            formatter.dateFormat = "d MMM"
            let startPart = formatter.string(from: start)
            formatter.dateFormat = "d MMM yyyy"
            return "\(startPart)–\(formatter.string(from: endInclusive))"
        }

        formatter.dateFormat = "d MMM yyyy"
        return "\(formatter.string(from: start))–\(formatter.string(from: endInclusive))"
    }
}
