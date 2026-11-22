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
    /// Разбивка по подкатегориям; пустая, если подкатегорий у категории нет или их не выбирали.
    var subcategories: [AnalyticsSubcategoryTotal] = []
}

struct AnalyticsSubcategoryTotal: Identifiable {
    var id: String { name }
    let name: String
    let emoji: String?
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
        trackedRates: [TrackedExchangeRate],
        folded: FoldedExchangeRateDifferences? = nil
    ) -> AnalyticsSnapshot {
        // Пары «покупка — курсовая разница» ищутся по всем операциям: разница
        // часто приходит в следующем периоде.
        let folded = folded ?? ExchangeRateDifferenceMatcher.fold(transactions)
        let index = AnalyticsIndex(
            transactions: newestFirst(transactions),
            folded: folded,
            settings: settings,
            trackedRates: trackedRates
        )
        return build(index: index, scale: scale, anchorDate: anchorDate)
    }

    /// Операции новыми сверху — так их ждёт `AnalyticsIndex`.
    static func newestFirst(_ transactions: [Transaction]) -> [Transaction] {
        let isSorted = zip(transactions, transactions.dropFirst()).allSatisfy { $0.date >= $1.date }
        return isSorted ? transactions : transactions.sorted { $0.date > $1.date }
    }

    /// Отчёт периода по готовому индексу: проходит только операции своего отрезка.
    static func build(
        index: AnalyticsIndex,
        scale: AnalyticsTimeScale,
        anchorDate: Date
    ) -> AnalyticsSnapshot {
        let page = makePage(for: scale, anchorDate: anchorDate)
        let range = index.range(from: page.startDate, to: page.endDateExclusive)

        let bins = makeBins(for: scale, page: page)

        var chartTotals = Array(repeating: 0.0, count: bins.count)
        var totalExpensesRub = 0.0
        var totalIncomeRub = 0.0
        var expenseCount = 0
        var incomeCount = 0

        // Суммы — в массивы по номерам из индекса: без строковых ключей на каждой операции.
        var subTotals = Array(repeating: 0.0, count: index.subcategoryKeys.count)
        var subCounts = Array(repeating: 0, count: index.subcategoryKeys.count)
        var subTouched = Array(repeating: false, count: index.subcategoryKeys.count)
        var merchantTotalsByID = Array(repeating: 0.0, count: index.merchantNames.count)
        var merchantByCategoryID: [Int: Double] = [:]
        let merchantCount = index.merchantNames.count

        let calendar = Calendar.current

        for i in range {
            if let rub = index.expenseRub[i] {
                let isPurchase = index.isPurchase[i]
                totalExpensesRub += rub
                if isPurchase { expenseCount += 1 }

                if let binIndex = binIndexForDate(index.dates[i], scale: scale, page: page, calendar: calendar) {
                    chartTotals[binIndex] += rub
                }

                let sub = index.subcategoryID[i]
                subTotals[sub] += rub
                subCounts[sub] += isPurchase ? 1 : 0
                subTouched[sub] = true

                let merchant = index.merchantID[i]
                merchantTotalsByID[merchant] += rub
                merchantByCategoryID[index.categoryID[i] * merchantCount + merchant, default: 0] += rub
            } else if let rub = index.incomeRub[i] {
                totalIncomeRub += rub
                incomeCount += 1
            }
        }

        var categoryTotals = CategoryTotalsAccumulator()
        for sub in subTotals.indices where subTouched[sub] {
            let key = index.subcategoryKeys[sub]
            categoryTotals.add(
                category: index.categoryNames[key.category],
                subcategory: key.name,
                rub: subTotals[sub],
                count: subCounts[sub]
            )
        }

        var merchantMap: [String: Double] = [:]
        for (id, total) in merchantTotalsByID.enumerated() where total != 0 {
            merchantMap[index.merchantNames[id]] = total
        }
        var merchantByCategory: [String: [String: Double]] = [:]
        for (key, total) in merchantByCategoryID {
            let category = index.categoryNames[key / merchantCount]
            merchantByCategory[category, default: [:]][index.merchantNames[key % merchantCount]] = total
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
        
        // Операции идут новыми сверху: первая в отрезке — самая поздняя.
        if let lastTransactionDate = range.isEmpty ? nil : index.dates[range.lowerBound] {
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
            if now >= page.endDateExclusive {
                // Завершённый период — все его дни. Раньше сюда попадал и первый
                // день следующего периода: у 30-дневного месяца выходило 31.
                effectiveBinCount = page.binCount
            } else {
                // Текущий период — дни до сегодня включительно.
                let startOfDay = calendar.startOfDay(for: page.startDate)
                let currentDay = calendar.startOfDay(for: now)
                let daysPassed = calendar.dateComponents([.day], from: startOfDay, to: currentDay).day ?? 0
                effectiveBinCount = min(max(daysPassed + 1, 1), max(page.binCount, 1))
            }
            
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


        let merchantTotals = merchantMap
            .filter { CategoryTotalsAccumulator.isPositive($0.value) }
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
            categoryTotals: categoryTotals.result(),
            merchantTotals: merchantTotals,
            topMerchantByCategory: topMerchantByCategory,
            effectiveBinCount: effectiveBinCount
        )
    }

    /// Вклад операции в расходы, ₽; nil — в расходах она не участвует.
    ///
    /// Покупка (и оплата переводом) — со своими курсовыми разницами и привязанными
    /// возвратами. Возврат без покупки — минус в своей категории. Курсовая разница
    /// и привязанный возврат уже посчитаны внутри покупки.
    static func expenseRub(
        for transaction: Transaction,
        settings: AppSettings?,
        trackedRates: [TrackedExchangeRate],
        folded: FoldedExchangeRateDifferences
    ) -> Double? {
        let isPurchase = transaction.countsAsPurchaseInAnalytics
        let isStandaloneRefund = transaction.isRefund && !folded.isLinkedRefund(transaction)
        guard isPurchase || isStandaloneRefund,
              let rub = TransactionRubConverter.displayRubAmount(
                for: transaction,
                settings: settings,
                trackedRates: trackedRates
              )
        else { return nil }
        guard isPurchase else { return -rub }
        return rub + folded.rubAdjustment(for: transaction, settings: settings, trackedRates: trackedRates)
    }

    /// Доход в ₽; nil — операция не доход (возврат, свои счета, курсовая разница).
    static func incomeRub(
        for transaction: Transaction,
        settings: AppSettings?,
        trackedRates: [TrackedExchangeRate]
    ) -> Double? {
        guard transaction.countsAsIncomeInAnalytics else { return nil }
        return TransactionRubConverter.displayRubAmount(for: transaction, settings: settings, trackedRates: trackedRates)
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
                BinDescriptor(
                    date: date,
                    axisLabel: AnalyticsDateFormat.weekdayShort.string(from: date),
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
                // Подпись года — одна заглавная буква месяца (Июнь/Июль → «И»).
                let monthName = AnalyticsDateFormat.monthFull.string(from: date)
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

    static func normalizedMerchantName(_ details: String) -> String {
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
        let calendar = Calendar.current
        let startMonth = calendar.component(.month, from: start)
        let endMonth = calendar.component(.month, from: end)
        let startYear = calendar.component(.year, from: start)
        let endYear = calendar.component(.year, from: end)

        if startMonth == endMonth && startYear == endYear {
            let startDay = AnalyticsDateFormat.day.string(from: start)
            let endPart = AnalyticsDateFormat.dayMonthYear.string(from: end)

            return "\(startDay)–\(endPart)"
        } else {
            let startPart = AnalyticsDateFormat.dayMonth.string(from: start)
            let endPart = AnalyticsDateFormat.dayMonthYear.string(from: end)

            return "\(startPart)–\(endPart)"
        }
    }

    private static func formattedMonthYear(_ date: Date) -> String {
        AnalyticsDateFormat.monthShortYear.string(from: date).capitalized
    }

    private static func formattedYear(_ date: Date) -> String {
        AnalyticsDateFormat.year.string(from: date)
    }

    private static func formattedShortDate(_ date: Date) -> String {
        AnalyticsDateFormat.dayMonthYear.string(from: date)
    }
}

/// Форматтеры дат для снапшотов аналитики — по одному на шаблон.
/// Снапшот строится на каждой отрисовке, а DateFormatter создавать дорого:
/// раньше его заводил каждый столбик и каждая подпись.
enum AnalyticsDateFormat {
    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = format
        return formatter
    }

    static let day = formatter("d")
    static let dayMonth = formatter("d MMM")
    static let dayMonthYear = formatter("d MMM yyyy")
    /// «18 ноября».
    static let dayMonthLong = formatter("d MMMM")
    static let weekdayShort = formatter("EEE")
    static let monthShort = formatter("MMM")
    static let monthFull = formatter("MMMM")
    static let monthShortYear = formatter("LLL yyyy")
    static let year = formatter("yyyy")
}
