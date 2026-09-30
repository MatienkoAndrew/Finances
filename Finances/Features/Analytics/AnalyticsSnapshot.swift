//
//  AnalyticsPeriodPage.swift
//  Finances
//
//  Created by Андрей Матиенко on 31.03.2026.
//


import Foundation

struct AnalyticsPeriodPage {
    let startDate: Date
    let endDateExclusive: Date
    let displayTitle: String
    let binCount: Int

    func contains(_ date: Date) -> Bool {
        date >= startDate && date < endDateExclusive
    }
}

struct AnalyticsChartPoint: Identifiable {
    let id: String
    let index: Int
    let date: Date
    let axisLabel: String
    let title: String
    let total: Double
    // Рисовать ли вертикальную линию-разделитель у этой точки.
    var showsGridline: Bool = true
}

struct AnalyticsTimeTotal: Identifiable {
    let id: String
    let date: Date
    let title: String
    let total: Double
}

struct AnalyticsCategoryTotal: Identifiable {
    var id: String { category }
    let category: String
    let total: Double
    let count: Int
}

struct AnalyticsMerchantTotal: Identifiable {
    var id: String { merchant }
    let merchant: String
    let total: Double
}

struct AnalyticsSnapshot {
    let page: AnalyticsPeriodPage
    let chartPoints: [AnalyticsChartPoint]
    let lowerTimeTotals: [AnalyticsTimeTotal]

    let totalExpensesRub: Double
    let totalIncomeRub: Double
    let expenseCount: Int
    let incomeCount: Int

    let categoryTotals: [AnalyticsCategoryTotal]
    let merchantTotals: [AnalyticsMerchantTotal]
    let topMerchantByCategory: [String: String]
    
    let effectiveBinCount: Int

    var averageExpensePerBin: Double {
        guard effectiveBinCount > 0 else { return 0 }
        return totalExpensesRub / Double(effectiveBinCount)
    }

    var netFlowRub: Double {
        totalIncomeRub - totalExpensesRub
    }

    var peakChartPoint: AnalyticsChartPoint? {
        chartPoints.max { $0.total < $1.total }
    }

    static func empty(for page: AnalyticsPeriodPage) -> AnalyticsSnapshot {
        AnalyticsSnapshot(
            page: page,
            chartPoints: [],
            lowerTimeTotals: [],
            totalExpensesRub: 0,
            totalIncomeRub: 0,
            expenseCount: 0,
            incomeCount: 0,
            categoryTotals: [],
            merchantTotals: [],
            topMerchantByCategory: [:],
            effectiveBinCount: 0
        )
    }
}

enum AnalyticsSnapshotBuilder {
    static func build(
        transactions: [Transaction],
        scale: AnalyticsTimeScale,
        anchorDate: Date,
        settings: AppSettings?,
        trackedRates: [TrackedExchangeRate]
    ) -> AnalyticsSnapshot {
        let page = makePage(for: scale, anchorDate: anchorDate)
        let filtered = transactions.filter { page.contains($0.date) }

        let bins = makeBins(for: scale, page: page)

        var chartTotals = Array(repeating: 0.0, count: bins.count)
        var totalExpensesRub = 0.0
        var totalIncomeRub = 0.0
        var expenseCount = 0
        var incomeCount = 0

        var categoryMap: [String: Double] = [:]
        var categoryCountMap: [String: Int] = [:]
        var merchantMap: [String: Double] = [:]
        var merchantByCategory: [String: [String: Double]] = [:]

        let calendar = Calendar.current

        for transaction in filtered {
            guard let rub = TransactionRubConverter.displayRubAmount(
                for: transaction,
                settings: settings,
                trackedRates: trackedRates
            ) else {
                continue
            }

            switch transaction.kind {
            case .expense:
                totalExpensesRub += rub
                expenseCount += 1

                if let binIndex = binIndexForDate(transaction.date, scale: scale, page: page, calendar: calendar) {
                    chartTotals[binIndex] += rub
                }

                let category = transaction.categoryName ?? "Без категории"
                categoryMap[category, default: 0] += rub
                categoryCountMap[category, default: 0] += 1

                let merchant = normalizedMerchantName(transaction.details)
                merchantMap[merchant, default: 0] += rub
                merchantByCategory[category, default: [:]][merchant, default: 0] += rub

            case .income where transaction.reducesExpensesInAnalytics:
                // Курсовая разница «в плюс» — возврат части покупки: уменьшает расходы,
                // но отдельной операцией в счётчиках не считается.
                totalExpensesRub -= rub

                if let binIndex = binIndexForDate(transaction.date, scale: scale, page: page, calendar: calendar) {
                    chartTotals[binIndex] -= rub
                }

                let category = transaction.categoryName ?? "Без категории"
                categoryMap[category, default: 0] -= rub

                let merchant = normalizedMerchantName(transaction.details)
                merchantMap[merchant, default: 0] -= rub
                merchantByCategory[category, default: [:]][merchant, default: 0] -= rub

            case .income:
                totalIncomeRub += rub
                incomeCount += 1

            case .transfer:
                break
            }
        }

        let chartPoints = bins.enumerated().map { index, bin in
            AnalyticsChartPoint(
                id: "\(scale.rawValue)-\(bin.date.timeIntervalSince1970)",
                index: index,
                date: bin.date,
                axisLabel: bin.axisLabel,
                title: bin.title,
                total: chartTotals[index],
                showsGridline: bin.showsGridline
            )
        }

        // Вычисляем последнюю релевантную дату для фильтрации
        let now = Date()
        let lastRelevantDate: Date
        
        if let lastTransactionDate = filtered.map({ $0.date }).max() {
            // Используем последнюю транзакцию или текущую дату, в зависимости от того, что раньше
            lastRelevantDate = min(lastTransactionDate, now)
        } else {
            // Если нет транзакций, используем текущую дату
            lastRelevantDate = now
        }
        
        // Фильтруем chartPoints: показываем только те, которые не в будущем
        let filteredChartPoints = chartPoints.filter { $0.date <= lastRelevantDate }
        
        let lowerTimeTotals = filteredChartPoints
            .reversed()
            .map {
                AnalyticsTimeTotal(
                    id: $0.id,
                    date: $0.date,
                    title: $0.title,
                    total: $0.total
                )
            }

        // Вычисляем эффективное количество бинов для расчета среднего
        let effectiveBinCount: Int
        switch scale {
        case .week, .month:
            // Для недели и месяца считаем только дни до текущей даты (включительно)
            let startOfDay = calendar.startOfDay(for: page.startDate)
            let currentDay = calendar.startOfDay(for: min(now, page.endDateExclusive))
            // +1 потому что нужно включить текущий день
            let daysPassed = calendar.dateComponents([.day], from: startOfDay, to: currentDay).day ?? 0
            effectiveBinCount = max(daysPassed + 1, 1) // +1 для включения текущего дня
            
        case .year:
            // Для года считаем только месяцы до текущего (включительно)
            let startYear = calendar.component(.year, from: page.startDate)
            let startMonth = calendar.component(.month, from: page.startDate)
            let currentYear = calendar.component(.year, from: now)
            let currentMonth = calendar.component(.month, from: now)
            
            if currentYear > startYear {
                effectiveBinCount = 12
            } else if currentYear == startYear {
                effectiveBinCount = max(currentMonth - startMonth + 1, 1)
            } else {
                effectiveBinCount = 1
            }
        }

        let categoryTotals = categoryMap
            .map { AnalyticsCategoryTotal(category: $0.key, total: $0.value, count: categoryCountMap[$0.key] ?? 0) }
            .sorted { $0.total > $1.total }

        let merchantTotals = merchantMap
            .map { AnalyticsMerchantTotal(merchant: $0.key, total: $0.value) }
            .sorted { $0.total > $1.total }
            .prefix(10)
            .map { $0 }

        let topMerchantByCategory = merchantByCategory.mapValues { merchants in
            merchants.max(by: { $0.value < $1.value })?.key ?? ""
        }

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
            effectiveBinCount: effectiveBinCount
        )
    }

    static func makePage(for scale: AnalyticsTimeScale, anchorDate: Date) -> AnalyticsPeriodPage {
        let calendar = Calendar.current

        switch scale {
        case .week:
            let interval = calendar.dateInterval(of: .weekOfYear, for: anchorDate)!
            let endInclusive = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.start

            return AnalyticsPeriodPage(
                startDate: interval.start,
                endDateExclusive: interval.end,
                displayTitle: formattedWeekRange(start: interval.start, end: endInclusive),
                binCount: 7
            )

        case .month:
            let interval = calendar.dateInterval(of: .month, for: anchorDate)!
            let days = calendar.range(of: .day, in: .month, for: interval.start)?.count ?? 30

            return AnalyticsPeriodPage(
                startDate: interval.start,
                endDateExclusive: interval.end,
                displayTitle: formattedMonthYear(interval.start),
                binCount: days
            )

        case .year:
            let interval = calendar.dateInterval(of: .year, for: anchorDate)!

            return AnalyticsPeriodPage(
                startDate: interval.start,
                endDateExclusive: interval.end,
                displayTitle: formattedYear(interval.start),
                binCount: 12
            )
        }
    }

    private struct BinDescriptor {
        let date: Date
        let axisLabel: String
        let title: String
        var showsGridline: Bool = true
    }

    private static func makeBins(for scale: AnalyticsTimeScale, page: AnalyticsPeriodPage) -> [BinDescriptor] {
        let calendar = Calendar.current

        switch scale {
        case .week:
            return strideDates(from: page.startDate, to: page.endDateExclusive, component: .day).map { date in
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "ru_RU")
                formatter.dateFormat = "EEE"

                return BinDescriptor(
                    date: date,
                    axisLabel: formatter.string(from: date),
                    title: formattedShortDate(date)
                )
            }

        case .month:
            let dates = strideDates(from: page.startDate, to: page.endDateExclusive, component: .day)

            return dates.map { date in
                let day = calendar.component(.day, from: date)
                // Линия и подпись — только в начале каждой недели (понедельник),
                // так подписи всегда совпадают с вертикальными линиями.
                let isWeekStart = calendar.component(.weekday, from: date) == 2

                return BinDescriptor(
                    date: date,
                    axisLabel: isWeekStart ? "\(day)" : "",
                    title: formattedShortDate(date),
                    showsGridline: isWeekStart
                )
            }

        case .year:
            return strideDates(from: page.startDate, to: page.endDateExclusive, component: .month).map { date in
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "ru_RU")
                formatter.dateFormat = "MMMM"

                // Подпись года — одна заглавная буква месяца (Июнь/Июль → «И»).
                let monthName = formatter.string(from: date)
                let initial = String(monthName.prefix(1)).uppercased()

                return BinDescriptor(
                    date: date,
                    axisLabel: initial,
                    title: formattedMonthYear(date)
                )
            }
        }
    }

    private static func strideDates(from start: Date, to endExclusive: Date, component: Calendar.Component) -> [Date] {
        var result: [Date] = []
        var current = start
        let calendar = Calendar.current

        while current < endExclusive {
            result.append(current)
            current = calendar.date(byAdding: component, value: 1, to: current) ?? endExclusive
        }

        return result
    }

    private static func binIndexForDate(
        _ date: Date,
        scale: AnalyticsTimeScale,
        page: AnalyticsPeriodPage,
        calendar: Calendar
    ) -> Int? {
        switch scale {
        case .week, .month:
            let start = calendar.startOfDay(for: page.startDate)
            let current = calendar.startOfDay(for: date)
            let delta = calendar.dateComponents([.day], from: start, to: current).day ?? 0
            return (0..<page.binCount).contains(delta) ? delta : nil

        case .year:
            let year = calendar.component(.year, from: page.startDate)
            let transactionYear = calendar.component(.year, from: date)
            guard year == transactionYear else { return nil }
            let month = calendar.component(.month, from: date) - 1
            return (0..<12).contains(month) ? month : nil
        }
    }

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

    private static func formattedWeekRange(start: Date, end: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")

        let calendar = Calendar.current
        let startMonth = calendar.component(.month, from: start)
        let endMonth = calendar.component(.month, from: end)
        let startYear = calendar.component(.year, from: start)
        let endYear = calendar.component(.year, from: end)

        if startMonth == endMonth && startYear == endYear {
            formatter.dateFormat = "d"
            let startDay = formatter.string(from: start)

            formatter.dateFormat = "d MMM yyyy"
            let endPart = formatter.string(from: end)

            return "\(startDay)–\(endPart)"
        } else {
            formatter.dateFormat = "d MMM"
            let startPart = formatter.string(from: start)

            formatter.dateFormat = "d MMM yyyy"
            let endPart = formatter.string(from: end)

            return "\(startPart)–\(endPart)"
        }
    }

    private static func formattedMonthYear(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "LLL yyyy"
        return formatter.string(from: date).capitalized
    }

    private static func formattedYear(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "yyyy"
        return formatter.string(from: date)
    }

    private static func formattedShortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMM yyyy"
        return formatter.string(from: date)
    }
}
