import SwiftUI
import SwiftData
import Charts

struct AnalyticsView: View {
    @Query(sort: \Transaction.date, order: .reverse)
    private var transactions: [Transaction]

    @Query(sort: \ExpenseCategoryItem.name, order: .forward)
    private var categories: [ExpenseCategoryItem]

    @Query(sort: \TrackedExchangeRate.code, order: .forward)
    private var trackedRates: [TrackedExchangeRate]

    @Query
    private var settingsList: [AppSettings]

    @State private var selectedScale: AnalyticsTimeScale = .week
    @State private var pageAnchorDate: Date = .now
    @State private var selectedBreakdown: AnalyticsBreakdown = .daily

    @State private var selectedChartPointID: String?
    @State private var lastHapticChartPointID: String?

    @State private var selectedCategoryName: String?
    @State private var lastHapticCategoryName: String?
    @State private var categoryNavigationTarget: String?
    
    @State private var pageChangeToken = UUID()

    private var settings: AppSettings? {
        settingsList.first
    }

    private var snapshot: AnalyticsSnapshot {
        AnalyticsSnapshotBuilder.build(
            transactions: transactions,
            scale: selectedScale,
            anchorDate: pageAnchorDate,
            settings: settings,
            trackedRates: trackedRates
        )
    }

    private var previousSnapshot: AnalyticsSnapshot {
        let calendar = Calendar.current

        let previousAnchor: Date
        switch selectedScale {
        case .week:
            previousAnchor = calendar.date(byAdding: .weekOfYear, value: -1, to: pageAnchorDate) ?? pageAnchorDate
        case .month:
            previousAnchor = calendar.date(byAdding: .month, value: -1, to: pageAnchorDate) ?? pageAnchorDate
        case .year:
            previousAnchor = calendar.date(byAdding: .year, value: -1, to: pageAnchorDate) ?? pageAnchorDate
        }

        return AnalyticsSnapshotBuilder.build(
            transactions: transactions,
            scale: selectedScale,
            anchorDate: previousAnchor,
            settings: settings,
            trackedRates: trackedRates
        )
    }

    private var currentAnalyticsScope: AnalyticsScope {
        let page = snapshot.page
        return AnalyticsScope(
            title: page.displayTitle,
            contains: { page.contains($0) }
        )
    }

    private var selectedChartPoint: AnalyticsChartPoint? {
        snapshot.chartPoints.first { $0.id == selectedChartPointID }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    scalePicker
                    periodNavigation
                    topSummarySection
                    chartSection
                    periodSummaryCards
//                    trendSection
//                    highlightsSection
                    breakdownPicker
                    selectedBreakdownSection
                }
                .padding()
            }
            .navigationTitle("Аналитика")
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
        .onAppear {
            pageAnchorDate = .now
        }
    }

    // MARK: - Top

    private var scalePicker: some View {
        HStack(spacing: 0) {
            ForEach(AnalyticsTimeScale.allCases) { scale in
                Button {
                    selectedScale = scale
                    selectedChartPointID = nil
                    selectedCategoryName = nil
                } label: {
                    Text(scale.rawValue)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            selectedScale == scale
                            ? Color.white
                            : Color.clear
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)

                if scale != AnalyticsTimeScale.allCases.last {
                    Divider()
                        .frame(height: 20)
                        .padding(.horizontal, 8)
                }
            }
        }
        .padding(6)
        .background(Color.gray.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var periodNavigation: some View {
        HStack {
            Spacer()

            Text(snapshot.page.displayTitle)
                .font(.title3.weight(.semibold))
                .contentTransition(.opacity)

            Spacer()
        }
        .frame(height: 44)
    }

    private var topSummarySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(selectedChartPoint == nil ? selectedScale.averageTitle : selectedScale.selectedPointTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(
                formattedRubAmount(
                    selectedChartPoint?.total ?? snapshot.averageExpensePerBin
                )
            )
            .font(.system(size: 24, weight: .bold))
            .minimumScaleFactor(0.7)
            .lineLimit(1)
            .contentTransition(.numericText())

            Text(selectedChartPoint?.title ?? snapshot.page.displayTitle)
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
        }
        .id(pageChangeToken)
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("График расходов")
                .font(.title3.bold())

            if snapshot.chartPoints.isEmpty {
                Text("Нет расходов для выбранного периода")
                    .foregroundStyle(.secondary)
            } else {
                InteractiveBarChartView(
                    points: snapshot.chartPoints,
                    selectedPointID: $selectedChartPointID
                ) { point in
                    if let point {
                        if lastHapticChartPointID != point.id {
                            let generator = UIImpactFeedbackGenerator(style: .light)
                            generator.impactOccurred(intensity: 0.7)
                            lastHapticChartPointID = point.id
                        }
                    } else {
                        lastHapticChartPointID = nil
                    }
                } onPeriodSwipe: { swipeInfo in
                    handleProportionalSwipe(swipeInfo)
                }
                .padding()
                .background(Color.gray.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .id(pageChangeToken)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            }
        }
    }

    // MARK: - Summary cards

    private var periodSummaryCards: some View {
        VStack(spacing: 12) {
            NavigationLink {
                TransactionListByKindView(
                    kind: .expense,
                    scope: currentAnalyticsScope
                )
            } label: {
                AnalyticsCardView(
                    title: "Расходы",
                    value: formattedRubAmount(snapshot.totalExpensesRub),
                    secondaryValue: "\(snapshot.expenseCount) операций",
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
                    value: formattedRubAmount(snapshot.totalIncomeRub),
                    secondaryValue: "\(snapshot.incomeCount) операций",
                    systemImage: "arrow.down.circle.fill"
                )
            }
            .buttonStyle(.plain)

            AnalyticsCardView(
                title: "Итог",
                value: signedFormattedRubAmount(snapshot.netFlowRub),
                secondaryValue: snapshot.page.displayTitle,
                systemImage: "equal.circle.fill"
            )
        }
    }

    // MARK: - Trend / Highlights

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Тренд")
                .font(.title3.bold())

            if let trendMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Text(trendHeadline)
                        .font(.headline)

                    Text(trendMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color.gray.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 18))
            } else {
                Text("Недостаточно данных для сравнения с предыдущим периодом")
                    .foregroundStyle(.secondary)
                    .padding()
                    .background(Color.gray.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            }
        }
    }

    private var highlightsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Highlights")
                .font(.title3.bold())

            VStack(spacing: 12) {
                if let peakPoint = snapshot.peakChartPoint {
                    highlightCard(
                        title: selectedScale == .year ? "Пиковый месяц" : "Пиковый день",
                        value: formattedRubAmount(peakPoint.total),
                        subtitle: peakPoint.title,
                        systemImage: "flame.fill"
                    )
                }

                if let topCategory = snapshot.categoryTotals.first {
                    highlightCard(
                        title: "Топ категория",
                        value: formattedRubAmount(topCategory.total),
                        subtitle: "\(topCategory.category) • \(formattedPercent(categoryShare(for: topCategory.category)))",
                        systemImage: "chart.bar.fill"
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func highlightCard(
        title: String,
        value: String,
        subtitle: String,
        systemImage: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(.orange)

                Text(title)
                    .font(.headline)
            }

            Text(value)
                .font(.title2.bold())

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    // MARK: - Breakdown picker

    private var breakdownPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AnalyticsBreakdown.allCases, id: \.self) { breakdown in
                    Button {
                        selectedBreakdown = breakdown
                    } label: {
                        Text(breakdown.rawValue)
                            .font(.subheadline)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                selectedBreakdown == breakdown
                                ? Color.primary.opacity(0.10)
                                : Color.gray.opacity(0.08)
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

    // MARK: - Lower sections

    private var dailySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(selectedScale == .year ? "По месяцам" : "По дням")
                .font(.title3.bold())

            if snapshot.lowerTimeTotals.isEmpty {
                Text("Нет расходов для выбранного периода")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(snapshot.lowerTimeTotals) { item in
                        NavigationLink {
                            if selectedScale == .year {
                                TransactionListByKindView(
                                    kind: .expense,
                                    scope: monthScope(for: item.date)
                                )
                            } else {
                                TransactionListByDateView(date: item.date)
                            }
                        } label: {
                            HStack {
                                Text(item.title)
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

            if snapshot.categoryTotals.isEmpty {
                Text("Нет данных для выбранного периода")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(snapshot.categoryTotals) { item in
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

            if snapshot.merchantTotals.isEmpty {
                Text("Нет расходов для выбранного периода")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(snapshot.merchantTotals.enumerated()), id: \.offset) { index, item in
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

    // MARK: - Category interactive chart

    private var categoryChartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("График по категориям")
                .font(.title3.bold())

            if snapshot.categoryTotals.isEmpty {
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

                                if let merchant = snapshot.topMerchantByCategory[selectedCategoryPoint.category], !merchant.isEmpty {
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
                    }

                    Chart {
                        ForEach(snapshot.categoryTotals) { item in
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

                                                    if lastHapticCategoryName != nearestCategoryName {
                                                        let generator = UIImpactFeedbackGenerator(style: .light)
                                                        generator.impactOccurred(intensity: 0.7)
                                                        lastHapticCategoryName = nearestCategoryName
                                                    }
                                                }
                                            }
                                        }
                                        .onEnded { value in
                                            let totalTranslation = abs(value.translation.width) + abs(value.translation.height)

                                            if totalTranslation < 10, let selectedCategoryName {
                                                categoryNavigationTarget = selectedCategoryName
                                            }

                                            selectedCategoryName = nil
                                            lastHapticCategoryName = nil
                                        }
                                )
                        }
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 18))
            }
        }
    }

    // MARK: - Helpers

    private var canMoveForward: Bool {
        let currentRealPage = AnalyticsSnapshotBuilder.makePage(for: selectedScale, anchorDate: .now)
        return snapshot.page.startDate < currentRealPage.startDate
    }

    /// Обрабатывает пропорциональный свайп с учётом дистанции и скорости
    private func handleProportionalSwipe(_ swipeInfo: ProportionalSwipeInfo) {
        let calendar = Calendar.current
        
        // Рассчитываем пропорциональный сдвиг в днях/месяцах
        let offsetDays = calculateProportionalOffset(for: swipeInfo)
        
        // Проверяем направление
        let multiplier: Double = swipeInfo.direction == .forward ? 1.0 : -1.0
        let totalDays = offsetDays * multiplier
        
        // Вычисляем новую дату
        let nextDate = calendar.date(byAdding: .day, value: Int(totalDays), to: pageAnchorDate) ?? pageAnchorDate
        
        // Проверка границы будущего
        if swipeInfo.direction == .forward {
            let currentRealPage = AnalyticsSnapshotBuilder.makePage(for: selectedScale, anchorDate: .now)
            let nextPage = AnalyticsSnapshotBuilder.makePage(for: selectedScale, anchorDate: nextDate)
            
            if nextPage.startDate >= currentRealPage.endDateExclusive {
                // Достигли будущего — предупреждающая вибрация и отскок
                let notification = UINotificationFeedbackGenerator()
                notification.notificationOccurred(.warning)
                
                // Визуальный bounce-эффект уже обрабатывается в InteractiveBarChartView
                return
            }
        }
        
        // Выбираем анимацию в зависимости от силы свайпа
        let animation: Animation
        switch swipeInfo.intensity {
        case .minimal, .light:
            animation = .spring(response: 0.5, dampingFraction: 0.80)
        case .medium:
            animation = .spring(response: 0.35, dampingFraction: 0.78)
        case .strong:
            animation = .spring(response: 0.28, dampingFraction: 0.75)
        }
        
        withAnimation(animation) {
            pageAnchorDate = nextDate
            selectedChartPointID = nil
            selectedCategoryName = nil
            pageChangeToken = UUID()
        }
    }
    
    /// Рассчитывает пропорциональный сдвиг в днях на основе параметров свайпа
    private func calculateProportionalOffset(for swipeInfo: ProportionalSwipeInfo) -> Double {
        let absDistance = abs(swipeInfo.distance)
        let absVelocity = abs(swipeInfo.velocity)
        
        // Калибровочные коэффициенты для каждого масштаба
        let baseCalibration: CGFloat
        switch selectedScale {
        case .week:
            baseCalibration = 80  // Для недельного масштаба
        case .month:
            baseCalibration = 100 // Для месячного масштаба
        case .year:
            baseCalibration = 60  // Для годового масштаба (более чувствительный)
        }
        
        // Базовый сдвиг = distance / K
        let baseOffset = absDistance / baseCalibration
        
        // Множитель скорости (от 1.0 до 3.0)
        let velocityMultiplier: CGFloat
        if absVelocity > 2000 {
            velocityMultiplier = 3.0
        } else if absVelocity > 1500 {
            velocityMultiplier = 2.5
        } else if absVelocity > 1000 {
            velocityMultiplier = 2.0
        } else if absVelocity > 500 {
            velocityMultiplier = 1.5
        } else {
            velocityMultiplier = 1.0
        }
        
        // Ограничения по масштабу
        let scaleLimits: (min: Double, max: Double)
        switch selectedScale {
        case .week:
            // Неделя: от 1 дня до 14 дней (2 недели максимум)
            scaleLimits = (1.0, 14.0)
        case .month:
            // Месяц: от 2 дней до 60 дней (2 месяца максимум)
            scaleLimits = (2.0, 60.0)
        case .year:
            // Год: от 15 дней до 365 дней (1 год максимум)
            scaleLimits = (15.0, 365.0)
        }
        
        // Итоговый сдвиг с учётом всех множителей
        let rawOffset = Double(baseOffset * velocityMultiplier)
        let clampedOffset = min(max(rawOffset, scaleLimits.min), scaleLimits.max)
        
        return clampedOffset
    }

    private func movePeriod(by delta: Int) {
        let calendar = Calendar.current

        let nextDate: Date
        switch selectedScale {
        case .week:
            nextDate = calendar.date(byAdding: .weekOfYear, value: delta, to: pageAnchorDate) ?? pageAnchorDate
        case .month:
            nextDate = calendar.date(byAdding: .month, value: delta, to: pageAnchorDate) ?? pageAnchorDate
        case .year:
            nextDate = calendar.date(byAdding: .year, value: delta, to: pageAnchorDate) ?? pageAnchorDate
        }

        if delta > 0 && !canMoveForward {
            return
        }

        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.impactOccurred(intensity: 0.8)

        withAnimation(.snappy(duration: 0.28, extraBounce: 0.04)) {
            pageAnchorDate = nextDate
            selectedChartPointID = nil
            selectedCategoryName = nil
            pageChangeToken = UUID()
        }
    }

    private var trendDeltaFraction: Double? {
        guard previousSnapshot.averageExpensePerBin > 0 else { return nil }
        return (snapshot.averageExpensePerBin - previousSnapshot.averageExpensePerBin) / previousSnapshot.averageExpensePerBin
    }

    private var trendHeadline: String {
        guard let delta = trendDeltaFraction else {
            return "Тренд недоступен"
        }

        if abs(delta) < 0.03 {
            return "Расходы почти не изменились"
        } else if delta > 0 {
            return "Ты тратишь больше"
        } else {
            return "Ты тратишь меньше"
        }
    }

    private var trendMessage: String? {
        guard let delta = trendDeltaFraction else { return nil }

        let periodName: String
        switch selectedScale {
        case .week:
            periodName = "прошлой неделей"
        case .month:
            periodName = "прошлым месяцем"
        case .year:
            periodName = "прошлым годом"
        }

        if abs(delta) < 0.03 {
            return "Средний расход почти не изменился по сравнению с \(periodName)."
        }

        let percent = formattedPercent(abs(delta))
        let unit: String = selectedScale == .year ? "Средний расход в месяц" : "Средний расход в день"

        if delta > 0 {
            return "\(unit) выше на \(percent) по сравнению с \(periodName)."
        } else {
            return "\(unit) ниже на \(percent) по сравнению с \(periodName)."
        }
    }

    private var selectedCategoryPoint: AnalyticsCategoryTotal? {
        snapshot.categoryTotals.first { $0.category == selectedCategoryName }
    }

    private func categoryShare(for categoryName: String) -> Double {
        guard snapshot.totalExpensesRub > 0 else { return 0 }
        let total = snapshot.categoryTotals.first(where: { $0.category == categoryName })?.total ?? 0
        return total / snapshot.totalExpensesRub
    }

    private func formattedPercent(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(Int(value * 100))%"
    }

    private func nearestCategory(at yInPlot: CGFloat, plotHeight: CGFloat) -> String? {
        guard !snapshot.categoryTotals.isEmpty, plotHeight > 0 else { return nil }

        let rowHeight = plotHeight / CGFloat(snapshot.categoryTotals.count)
        let rawIndex = Int((yInPlot / rowHeight).rounded(.down))
        let index = min(max(rawIndex, 0), snapshot.categoryTotals.count - 1)

        return snapshot.categoryTotals[index].category
    }

    private func categoryItem(for categoryName: String) -> ExpenseCategoryItem? {
        CategoryLookup.findCategory(named: categoryName, in: categories)
    }

    private var chartHeightForCategories: CGFloat {
        let count = max(snapshot.categoryTotals.count, 1)
        let base = CGFloat(count) * 44
        return min(max(base, 180), 420)
    }

    private func monthScope(for date: Date) -> AnalyticsScope {
        let interval = Calendar.current.dateInterval(of: .month, for: date)!
        return AnalyticsScope(
            title: monthYear(date),
            contains: { $0 >= interval.start && $0 < interval.end }
        )
    }

    private func monthYear(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "LLL yyyy"
        return formatter.string(from: date).capitalized
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

    private func shortAmount(_ value: Double) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM ₽", value / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "%.0fK ₽", value / 1_000)
        } else {
            return String(format: "%.0f ₽", value)
        }
    }
}
