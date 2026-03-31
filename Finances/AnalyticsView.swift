import SwiftUI
import SwiftData
import Charts

struct AnalyticsView: View {
    @Query(sort: \Transaction.date, order: .reverse)
    private var transactions: [Transaction]

    @Query(sort: \ExpenseCategoryItem.name, order: .forward)
    private var categories: [ExpenseCategoryItem]

    @Query
    private var settingsList: [AppSettings]

    @State private var selectedBreakdown: AnalyticsBreakdown = .daily
//    @State private var selectedMode: AnalyticsMode = .all
    @State private var selectedMode: AnalyticsMode = .month
    @State private var selectedMonth: MonthSelection?
    @State private var selectedRange = DateRangeSelection()
    @State private var isShowingRangePicker = false
    @State private var selectedExpenseDate: Date?
    @State private var lastHapticSelectionDate: Date?
    @State private var selectedCategoryName: String?
    @State private var lastHapticCategoryName: String?
    @State private var categoryNavigationTarget: String?

    private var settings: AppSettings? {
        settingsList.first
    }

    private var availableMonths: [MonthSelection] {
        let calendar = Calendar.current

        let months = transactions.map {
            let comps = calendar.dateComponents([.year, .month], from: $0.date)
            return MonthSelection(year: comps.year ?? 2000, month: comps.month ?? 1)
        }

        return Array(Set(months)).sorted {
            if $0.year != $1.year { return $0.year > $1.year }
            return $0.month > $1.month
        }
    }

    private var currentAnalyticsScope: AnalyticsScope {
        switch selectedMode {

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
            
        case .all:
            return AnalyticsScope(
                title: "Все",
                contains: { _ in true }
            )
        }
    }

    private var filteredTransactions: [Transaction] {
        switch selectedMode {
        case .all:
            return transactions

        case .month:
            guard let selectedMonth else { return transactions }
            return transactions.filter { selectedMonth.contains($0.date) }

        case .range:
            guard selectedRange.isComplete else { return transactions }
            return transactions.filter { selectedRange.contains($0.date) }
        }
    }

    private var expenseTransactions: [Transaction] {
        filteredTransactions.filter { $0.countsAsExpenseInAnalytics }
    }

    private var incomeTransactions: [Transaction] {
        filteredTransactions.filter { $0.countsAsIncomeInAnalytics }
    }

    private var totalExpensesRub: Double {
        expenseTransactions.reduce(0) { partial, transaction in
            partial + (rubValue(for: transaction) ?? 0)
        }
    }

    private var totalIncomeRub: Double {
        incomeTransactions.reduce(0) { partial, transaction in
            partial + (rubValue(for: transaction) ?? 0)
        }
    }

    private var netFlowRub: Double {
        totalIncomeRub - totalExpensesRub
    }

    private var expenseTransactionsMissingRub: [Transaction] {
        expenseTransactions.filter { rubValue(for: $0) == nil }
    }

    private var incomeTransactionsMissingRub: [Transaction] {
        incomeTransactions.filter { rubValue(for: $0) == nil }
    }

    private var dailyExpenseTotalsRub: [(date: Date, total: Double)] {
        let grouped = Dictionary(grouping: expenseTransactions.compactMap { transaction -> (Date, Double)? in
            guard let rub = rubValue(for: transaction) else { return nil }
            return (Calendar.current.startOfDay(for: transaction.date), rub)
        }) { $0.0 }

        return grouped
            .map { date, values in
                let total = values.reduce(0) { $0 + $1.1 }
                return (date: date, total: total)
            }
            .sorted { $0.date > $1.date }
    }

    private var categoryTotalsRub: [(category: String, total: Double)] {
        let grouped = Dictionary(grouping: expenseTransactions.compactMap { transaction -> (String, Double)? in
            guard let rub = rubValue(for: transaction) else { return nil }
            return (transaction.categoryName ?? "Без категории", rub)
        }) { $0.0 }

        return grouped
            .map { category, values in
                let total = values.reduce(0) { $0 + $1.1 }
                return (category: category, total: total)
            }
            .sorted { $0.total > $1.total }
    }

    private var merchantTotalsRub: [(merchant: String, total: Double)] {
        let grouped = Dictionary(grouping: expenseTransactions.compactMap { transaction -> (String, Double)? in
            guard let rub = rubValue(for: transaction) else { return nil }
            return (normalizedMerchantName(transaction.details), rub)
        }) { $0.0 }

        return grouped
            .map { merchant, values in
                let total = values.reduce(0) { $0 + $1.1 }
                return (merchant: merchant, total: total)
            }
            .sorted { $0.total > $1.total }
            .prefix(10)
            .map { $0 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    modePicker
                    periodControls
//                    coverageInfoSection
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
                    availableDates: transactions.map(\.date)
                )
            }
            .onAppear {
                if selectedMonth == nil {
                    selectedMonth = availableMonths.first
                }
            }
            .background {
                NavigationLink(
                    isActive: Binding(
                        get: { categoryNavigationTarget != nil },
                        set: { if !$0 { categoryNavigationTarget = nil } }
                    )
                ) {
                    Group {
                        if let categoryNavigationTarget {
                            TransactionListByCategoryView(
                                categoryTitle: categoryNavigationTarget,
                                scope: currentAnalyticsScope
                            )
                        } else {
                            EmptyView()
                        }
                    }
                } label: {
                    EmptyView()
                }
                .hidden()
            }
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

    private var coverageInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Базовая валюта аналитики — рубли")
                .font(.subheadline.weight(.semibold))

            if expenseTransactionsMissingRub.isEmpty && incomeTransactionsMissingRub.isEmpty {
                Text("Все доходы и расходы в выбранном периоде имеют рублевый эквивалент.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    if !expenseTransactionsMissingRub.isEmpty {
                        Text("• Расходов без ₽-эквивалента: \(expenseTransactionsMissingRub.count)")
                    }

                    if !incomeTransactionsMissingRub.isEmpty {
                        Text("• Доходов без ₽-эквивалента: \(incomeTransactionsMissingRub.count)")
                    }
                }
                .font(.footnote)
                .foregroundStyle(.orange)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var summaryCards: some View {
        VStack(spacing: 12) {
            NavigationLink {
                TransactionListByKindView(
                    kind: .expense,
                    scope: currentAnalyticsScope
                )
            } label: {
                AnalyticsCardView(
                    title: "Расходы",
                    value: formattedRubAmount(totalExpensesRub),
                    secondaryValue: "\(expenseTransactions.count) операций",
                    systemImage: "arrow.up.circle.fill"
                )
            }
            .buttonStyle(.plain)

            NavigationLink {
                TransactionListByKindView(
                    kind: .income,
                    scope: currentAnalyticsScope
                )
            } label: {
                AnalyticsCardView(
                    title: "Доходы",
                    value: formattedRubAmount(totalIncomeRub),
                    secondaryValue: "\(incomeTransactions.count) операций",
                    systemImage: "arrow.down.circle.fill"
                )
            }
            .buttonStyle(.plain)

            AnalyticsCardView(
                title: "Итог",
                value: signedFormattedRubAmount(netFlowRub),
                secondaryValue: currentAnalyticsScope.title,
                systemImage: "equal.circle.fill"
            )
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

    private var dailySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("По дням")
                .font(.title3.bold())

            if dailyExpenseTotalsRub.isEmpty {
                Text("Нет расходов для выбранного периода")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(dailyExpenseTotalsRub, id: \.date) { item in
                        NavigationLink {
                            TransactionListByDateView(date: item.date)
                        } label: {
                            HStack {
                                Text(formattedShortDate(item.date))
                                Spacer()
                                Text(formattedRubAmount(item.total))
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

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("По категориям")
                .font(.title3.bold())

            if categoryTotalsRub.isEmpty {
                Text("Нет данных для выбранного периода")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(categoryTotalsRub, id: \.category) { item in
                        NavigationLink {
                            TransactionListByCategoryView(
                                categoryTitle: item.category,
                                scope: currentAnalyticsScope
                            )
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

                                        Text(item.category)
                                    }
                                } else {
                                    Text(item.category)
                                }

                                Spacer()

                                Text(formattedRubAmount(item.total))
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

    private var merchantSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Топ мест и сервисов")
                .font(.title3.bold())

            if merchantTotalsRub.isEmpty {
                Text("Нет расходов для выбранного периода")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(merchantTotalsRub.enumerated()), id: \.offset) { index, item in
                        NavigationLink {
                            TransactionListByMerchantView(
                                merchantTitle: item.merchant,
                                scope: currentAnalyticsScope
                            )
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

                                    Text(formattedRubAmount(item.total))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
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
                VStack(alignment: .leading, spacing: 10) {
                    if let selectedDailyPoint {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(tooltipDate(selectedDailyPoint.date))
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(formattedRubAmount(selectedDailyPoint.total))
                                .font(.headline.bold())
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    }

                    Chart {
                        ForEach(dailyExpenseTotalsRub, id: \.date) { item in
                            let isSelected = selectedExpenseDate.map {
                                Calendar.current.isDate($0, inSameDayAs: item.date)
                            } ?? false

                            BarMark(
                                x: .value("Дата", item.date),
                                y: .value("Расходы", item.total),
                                width: .fixed(isSelected ? 20 : 12)
                            )
                            .foregroundStyle(isSelected ? .blue : .blue.opacity(0.8))
                            .cornerRadius(isSelected ? 6 : 4)

                            if isSelected {
                                RuleMark(x: .value("Дата", item.date))
                                    .foregroundStyle(.secondary.opacity(0.22))
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
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            Rectangle()
                                .fill(.clear)
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            let plotFrame = geometry[proxy.plotAreaFrame]
                                            let xInPlot = value.location.x - plotFrame.origin.x

                                            guard xInPlot >= 0, xInPlot <= proxy.plotAreaSize.width else {
                                                return
                                            }

                                            if let date: Date = proxy.value(atX: xInPlot),
                                               let nearest = nearestDailyPoint(to: date) {
                                                if selectedExpenseDate == nil ||
                                                    !Calendar.current.isDate(selectedExpenseDate!, inSameDayAs: nearest.date) {
                                                    selectedExpenseDate = nearest.date
                                                    triggerSelectionHaptic(for: nearest.date)
                                                }
                                            }
                                        }
                                        .onEnded { _ in
                                            withAnimation(.easeOut(duration: 0.15)) {
                                                selectedExpenseDate = nil
                                                lastHapticSelectionDate = nil
                                            }
                                        }
                                )
                        }
                    }
                    .animation(.easeOut(duration: 0.15), value: selectedExpenseDate)
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
                VStack(alignment: .leading, spacing: 10) {
                    if let selectedCategoryPoint {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(selectedCategoryPoint.category)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(formattedRubAmount(selectedCategoryPoint.total))
                                .font(.headline.bold())

                            HStack(spacing: 8) {
                                Text(formattedPercent(categoryShare(for: selectedCategoryPoint.category)))
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.gray.opacity(0.10))
                                    .clipShape(Capsule())

                                if let merchant = topMerchant(in: selectedCategoryPoint.category) {
                                    Text("Топ: \(merchant)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    }

                    Chart {
                        ForEach(categoryTotalsRub, id: \.category) { item in
                            let isSelected = selectedCategoryName == item.category
                            let color = categoryItem(for: item.category).flatMap { Color(hex: $0.colorHex) } ?? .gray

                            BarMark(
                                x: .value("Сумма", item.total),
                                y: .value("Категория", item.category),
                                height: .fixed(isSelected ? 26 : 18)
                            )
                            .foregroundStyle(isSelected ? color : color.opacity(0.72))
                            .cornerRadius(isSelected ? 8 : 5)
                            .annotation(position: .trailing) {
                                Text(shortAmount(item.total))
                                    .font(isSelected ? .caption.bold() : .caption2)
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
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            Rectangle()
                                .fill(.clear)
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            let plotFrame = geometry[proxy.plotAreaFrame]
                                            let yInPlot = value.location.y - plotFrame.origin.y

                                            guard yInPlot >= 0, yInPlot <= proxy.plotAreaSize.height else {
                                                return
                                            }

                                            if let nearestCategoryName = nearestCategory(
                                                at: yInPlot,
                                                plotHeight: proxy.plotAreaSize.height
                                            ) {
                                                if selectedCategoryName != nearestCategoryName {
                                                    selectedCategoryName = nearestCategoryName
                                                    triggerCategoryHaptic(for: nearestCategoryName)
                                                }
                                            }
                                        }
                                        .onEnded { value in
                                            let totalTranslation = abs(value.translation.width) + abs(value.translation.height)

                                            if totalTranslation < 10, let selectedCategoryName {
                                                categoryNavigationTarget = selectedCategoryName
                                            }

                                            withAnimation(.easeOut(duration: 0.15)) {
                                                selectedCategoryName = nil
                                                lastHapticCategoryName = nil
                                            }
                                        }
                                )
                        }
                    }
                    .animation(.easeOut(duration: 0.15), value: selectedCategoryName)
                }
                .padding()
                .background(Color.gray.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 18))
            }
        }
    }

    private var chartHeightForCategories: CGFloat {
        let count = max(categoryTotalsRub.count, 1)
        let base = CGFloat(count) * 44
        return min(max(base, 180), 420)
    }

    private func rubValue(for transaction: Transaction) -> Double? {
        if let rubAmount = transaction.rubAmount {
            return abs(rubAmount)
        }

        if transaction.currencyCode == "₽" {
            return abs(transaction.amount)
        }

        if transaction.currencyCode == "₸", let settings {
            return CurrencyConverter.kztToRub(abs(transaction.amount), kztPerRub: settings.kztPerRub)
        }

        return nil
    }

    private func categoryItem(for categoryName: String) -> ExpenseCategoryItem? {
        CategoryLookup.findCategory(named: categoryName, in: categories)
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

    private func chartShortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMM"
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

    private func formattedShortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMM yyyy"
        return formatter.string(from: date)
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
    
    private var selectedDailyPoint: (date: Date, total: Double)? {
        guard let selectedExpenseDate else { return nil }

        return dailyExpenseTotalsRub.first {
            Calendar.current.isDate($0.date, inSameDayAs: selectedExpenseDate)
        }
    }

    private func nearestDailyPoint(to date: Date) -> (date: Date, total: Double)? {
        guard !dailyExpenseTotalsRub.isEmpty else { return nil }

        return dailyExpenseTotalsRub.min {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }
    }

    private func triggerSelectionHaptic(for date: Date) {
        if let lastHapticSelectionDate,
           Calendar.current.isDate(lastHapticSelectionDate, inSameDayAs: date) {
            return
        }

        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred(intensity: 0.7)
        lastHapticSelectionDate = date
    }

    private func tooltipDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMM yyyy"
        return formatter.string(from: date)
    }
    
    private var selectedCategoryPoint: (category: String, total: Double)? {
        guard let selectedCategoryName else { return nil }

        return categoryTotalsRub.first { $0.category == selectedCategoryName }
    }

    private func categoryShare(for categoryName: String) -> Double {
        guard totalExpensesRub > 0 else { return 0 }

        let total = categoryTotalsRub.first(where: { $0.category == categoryName })?.total ?? 0
        return total / totalExpensesRub
    }

    private func formattedPercent(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(Int(value * 100))%"
    }

    private func topMerchant(in categoryName: String) -> String? {
        let grouped = Dictionary(grouping: expenseTransactions.compactMap { transaction -> (String, Double)? in
            guard (transaction.categoryName ?? "Без категории") == categoryName else { return nil }
            guard let rub = rubValue(for: transaction) else { return nil }

            return (normalizedMerchantName(transaction.details), rub)
        }) { $0.0 }

        return grouped
            .map { merchant, values in
                (merchant: merchant, total: values.reduce(0) { $0 + $1.1 })
            }
            .sorted { $0.total > $1.total }
            .first?
            .merchant
    }

    private func nearestCategory(at yInPlot: CGFloat, plotHeight: CGFloat) -> String? {
        guard !categoryTotalsRub.isEmpty, plotHeight > 0 else { return nil }

        let rowHeight = plotHeight / CGFloat(categoryTotalsRub.count)
        let rawIndex = Int((yInPlot / rowHeight).rounded(.down))
        let index = min(max(rawIndex, 0), categoryTotalsRub.count - 1)

        return categoryTotalsRub[index].category
    }

    private func triggerCategoryHaptic(for categoryName: String) {
        if lastHapticCategoryName == categoryName {
            return
        }

        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred(intensity: 0.7)
        lastHapticCategoryName = categoryName
    }
}
