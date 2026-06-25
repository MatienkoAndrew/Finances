import SwiftUI
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
    
    @Query(sort: \TransactionTag.createdAt, order: .reverse)
    private var tags: [TransactionTag]

    @Query
    private var settingsList: [AppSettings]

    @State private var selectedMode: AnalyticsViewMode = .time
    @State private var selectedScale: AnalyticsTimeScale = .week
    @State private var pageAnchorDate: Date = .now
    
    // Для режима Tags
    @State private var selectedTag: TransactionTag?

    @State private var selectedChartPointID: String?
    @State private var selectedCategoryName: String?
    @State private var lastHapticCategoryName: String?
    @State private var categoryNavigationTarget: String?

    @State private var pagingSessionStartAnchorDate: Date?
    @State private var didInitializeAnchor = false

    private var settings: AppSettings? {
        settingsList.first
    }
    
    // MARK: - Filtered Transactions
    
    private var filteredTransactions: [Transaction] {
        switch selectedMode {
        case .time:
            return transactions
        case .tags:
            guard let tag = selectedTag else { return [] }
            return transactions.filter { $0.hasTag(tag.name) }
        }
    }

    private var snapshot: AnalyticsSnapshot {
        if selectedMode == .tags {
            // В режиме Tags строим снапшот по эффективному периоду метки
            // (без пустых дней до/после) с авто-гранулярностью бинов.
            guard let tag = selectedTag else {
                let emptyPage = AnalyticsPeriodPage(
                    startDate: .now,
                    endDateExclusive: .now,
                    displayTitle: "Нет метки",
                    binCount: 0
                )
                return AnalyticsSnapshot.empty(for: emptyPage)
            }
            return TagAnalyticsBuilder.buildSnapshot(
                tag: tag,
                transactions: transactions,
                settings: settings,
                trackedRates: trackedRates
            )
        } else {
            // В режиме Time используем стандартную логику
            return AnalyticsSnapshotBuilder.build(
                transactions: filteredTransactions,
                scale: selectedScale,
                anchorDate: pageAnchorDate,
                settings: settings,
                trackedRates: trackedRates
            )
        }
    }

    /// Гранулярность бинов для текущей выбранной метки.
    /// Используется для подзаголовков и форматирования "ДЕНЬ/НЕДЕЛЯ/МЕСЯЦ".
    private var tagBinGranularity: TagBinGranularity? {
        guard selectedMode == .tags, let tag = selectedTag else { return nil }
        let tagged = transactions.filter { $0.hasTag(tag.name) }
        return TagAnalyticsBuilder.granularity(for: tag, taggedTransactions: tagged)
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
            transactions: filteredTransactions,
            scale: selectedScale,
            anchorDate: previousAnchor,
            settings: settings,
            trackedRates: trackedRates
        )
    }

    private var currentAnalyticsScope: AnalyticsScope {
        switch selectedMode {
        case .time:
            let page = snapshot.page
            return AnalyticsScope(
                title: page.displayTitle,
                matches: { tx in page.contains(tx.date) },
                containsDate: { date in page.contains(date) }
            )
        case .tags:
            guard let tag = selectedTag else {
                return AnalyticsScope(
                    title: "Нет метки",
                    matches: { _ in false },
                    containsDate: { _ in false }
                )
            }

            // В режиме меток drill-down должен показывать ТОЛЬКО транзакции
            // с этим тегом — иначе после ручного снятия метки транзакция
            // продолжала бы всплывать в детализации по диапазону дат.
            let tagName = tag.name
            if let start = tag.startDate, let end = tag.endDate {
                return AnalyticsScope(
                    title: tag.name,
                    matches: { tx in
                        tx.hasTag(tagName) && tx.date >= start && tx.date <= end
                    },
                    containsDate: { date in date >= start && date <= end }
                )
            } else {
                return AnalyticsScope(
                    title: tag.name,
                    matches: { tx in tx.hasTag(tagName) },
                    containsDate: { _ in true }
                )
            }
        }
    }

    private var selectedChartPoint: AnalyticsChartPoint? {
        snapshot.chartPoints.first { $0.id == selectedChartPointID }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    if selectedMode == .time {
                        periodNavigation
                    } else {
                        tagPicker
                        // В режиме меток период жёстко задан самой меткой,
                        // поэтому W/M/Y и стрелки навигации скрываем —
                        // вместо них показываем инфо-полоску.
                        if tagBinGranularity != nil {
                            tagInfoStrip
                        }
                    }
                    
                    periodSummaryCards
                    topSummarySection
                    chartSection

                    // Разбивки идут одна за другой, без переключателя.
                    dailySection
                    categoryChartSection
                    categorySection
                    merchantSection
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if selectedMode == .time {
                        scaleTabs
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    tagToggleButton
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
        .onAppear {
            guard !didInitializeAnchor else { return }
            didInitializeAnchor = true
            pageAnchorDate = latestAllowedAnchorDate
        }
        .onChange(of: selectedScale) { _, _ in
            pagingSessionStartAnchorDate = nil
            selectedChartPointID = nil
            selectedCategoryName = nil
            pageAnchorDate = snappedAnchorDate(
                min(pageAnchorDate, latestAllowedAnchorDate),
                scale: selectedScale
            )
        }
        .onChange(of: selectedMode) { _, newMode in
            selectedChartPointID = nil
            selectedCategoryName = nil
            
            // При переключении в режим Tags, автоматически выбираем первую метку
            if newMode == .tags {
                if selectedTag == nil {
                    selectedTag = tags.first
                }
                // Устанавливаем anchor на начало периода метки
                if let tag = selectedTag, let start = tag.startDate {
                    pageAnchorDate = start
                }
            }
        }
        .onChange(of: selectedTag) { _, newTag in
            selectedChartPointID = nil
            selectedCategoryName = nil
            
            // При смене метки обновляем anchor date
            if selectedMode == .tags, let tag = newTag, let start = tag.startDate {
                pageAnchorDate = start
            }
        }
    }

    // MARK: - Top
    
    // Иконка-тумблер в правом верхнем углу: переключает экран между
    // режимами времени и меток (заменяет прежний сегмент Time/Tags).
    private var tagToggleButton: some View {
        Button {
            withAnimation {
                selectedMode = selectedMode == .tags ? .time : .tags
            }
        } label: {
            Image(systemName: selectedMode == .tags ? "tag.fill" : "tag")
        }
        .accessibilityLabel(selectedMode == .tags ? "Закрыть метки" : "Метки")
    }
    
    private var tagPicker: some View {
        VStack(spacing: 12) {
            if tags.isEmpty {
                HStack {
                    Image(systemName: "tag.slash")
                        .foregroundStyle(.secondary)
                    Text("Нет меток")
                        .foregroundStyle(.secondary)
                    Spacer()
                    NavigationLink {
                        TagsManagementView()
                    } label: {
                        Text("Создать")
                            .font(.subheadline)
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                Picker("Метка", selection: $selectedTag) {
                    ForEach(tags) { tag in
                        Text("\(tag.displayIcon) \(tag.name)")
                            .tag(tag as TransactionTag?)
                    }
                }
                .pickerStyle(.menu)
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                
                if let tag = selectedTag {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(tag.name)
                                .font(.headline)
                            if tag.startDate != nil || tag.endDate != nil {
                                Text(tag.periodDescription)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text("\(filteredTransactions.count)")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.secondary)
                        Text("транзакций")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(ColorHelper.fromHex(tag.colorHex ?? "#007AFF").opacity(0.1))
                    )
                }
            }
        }
    }

    private var tagInfoStrip: some View {
        HStack(spacing: 8) {
            if let granularity = tagBinGranularity {
                Label(granularity.sectionTitle, systemImage: granularityIconName(granularity))
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.12))
                    .foregroundStyle(Color.accentColor)
                    .clipShape(Capsule())
            }

            Text(snapshot.page.displayTitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Spacer()
        }
    }

    private func granularityIconName(_ granularity: TagBinGranularity) -> String {
        switch granularity {
        case .daily: return "calendar"
        case .weekly: return "calendar.badge.clock"
        case .monthly: return "calendar.circle"
        }
    }

    // Верхние вкладки масштаба в стиле Alipay: текст + подчёркивание.
    private var scaleTabs: some View {
        HStack(spacing: 22) {
            ForEach(AnalyticsTimeScale.allCases) { scale in
                let isSelected = selectedScale == scale

                Button {
                    selectedScale = scale
                } label: {
                    VStack(spacing: 3) {
                        Text(scale.tabTitle)
                            .font(.subheadline.weight(isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? Color.primary : Color.secondary)

                        Capsule()
                            .fill(isSelected ? Color.primary : Color.clear)
                            .frame(width: 16, height: 2)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var periodNavigation: some View {
        HStack(spacing: 16) {
            Button {
                moveToPreviousPeriod()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            Text(snapshot.page.displayTitle)
                .font(.title3.weight(.semibold))
                .contentTransition(.opacity)

            Spacer()

            Button {
                moveToNextPeriod()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(canMoveToNextPeriod ? Color.primary : Color.secondary.opacity(0.3))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canMoveToNextPeriod)
        }
        .frame(height: 44)
    }

    private var topSummarySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(topSummaryTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(
                formattedRubAmount(topSummaryAmount)
            )
            .font(.system(size: 24, weight: .bold))
            .minimumScaleFactor(0.7)
            .lineLimit(1)
            .contentTransition(.numericText())

            Text(topSummarySubtitle)
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
        }
    }
    
    private var topSummaryAmount: Double {
        // Если бар выбран — всегда показываем его сумму (и в Time, и в Tags).
        if let selected = selectedChartPoint {
            return selected.total
        }
        if selectedMode == .tags {
            return snapshot.totalExpensesRub
        }
        return snapshot.averageExpensePerBin
    }

    private var topSummaryTitle: String {
        if selectedChartPoint != nil {
            // Заголовок выбранной точки зависит от гранулярности бинов.
            if selectedMode == .tags {
                return tagBinGranularity?.selectedPointTitle ?? "ПЕРИОД"
            }
            return selectedScale.selectedPointTitle
        }
        if selectedMode == .tags {
            return selectedTag != nil ? "ВСЕГО ПО МЕТКЕ" : "МЕТКА НЕ ВЫБРАНА"
        }
        return selectedScale.averageTitle
    }

    private var topSummarySubtitle: String {
        if let selected = selectedChartPoint {
            // При выделенном баре показываем его название (день/неделю/месяц).
            return selected.title
        }
        if selectedMode == .tags {
            return selectedTag?.name ?? "—"
        }
        return snapshot.page.displayTitle
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
                    if point != nil {
                        selectedCategoryName = nil
                    }
                } onPeriodDragBegan: {
                    beginInteractivePaging()
                } onPeriodDragChanged: { translation in
                    updateInteractivePaging(with: translation)
                } onPeriodSwipeEnded: { swipeInfo in
                    finishInteractivePaging(with: swipeInfo)
                }
                .padding()
                .background(Color.gray.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 18))
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
        }
    }

    // MARK: - Lower sections

    private var dailySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(dailySectionTitle)
                .font(.title3.bold())

            if snapshot.chartPoints.isEmpty {
                Text("Нет расходов для выбранного периода")
                    .foregroundStyle(.secondary)
            } else if selectedMode == .time && selectedScale == .week {
                weekDailyStrip
            } else if selectedMode == .time && selectedScale == .month {
                monthDailyCalendar
            } else {
                // Год и режим меток — прежний список строк.
                VStack(spacing: 10) {
                    ForEach(snapshot.lowerTimeTotals) { item in
                        dailySectionRow(for: item)
                    }
                }
            }
        }
    }

    // Неделя: горизонтальная лента из 7 карточек (дата + сумма), стиль Alipay.
    private var weekDailyStrip: some View {
        HStack(spacing: 8) {
            ForEach(snapshot.chartPoints) { point in
                NavigationLink {
                    TransactionListByDateView(date: point.date)
                } label: {
                    VStack(spacing: 6) {
                        Text(Self.dayMonthFormatter.string(from: point.date))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)

                        Text(dayCellAmount(point.total))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 4)
                    .background(Color.gray.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // Месяц: сетка-календарь с суммой по дням и подсветкой по интенсивности трат.
    private var monthDailyCalendar: some View {
        var calendar = Calendar.current
        calendar.locale = Locale(identifier: "ru_RU")

        let points = snapshot.chartPoints
        let maxTotal = max(points.map(\.total).max() ?? 0, 1)
        let leadingBlanks = points.first.map { first in
            (calendar.component(.weekday, from: first.date) - calendar.firstWeekday + 7) % 7
        } ?? 0
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

        return VStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(orderedWeekdaySymbols(calendar), id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(0..<leadingBlanks, id: \.self) { _ in
                    Color.clear.frame(height: 52)
                }

                ForEach(points) { point in
                    monthDayCell(point, maxTotal: maxTotal, calendar: calendar)
                }
            }
        }
    }

    private func monthDayCell(
        _ point: AnalyticsChartPoint,
        maxTotal: Double,
        calendar: Calendar
    ) -> some View {
        let day = calendar.component(.day, from: point.date)
        let hasSpend = point.total > 0
        let intensity = hasSpend ? min(point.total / maxTotal, 1) : 0
        let background = hasSpend
            ? Color.red.opacity(0.10 + 0.30 * intensity)
            : Color.gray.opacity(0.08)

        return NavigationLink {
            TransactionListByDateView(date: point.date)
        } label: {
            VStack(spacing: 3) {
                Text("\(day)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(hasSpend ? dayCellAmount(point.total) : "—")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    // Короткие названия дней недели в порядке от firstWeekday (Пн … Вс для ru).
    private func orderedWeekdaySymbols(_ calendar: Calendar) -> [String] {
        let symbols = calendar.shortWeekdaySymbols.map { $0.capitalized }
        let shift = calendar.firstWeekday - 1
        guard shift > 0 else { return symbols }
        return Array(symbols[shift...] + symbols[..<shift])
    }

    private static let dayMonthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "MM.dd"
        return formatter
    }()

    private static let dayCellAmountFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        formatter.groupingSeparator = ""
        formatter.decimalSeparator = ","
        return formatter
    }()

    private func dayCellAmount(_ value: Double) -> String {
        Self.dayCellAmountFormatter.string(from: NSNumber(value: value)) ?? "0"
    }

    private var dailySectionTitle: String {
        if selectedMode == .tags, let granularity = tagBinGranularity {
            return granularity.sectionTitle
        }
        return selectedScale == .year ? "По месяцам" : "По дням"
    }

    @ViewBuilder
    private func dailySectionRow(for item: AnalyticsTimeTotal) -> some View {
        if selectedMode == .time {
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
                dailySectionRowLabel(for: item)
            }
            .buttonStyle(.plain)
        } else if let tag = selectedTag {
            // В режиме Tags строки кликабельны: переход к списку расходов
            // с этим тегом за данный день/неделю/месяц.
            NavigationLink {
                TransactionListByKindView(
                    kind: .expense,
                    scope: tagBinScope(for: item, tag: tag)
                )
            } label: {
                dailySectionRowLabel(for: item)
            }
            .buttonStyle(.plain)
        } else {
            dailySectionRowLabel(for: item)
        }
    }

    /// Создаёт скоуп для конкретного бина (день/неделя/месяц) в режиме Tags.
    private func tagBinScope(for item: AnalyticsTimeTotal, tag: TransactionTag) -> AnalyticsScope {
        let calendar = Calendar.current
        let tagName = tag.name
        let binStart = item.date

        let binEndExclusive: Date
        switch tagBinGranularity {
        case .daily, nil:
            binEndExclusive = calendar.date(byAdding: .day, value: 1, to: binStart) ?? binStart
        case .weekly:
            binEndExclusive = calendar.date(byAdding: .day, value: 7, to: binStart) ?? binStart
        case .monthly:
            binEndExclusive = calendar.date(byAdding: .month, value: 1, to: binStart) ?? binStart
        }

        return AnalyticsScope(
            title: item.title,
            matches: { tx in
                tx.hasTag(tagName) &&
                tx.date >= binStart &&
                tx.date < binEndExclusive
            },
            containsDate: { date in
                date >= binStart && date < binEndExclusive
            }
        )
    }

    private func dailySectionRowLabel(for item: AnalyticsTimeTotal) -> some View {
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
                                HStack(spacing: 8) {
                                    if let categoryItem = categoryItem(for: item.category) {
                                        Circle()
                                            .fill(Color(hex: categoryItem.colorHex) ?? .gray)
                                            .frame(width: 24, height: 24)
                                            .overlay {
                                                Image(systemName: categoryItem.iconName)
                                                    .font(.system(size: 10, weight: .bold))
                                                    .foregroundStyle(.white)
                                            }
                                    }

                                    Text(item.category)

                                    Text(categoryPercentLabel(item.total))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(formattedRubAmount(item.total))
                                        .fontWeight(.semibold)

                                    Text("(\(item.count) всего)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
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
                            Text(formattedPercent(categoryShare(for: item.category)))
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
                    AxisMarks(position: .leading) { value in
                        AxisValueLabel {
                            if let name = value.as(String.self) {
                                let isSelected = selectedCategoryName == name
                                Text(name)
                                    .font(isSelected ? .caption.bold() : .caption)
                                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                            }
                        }
                    }
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
                .padding()
                .background(Color.gray.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .animation(.smooth(duration: 0.25), value: selectedCategoryName)
            }
        }
    }

    // MARK: - Interactive paging

    private struct PagingConfiguration {
        let livePixelsPerUnit: CGFloat
        let endPixelsPerUnit: CGFloat
        let unitSeconds: TimeInterval
        let minimumEndUnits: Double
        let maximumEndUnits: Double
        let fullPeriodUnits: Double
    }

    private var pagingConfiguration: PagingConfiguration {
        switch selectedScale {
        case .week:
            return PagingConfiguration(
                livePixelsPerUnit: 82,
                endPixelsPerUnit: 72,
                unitSeconds: 24 * 60 * 60,
                minimumEndUnits: 1,
                maximumEndUnits: 7,
                fullPeriodUnits: 7
            )

        case .month:
            return PagingConfiguration(
                livePixelsPerUnit: 40,
                endPixelsPerUnit: 34,
                unitSeconds: 24 * 60 * 60,
                minimumEndUnits: 2,
                maximumEndUnits: 31,
                fullPeriodUnits: 30
            )

        case .year:
            return PagingConfiguration(
                livePixelsPerUnit: 115,
                endPixelsPerUnit: 100,
                unitSeconds: 30 * 24 * 60 * 60,
                minimumEndUnits: 1,
                maximumEndUnits: 12,
                fullPeriodUnits: 12
            )
        }
    }

    private var latestAllowedAnchorDate: Date {
        AnalyticsSnapshotBuilder.makePage(for: selectedScale, anchorDate: .now).startDate
    }

    private func beginInteractivePaging() {
        guard pagingSessionStartAnchorDate == nil else { return }

        pagingSessionStartAnchorDate = pageAnchorDate
        selectedChartPointID = nil
        selectedCategoryName = nil
    }

    private func updateInteractivePaging(with translation: CGFloat) {
        guard let startAnchor = pagingSessionStartAnchorDate else { return }

        let config = pagingConfiguration
        let rawUnits = -Double(translation / config.livePixelsPerUnit)
        let limitedUnits = min(max(rawUnits, -config.maximumEndUnits), config.maximumEndUnits)

        let candidate = startAnchor.addingTimeInterval(limitedUnits * config.unitSeconds)
        pageAnchorDate = clampAnchorDate(candidate)
    }

    private func finishInteractivePaging(with swipeInfo: ProportionalSwipeInfo) -> PeriodSwipeResult {
        guard let startAnchor = pagingSessionStartAnchorDate else {
            return .cancelled
        }

        defer {
            pagingSessionStartAnchorDate = nil
        }

        let target = projectedAnchorDate(from: startAnchor, swipeInfo: swipeInfo)
        let clampedTarget = clampAnchorDate(target)
        let hitFutureBoundary = target > latestAllowedAnchorDate
        let finalAnchor = snappedAnchorDate(clampedTarget, scale: selectedScale)

        let animation = animation(for: swipeInfo)
        withAnimation(animation) {
            pageAnchorDate = finalAnchor
            selectedChartPointID = nil
            selectedCategoryName = nil
        }

        return hitFutureBoundary ? .blockedAtFuture : .applied
    }

    private func projectedAnchorDate(from startAnchor: Date, swipeInfo: ProportionalSwipeInfo) -> Date {
        let config = pagingConfiguration
        let absDistance = abs(swipeInfo.distance)
        let absVelocity = abs(swipeInfo.velocity)

        let baseUnits = Double(absDistance / config.endPixelsPerUnit)
        let velocityMultiplier = velocityMultiplier(for: absVelocity)

        let computedUnits = baseUnits * velocityMultiplier

        let finalUnits: Double
        switch swipeInfo.intensity {
        case .minimal:
            finalUnits = max(computedUnits, config.minimumEndUnits)

        case .light:
            finalUnits = min(
                max(computedUnits, config.minimumEndUnits),
                config.maximumEndUnits
            )

        case .medium:
            finalUnits = min(
                max(computedUnits * 1.12, config.minimumEndUnits),
                config.maximumEndUnits
            )

        case .strong:
            finalUnits = config.fullPeriodUnits
        }

        let signedUnits = swipeInfo.direction == .forward ? finalUnits : -finalUnits
        return startAnchor.addingTimeInterval(signedUnits * config.unitSeconds)
    }

    private func velocityMultiplier(for velocity: CGFloat) -> Double {
        switch velocity {
        case ..<500:
            return 1.0
        case 500..<900:
            return 1.22
        case 900..<1500:
            return 1.55
        case 1500..<2200:
            return 2.05
        default:
            return 2.65
        }
    }

    private func animation(for swipeInfo: ProportionalSwipeInfo) -> Animation {
        let absVelocity = abs(swipeInfo.velocity)

        let response: Double
        if absVelocity > 1500 {
            response = 0.24
        } else if absVelocity > 700 {
            response = 0.32
        } else {
            response = 0.44
        }

        return .spring(response: response, dampingFraction: 0.82)
    }

    private func clampAnchorDate(_ date: Date) -> Date {
        min(date, latestAllowedAnchorDate)
    }

    private func snappedAnchorDate(_ date: Date, scale: AnalyticsTimeScale) -> Date {
        let calendar = Calendar.current

        switch scale {
        case .week, .month:
            return calendar.startOfDay(for: date)

        case .year:
            return calendar.dateInterval(of: .month, for: date)?.start ?? date
        }
    }

    // MARK: - Period navigation

    private var canMoveToNextPeriod: Bool {
        let calendar = Calendar.current
        let nextAnchor: Date
        
        switch selectedScale {
        case .week:
            nextAnchor = calendar.date(byAdding: .weekOfYear, value: 1, to: pageAnchorDate) ?? pageAnchorDate
        case .month:
            nextAnchor = calendar.date(byAdding: .month, value: 1, to: pageAnchorDate) ?? pageAnchorDate
        case .year:
            nextAnchor = calendar.date(byAdding: .year, value: 1, to: pageAnchorDate) ?? pageAnchorDate
        }
        
        return nextAnchor <= latestAllowedAnchorDate
    }

    private func moveToPreviousPeriod() {
        let calendar = Calendar.current
        
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            switch selectedScale {
            case .week:
                pageAnchorDate = calendar.date(byAdding: .weekOfYear, value: -1, to: pageAnchorDate) ?? pageAnchorDate
            case .month:
                pageAnchorDate = calendar.date(byAdding: .month, value: -1, to: pageAnchorDate) ?? pageAnchorDate
            case .year:
                pageAnchorDate = calendar.date(byAdding: .year, value: -1, to: pageAnchorDate) ?? pageAnchorDate
            }
            
            selectedChartPointID = nil
            selectedCategoryName = nil
        }
    }

    private func moveToNextPeriod() {
        guard canMoveToNextPeriod else { return }
        
        let calendar = Calendar.current
        
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            switch selectedScale {
            case .week:
                pageAnchorDate = calendar.date(byAdding: .weekOfYear, value: 1, to: pageAnchorDate) ?? pageAnchorDate
            case .month:
                pageAnchorDate = calendar.date(byAdding: .month, value: 1, to: pageAnchorDate) ?? pageAnchorDate
            case .year:
                pageAnchorDate = calendar.date(byAdding: .year, value: 1, to: pageAnchorDate) ?? pageAnchorDate
            }
            
            pageAnchorDate = clampAnchorDate(pageAnchorDate)
            selectedChartPointID = nil
            selectedCategoryName = nil
        }
    }

    // MARK: - Trend / insights helpers

    private var trendDeltaFraction: Double? {
        guard previousSnapshot.averageExpensePerBin > 0 else { return nil }
        return (snapshot.averageExpensePerBin - previousSnapshot.averageExpensePerBin) / previousSnapshot.averageExpensePerBin
    }

    private var selectedCategoryPoint: AnalyticsCategoryTotal? {
        snapshot.categoryTotals.first { $0.category == selectedCategoryName }
    }

    // Доля категории в процентах с одним знаком: "92.3%".
    private func categoryPercentLabel(_ total: Double) -> String {
        guard snapshot.totalExpensesRub > 0 else { return "0%" }
        return String(format: "%.1f%%", total / snapshot.totalExpensesRub * 100)
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
            matches: { tx in tx.date >= interval.start && tx.date < interval.end },
            containsDate: { d in d >= interval.start && d < interval.end }
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
