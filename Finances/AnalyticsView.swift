//
//  AnalyticsView.swift
//  Finances
//
//  Created by Андрей Матиенко on 19.03.2026.
//


import SwiftUI
import SwiftData
import Charts

struct AnalyticsView: View {
    @Query(sort: \Expense.date, order: .reverse)
    private var expenses: [Expense]
    
    @Query(sort: \ExpenseCategoryItem.name, order: .forward)
    private var categories: [ExpenseCategoryItem]

//    @State private var selectedPeriod: AnalyticsPeriod = .month
    
    @State private var selectedBreakdown: AnalyticsBreakdown = .daily
    
    @State private var selectedMode: AnalyticsMode = .all
    @State private var selectedMonth: MonthSelection?
    @State private var selectedRange = DateRangeSelection()
    @State private var isShowingRangePicker = false
    
    @Query
    private var settingsList: [AppSettings]
    
    private var settings: AppSettings? {
        settingsList.first
    }
    
    private var availableMonths: [MonthSelection] {
        let calendar = Calendar.current

        let months = expenses.map {
            let comps = calendar.dateComponents([.year, .month], from: $0.date)
            return MonthSelection(year: comps.year ?? 2000, month: comps.month ?? 1)
        }

        return Array(Set(months)).sorted {
            if $0.year != $1.year { return $0.year > $1.year }
            return $0.month > $1.month
        }
    }
    
    private var breakdownPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AnalyticsBreakdown.allCases, id: \.self) { breakdown in
                    Button {
                        selectedBreakdown = breakdown
                    } label: {
                        Text(breakdown.rawValue)
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                selectedBreakdown == breakdown
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
    
    private var currentAnalyticsScope: AnalyticsScope {
        switch selectedMode {
        case .all:
            return AnalyticsScope(
                title: "Все",
                contains: { _ in true }
            )

        case .month:
            let month = selectedMonth
            return AnalyticsScope(
                title: month?.title ?? "Месяц",
                contains: { date in
                    guard let month else { return true }
                    return month.contains(date)
                }
            )

        case .range:
            let range = selectedRange
            return AnalyticsScope(
                title: range.title,
                contains: { date in
                    guard range.isComplete else { return true }
                    return range.contains(date)
                }
            )
        }
    }
    
    private var filteredExpenses: [Expense] {
        switch selectedMode {
        case .all:
            return expenses

        case .month:
            guard let selectedMonth else { return expenses }
            return expenses.filter { selectedMonth.contains($0.date) }

        case .range:
            guard selectedRange.isComplete else { return expenses }
            return expenses.filter { selectedRange.contains($0.date) }
        }
    }
    
    private var modePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AnalyticsMode.allCases, id: \.self) { mode in
                    Button {
                        selectedMode = mode
                    } label: {
                        Text(mode.rawValue)
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                selectedMode == mode
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
    
    @ViewBuilder
    private var periodControls: some View {
        switch selectedMode {
        case .all:
            EmptyView()

        case .month:
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(availableMonths) { month in
                        Button {
                            selectedMonth = month
                        } label: {
                            Text(month.title)
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    selectedMonth == month
                                    ? Color.primary.opacity(0.1)
                                    : Color.gray.opacity(0.1)
                                )
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

        case .range:
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    isShowingRangePicker = true
                } label: {
                    HStack {
                        Image(systemName: "calendar")
                        Text(selectedRange.title)
                        Spacer()
                    }
                    .padding()
                    .background(Color.gray.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
        }
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
            expense.categoryName ?? "Без категории"
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
                    modePicker
                    periodControls
                    summaryCards
                    chartSection
                    breakdownPicker
                    selectedBreakdownSection
                }
                .padding()
            }
            .navigationTitle("Аналитика")
            .sheet(isPresented: $isShowingRangePicker) {
                DateRangePickerView(
                    selection: $selectedRange,
                    availableDates: expenses.map(\.date)
                )
            }
            .onAppear {
                if selectedMonth == nil {
                    selectedMonth = availableMonths.first
                }
            }
        }
    }
    
    @ViewBuilder
    private var selectedBreakdownSection: some View {
        switch selectedBreakdown {
        case .daily:
            dailySection

        case .category:
            VStack(spacing: 16) {
                categoryChartSection
                categorySection
            }

        case .merchant:
            merchantSection
        }
    }

    private var summaryCards: some View {
        VStack(spacing: 12) {
            NavigationLink {
                ExpenseListByCashFlowView(
                    flowType: .expenses,
                    scope: currentAnalyticsScope
                )
            } label: {
                AnalyticsCardView(
                    title: "Расходы",
                    value: formattedAmount(totalExpenses),
                    secondaryValue: settings != nil ? formattedRubAmount(totalExpensesRub) : nil,
                    systemImage: "arrow.up.circle.fill"
                )
            }
            .buttonStyle(.plain)

            NavigationLink {
                ExpenseListByCashFlowView(
                    flowType: .income,
                    scope: currentAnalyticsScope
                )
            } label: {
                AnalyticsCardView(
                    title: "Пополнения",
                    value: formattedAmount(totalIncome),
                    secondaryValue: settings != nil ? formattedRubAmount(totalIncomeRub) : nil,
                    systemImage: "arrow.down.circle.fill"
                )
            }
            .buttonStyle(.plain)

            AnalyticsCardView(
                title: "Итог",
                value: signedFormattedAmount(netFlow),
                secondaryValue: settings != nil ? signedFormattedRubAmount(netFlowRub) : nil,
                systemImage: "equal.circle.fill"
            )
        }
    }
    
    private var dailyExpenseTotalsRub: [(date: Date, total: Double)] {
        let onlyExpenses = filteredExpenses.filter { $0.amount < 0 }

        let grouped = Dictionary(grouping: onlyExpenses) {
            Calendar.current.startOfDay(for: $0.date)
        }

        return grouped
            .map { date, expenses in
                let total = expenses.reduce(0) { $0 + abs($1.rubAmount ?? 0) }
                return (date: date, total: total)
            }
            .sorted { $0.date > $1.date }
    }
    
    private var categoryTotalsRub: [(category: String, total: Double)] {
        let grouped = Dictionary(grouping: filteredExpenses.filter { $0.amount < 0 }) { expense in
            expense.categoryName ?? "Без категории"
        }

        return grouped
            .map { key, value in
                let total = value.reduce(0) { $0 + abs($1.rubAmount ?? 0) }
                return (category: key, total: total)
            }
            .sorted { $0.total > $1.total }
    }
    
    private var merchantTotalsRub: [(merchant: String, total: Double)] {
        let onlyExpenses = filteredExpenses.filter { $0.amount < 0 }

        let grouped = Dictionary(grouping: onlyExpenses) { expense in
            normalizedMerchantName(expense.details)
        }

        return grouped
            .map { merchant, expenses in
                let total = expenses.reduce(0) { $0 + abs($1.rubAmount ?? 0) }
                return (merchant: merchant, total: total)
            }
            .sorted { $0.total > $1.total }
            .prefix(10)
            .map { $0 }
    }
    
    private func categoryItem(for categoryName: String) -> ExpenseCategoryItem? {
        CategoryLookup.findCategory(named: categoryName, in: categories)
    }
    
    private func formattedRubAmount(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.groupingSeparator = " "
        formatter.decimalSeparator = ","

        let number = formatter.string(from: NSNumber(value: value)) ?? "\(value)"
        return "\(number) ₽"
    }

    private func signedFormattedRubAmount(_ value: Double) -> String {
        let sign = value < 0 ? "-" : "+"
        return "\(sign) \(formattedRubAmount(abs(value)))"
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
                        NavigationLink {
                            ExpenseListByCategoryView(categoryTitle: item.category)
                        } label: {
                            HStack {
                                if let categoryItem = categoryItem(for: item.category) {
                                    HStack(spacing: 8) {
                                        Circle()
                                            .fill(Color(hex: categoryItem.colorHex) ?? .gray)
                                            .frame(width: 24, height: 24)
                                            .overlay {
                                                Image(systemName: categoryItem.iconName)
                                                    .font(.system(size: 10, weight: .bold))
                                                    .foregroundStyle(.white)
                                            }

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(item.category)

                                            if let settings {
                                                Text(formattedRubAmount(
                                                    CurrencyConverter.kztToRub(item.total, kztPerRub: settings.kztPerRub)
                                                ))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                } else {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.category)

                                        if let settings {
                                            Text(formattedRubAmount(
                                                CurrencyConverter.kztToRub(item.total, kztPerRub: settings.kztPerRub)
                                            ))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        }
                                    }
                                }

                                Spacer()

                                Text(formattedAmount(item.total))
                                    .fontWeight(.semibold)
                            }
                            .padding()
                            .background(Color.gray.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
    
    private var dailyExpenseTotals: [(date: Date, total: Double)] {
        let onlyExpenses = filteredExpenses.filter { $0.amount < 0 }

        let grouped = Dictionary(grouping: onlyExpenses) {
            Calendar.current.startOfDay(for: $0.date)
        }

        return grouped
            .map { date, expenses in
                let total = expenses.reduce(0) { $0 + abs($1.amount) }
                return (date: date, total: total)
            }
            .sorted { $0.date > $1.date }
    }
    
    private var dailySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("По дням")
                .font(.title3.bold())

            if dailyExpenseTotals.isEmpty {
                Text("Нет расходов для выбранного периода")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(dailyExpenseTotals, id: \.date) { item in
                        NavigationLink {
                            ExpenseListByDateView(date: item.date)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(formattedShortDate(item.date))

                                    if let settings {
                                        Text(formattedRubAmount(
                                            CurrencyConverter.kztToRub(item.total, kztPerRub: settings.kztPerRub)
                                        ))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                Text(formattedAmount(item.total))
                                    .fontWeight(.semibold)
                            }
                            .padding()
                            .background(Color.gray.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
    
    private var merchantTotals: [(merchant: String, total: Double)] {
        let onlyExpenses = filteredExpenses.filter { $0.amount < 0 }

        let grouped = Dictionary(grouping: onlyExpenses) { expense in
            normalizedMerchantName(expense.details)
        }

        return grouped
            .map { merchant, expenses in
                let total = expenses.reduce(0) { $0 + abs($1.amount) }
                return (merchant: merchant, total: total)
            }
            .sorted { $0.total > $1.total }
            .prefix(10)
            .map { $0 }
    }
    
    private var merchantSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Топ мест и сервисов")
                .font(.title3.bold())

            if merchantTotals.isEmpty {
                Text("Нет расходов для выбранного периода")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(merchantTotals.enumerated()), id: \.offset) { index, item in
                        NavigationLink {
                            ExpenseListByMerchantView(merchantTitle: item.merchant)
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Text("\(index + 1)")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.merchant)
                                        .font(.body)
                                        .fontWeight(.medium)
                                        .lineLimit(2)

                                    Text(formattedAmount(item.total))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)

                                    if let settings {
                                        Text(formattedRubAmount(
                                            CurrencyConverter.kztToRub(item.total, kztPerRub: settings.kztPerRub)
                                        ))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()
                            }
                            .padding()
                            .background(Color.gray.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
    
    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("График расходов")
                .font(.title3.bold())

            if dailyExpenseTotalsRub.isEmpty {
                Text("Нет расходов для выбранного периода")
                    .foregroundStyle(.secondary)
            } else {
                Chart {
                    ForEach(dailyExpenseTotalsRub, id: \.date) { item in
                        BarMark(
                            x: .value("Дата", item.date),
                            y: .value("Расходы", item.total)
                        )
                        .annotation(position: .top, alignment: .center) {
                            if dailyExpenseTotalsRub.count <= 7 {
                                Text(shortAmount(item.total))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(height: 240)
                .chartXAxis {
                    AxisMarks(values: .automatic) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(chartShortDate(date))
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .padding()
                .background(Color.gray.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 18))
            }
        }
    }
    
    private var categoryChartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("График по категориям")
                .font(.title3.bold())

            if categoryTotalsRub.isEmpty {
                Text("Нет данных для выбранного периода")
                    .foregroundStyle(.secondary)
            } else {
                Chart {
                    ForEach(categoryTotalsRub, id: \.category) { item in
                        let color = categoryItem(for: item.category).flatMap { Color(hex: $0.colorHex) } ?? .gray

                        BarMark(
                            x: .value("Сумма", item.total),
                            y: .value("Категория", item.category)
                        )
                        .foregroundStyle(color)
                        .annotation(position: .trailing) {
                            Text(shortAmount(item.total))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(height: chartHeightForCategories)
                .chartXAxis {
                    AxisMarks(position: .bottom)
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .padding()
                .background(Color.gray.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 18))
            }
        }
    }
    
    private var chartHeightForCategories: CGFloat {
        let count = max(categoryTotals.count, 1)
        let base = CGFloat(count) * 44
        return min(max(base, 180), 420)
    }
    
    private var totalExpensesRub: Double {
        filteredExpenses
            .filter { $0.amount < 0 }
            .reduce(0) { $0 + abs($1.rubAmount ?? 0) }
    }

    private var totalIncomeRub: Double {
        filteredExpenses
            .filter { $0.amount > 0 }
            .reduce(0) { $0 + ($1.rubAmount ?? 0) }
    }

    private var netFlowRub: Double {
        totalIncomeRub - totalExpensesRub
    }
    
    private func chartShortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")

        switch selectedMode {
        case .all:
            formatter.dateFormat = "d MMM"

        case .month:
            formatter.dateFormat = "d MMM"

        case .range:
            formatter.dateFormat = "d MMM"
        }

        return formatter.string(from: date)
    }
    
    private func shortAmount(_ value: Double) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM ₽", value / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "%.0fK ₽", value / 1_000)
        } else {
            return String(format: "%.0f ₽", value)
        }
    }
    
    private func normalizedMerchantName(_ details: String) -> String {
        let uppercased = details.uppercased()

        if uppercased.hasPrefix("GRAB ") {
            return "GRAB"
        }

        if uppercased.hasPrefix("PAYOO MCDONALDS") {
            return "PAYOO MCDONALDS"
        }

        if uppercased.hasPrefix("OPENAI CHATGPT SUBSCR") {
            return "OPENAI CHATGPT SUBSCR"
        }

        if uppercased.hasPrefix("APPLE.COM BILL") {
            return "APPLE.COM BILL"
        }

        if uppercased.hasPrefix("VNPAY 43 FACTORY") {
            return "VNPAY 43 FACTORY"
        }

        if uppercased.hasPrefix("VNPAY XLIII COFFEE") {
            return "VNPAY XLIII COFFEE"
        }

        return uppercased
    }
    
    private func formattedShortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMM yyyy"
        return formatter.string(from: date)
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
