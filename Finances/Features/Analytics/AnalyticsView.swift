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
    /// Интервал графика, выбранный вручную; nil — автоматический по длине метки.
    @State private var tagGranularityOverride: TagBinGranularity?

    @State private var selectedChartPointID: String?
    @State private var selectedCategoryName: String?
    @State private var lastHapticCategoryName: String?
    @State private var categoryNavigationTarget: String?
    /// Вид графика по категориям (выбор запоминается между запусками).
    @AppStorage("analytics.categoryChartStyle") private var categoryChartStyle: CategoryChartStyle = .bars
    /// Значение под пальцем на кольце категорий (накопленная сумма).
    @State private var donutSelectedValue: Double?
    /// Категории с подкатегориями раскрыты сразу, как в Alipay; здесь — свёрнутые вручную.
    @State private var collapsedCategories: Set<String> = []

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
                trackedRates: trackedRates,
                granularity: tagBinGranularity
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

    /// Гранулярность бинов для текущей выбранной метки: ручной выбор,
    /// если он допустим для её периода, иначе автоматическая.
    /// Используется для подзаголовков и форматирования "ДЕНЬ/НЕДЕЛЯ/МЕСЯЦ".
    private var tagBinGranularity: TagBinGranularity? {
        guard selectedMode == .tags, let tag = selectedTag else { return nil }
        let tagged = transactions.filter { $0.hasTag(tag.name) }
        if let tagGranularityOverride,
           TagAnalyticsBuilder.availableGranularities(for: tag, taggedTransactions: tagged).contains(tagGranularityOverride) {
            return tagGranularityOverride
        }
        return TagAnalyticsBuilder.granularity(for: tag, taggedTransactions: tagged)
    }

    /// Интервалы, между которыми можно переключать график метки.
    private var availableTagGranularities: [TagBinGranularity] {
        guard selectedMode == .tags, let tag = selectedTag else { return [] }
        let tagged = transactions.filter { $0.hasTag(tag.name) }
        return TagAnalyticsBuilder.availableGranularities(for: tag, taggedTransactions: tagged)
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
                        periodSummaryCards
                        topSummarySection
                        breakdownSections
                    } else {
                        // В режиме меток период задан самой меткой, поэтому
                        // W/M/Y и стрелки скрыты: сверху лента меток и карточка
                        // выбранной метки с итогами.
                        tagSelector
                        if let tag = selectedTag {
                            tagHeroCard(tag)
                            breakdownSections
                        }
                    }
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
            tagGranularityOverride = nil
            
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
    
    /// График и разбивки — общие для режимов времени и меток.
    @ViewBuilder
    private var breakdownSections: some View {
        chartSection

        // Разбивки идут одна за другой, без переключателя.
        dailySection
        categoryChartSection
        categorySection
        merchantSection
    }

    // MARK: - Tags mode

    private func tagColor(_ tag: TransactionTag) -> Color {
        tag.colorHex.flatMap { Color(hex: $0) } ?? .accentColor
    }

    /// Горизонтальная лента меток: переключение в одно касание.
    @ViewBuilder
    private var tagSelector: some View {
        if tags.isEmpty {
            tagsEmptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(tags) { tag in
                            tagChip(tag)
                                .id(tag.persistentModelID)
                        }

                        NavigationLink {
                            TagsManagementView()
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 34, height: 34)
                                .background(Color.gray.opacity(0.08), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Управление метками")
                    }
                }
                .scrollClipDisabled()
                .onAppear {
                    if let id = selectedTag?.persistentModelID {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
    }

    private func tagChip(_ tag: TransactionTag) -> some View {
        let isSelected = selectedTag?.persistentModelID == tag.persistentModelID
        let color = tagColor(tag)

        return Button {
            withAnimation(.snappy(duration: 0.25)) {
                selectedTag = tag
            }
        } label: {
            HStack(spacing: 6) {
                TagIconView(icon: tag.icon, colorHex: tag.colorHex, size: 26)
                Text(tag.name)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .lineLimit(1)
            }
            .padding(.leading, 4)
            .padding(.trailing, 12)
            .padding(.vertical, 4)
            .background(Capsule().fill(isSelected ? color.opacity(0.16) : Color.gray.opacity(0.08)))
            .overlay(Capsule().strokeBorder(isSelected ? color.opacity(0.55) : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var tagsEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tag")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.secondary)

            Text("Пока нет меток")
                .font(.headline)

            Text("Метки собирают траты поездки, проекта или события — здесь появится их аналитика.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            NavigationLink {
                TagsManagementView()
            } label: {
                Label("Создать метку", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal)
        .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    /// Карточка выбранной метки: иконка, период, сумма и ключевые цифры.
    /// При выборе бара на графике сумма переключается на этот бар.
    private func tagHeroCard(_ tag: TransactionTag) -> some View {
        let color = tagColor(tag)
        let selected = selectedChartPoint
        let days = tagPeriodDays
        let perDay = days > 0 ? snapshot.totalExpensesRub / Double(days) : 0

        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                TagIconView(icon: tag.icon, colorHex: tag.colorHex, size: 48)

                VStack(alignment: .leading, spacing: 2) {
                    Text(tag.name)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)

                    Text(tagPeriodLine(for: tag))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 4)

                if tag.contains(date: .now) {
                    Text("Сейчас")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(color.opacity(0.14), in: Capsule())
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(selected.map { "\(tagBinGranularity?.selectedPointTitle ?? "ПЕРИОД") · \($0.title)" } ?? "ПОТРАЧЕНО ВСЕГО")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .contentTransition(.opacity)

                Text(formattedRubAmount(selected?.total ?? snapshot.totalExpensesRub))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
            }

            HStack(spacing: 8) {
                tagMetric(title: "операций", value: "\(snapshot.expenseCount)")
                tagMetric(title: "в среднем за день", value: TagFormatting.rub(perDay))
                tagMetric(title: daysWord(days), value: "\(days)")
            }

            NavigationLink {
                TransactionListByKindView(
                    kind: .expense,
                    scope: currentAnalyticsScope
                )
            } label: {
                HStack {
                    Text("Все расходы по метке")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.gray.opacity(0.08))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(LinearGradient(
                            colors: [color.opacity(0.18), color.opacity(0.03)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                }
        }
        .animation(.snappy(duration: 0.25), value: selectedChartPointID)
    }

    /// Переключатель интервала графика метки: Дни / Недели / Месяцы.
    @ViewBuilder
    private var tagGranularityPicker: some View {
        let options = availableTagGranularities
        if options.count > 1, let current = tagBinGranularity {
            Picker(
                "Интервал",
                selection: Binding(
                    get: { current },
                    set: { newValue in
                        withAnimation(.snappy(duration: 0.25)) {
                            selectedChartPointID = nil
                            tagGranularityOverride = newValue
                        }
                    }
                )
            ) {
                ForEach(options, id: \.self) { option in
                    Text(option.shortTitle).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private func tagMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(.systemBackground).opacity(0.65), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// Явный период метки, а без него — фактический диапазон её операций.
    private func tagPeriodLine(for tag: TransactionTag) -> String {
        if let period = TagFormatting.period(of: tag) {
            return period
        }
        return snapshot.page.binCount > 0 ? snapshot.page.displayTitle : "Пока нет операций"
    }

    private func daysWord(_ count: Int) -> String {
        let mod10 = count % 10
        let mod100 = count % 100
        if mod10 == 1 && mod100 != 11 { return "день" }
        if (2...4).contains(mod10) && !(12...14).contains(mod100) { return "дня" }
        return "дней"
    }

    /// Сколько дней в эффективном периоде метки (до сегодня включительно).
    private var tagPeriodDays: Int {
        let page = snapshot.page
        guard page.binCount > 0 else { return 0 }
        let days = Calendar.current.dateComponents([.day], from: page.startDate, to: page.endDateExclusive).day ?? 0
        return max(days, 1)
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
    
    // Верхняя сводка — только для режима времени; у меток её роль играет карточка метки.
    private var topSummaryAmount: Double {
        // Если бар выбран — показываем его сумму.
        if let selected = selectedChartPoint {
            return selected.total
        }
        return snapshot.averageExpensePerBin
    }

    private var topSummaryTitle: String {
        if selectedChartPoint != nil {
            return selectedScale.selectedPointTitle
        }
        return selectedScale.averageTitle
    }

    private var topSummarySubtitle: String {
        if let selected = selectedChartPoint {
            // При выделенном баре показываем его название (день/неделю/месяц).
            return selected.title
        }
        return snapshot.page.displayTitle
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("График расходов")
                .font(.title3.bold())

            if selectedMode == .tags {
                tagGranularityPicker
            }

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
                // Год и режим меток — список строк.
                let items = snapshot.lowerTimeTotals
                let maxTotal = items.map(\.total).max() ?? 0
                VStack(spacing: 10) {
                    ForEach(items) { item in
                        dailySectionRow(for: item, maxTotal: maxTotal)
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
    private func dailySectionRow(for item: AnalyticsTimeTotal, maxTotal: Double) -> some View {
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
                tagBinRowLabel(for: item, maxTotal: maxTotal, color: tagColor(tag))
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

    /// Строка бина метки: сумма и полоска относительно самого дорогого бина.
    private func tagBinRowLabel(for item: AnalyticsTimeTotal, maxTotal: Double, color: Color) -> some View {
        let share = maxTotal > 0 ? min(max(item.total, 0) / maxTotal, 1) : 0

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(item.title)
                    .foregroundStyle(item.total > 0 ? Color.primary : Color.secondary)
                Spacer()
                Text(formattedRubAmount(item.total))
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(item.total > 0 ? Color.primary : Color.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(color.opacity(0.12))
                    Capsule()
                        .fill(color.opacity(0.85))
                        .frame(width: geometry.size.width * share)
                }
            }
            .frame(height: 4)
        }
        .padding()
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .contentShape(Rectangle())
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
                        categoryCard(item)
                    }
                }
            }
        }
    }

    /// Карточка категории. Категория с подкатегориями показывает плитки подкатегорий
    /// (как в Alipay) и сворачивается по тапу, остальные сразу ведут к операциям.
    private func categoryCard(_ item: AnalyticsCategoryTotal) -> some View {
        let isExpanded = !collapsedCategories.contains(item.category)

        return VStack(alignment: .leading, spacing: 12) {
            if item.subcategories.isEmpty {
                NavigationLink {
                    TransactionListByCategoryView(categoryTitle: item.category, scope: currentAnalyticsScope)
                } label: {
                    categoryHeader(item, accessory: "chevron.right")
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    withAnimation(.snappy(duration: 0.25)) {
                        if isExpanded {
                            collapsedCategories.insert(item.category)
                        } else {
                            collapsedCategories.remove(item.category)
                        }
                    }
                } label: {
                    categoryHeader(item, accessory: isExpanded ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(.plain)

                if isExpanded {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                        ForEach(item.subcategories) { subcategory in
                            NavigationLink {
                                TransactionListByCategoryView(
                                    categoryTitle: item.category,
                                    subcategoryTitle: subcategory.name,
                                    scope: currentAnalyticsScope
                                )
                            } label: {
                                subcategoryTile(subcategory, in: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    NavigationLink {
                        TransactionListByCategoryView(categoryTitle: item.category, scope: currentAnalyticsScope)
                    } label: {
                        HStack(spacing: 4) {
                            Text("Все операции категории")
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func categoryHeader(_ item: AnalyticsCategoryTotal, accessory: String) -> some View {
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

            Image(systemName: accessory)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    private func subcategoryTile(_ subcategory: AnalyticsSubcategoryTotal, in category: AnalyticsCategoryTotal) -> some View {
        let color = categoryItem(for: category.category).flatMap { Color(hex: $0.colorHex) } ?? .gray
        let share = category.total > 0 ? subcategory.total / category.total : 0

        return VStack(alignment: .leading, spacing: 6) {
            Text(subcategory.emoji ?? "•")
                .font(.title2)

            HStack(spacing: 2) {
                Text(subcategory.name)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)

            Text(formattedRubAmount(subcategory.total))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text("\(formattedPercent(share)) · \(subcategory.count) шт.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(color.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
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
            HStack {
                Text("График по категориям")
                    .font(.title3.bold())

                Spacer()

                // Вид графика: полосы, кольцо или лента — запоминается.
                Picker("Вид графика", selection: $categoryChartStyle.animation(.snappy(duration: 0.25))) {
                    ForEach(CategoryChartStyle.allCases) { style in
                        Image(systemName: style.iconName)
                            .accessibilityLabel(style.title)
                            .tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }

            if snapshot.categoryTotals.isEmpty {
                Text("Нет данных для выбранного периода")
                    .foregroundStyle(.secondary)
            } else {
                switch categoryChartStyle {
                case .bars:
                    categoryBarsChart
                case .donut:
                    categoryDonutChart
                case .strip:
                    categoryStripChart
                }
            }
        }
    }

    // Горизонтальные полосы с выбором пальцем (исходный вариант).
    private var categoryBarsChart: some View {
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

    /// Категории с положительной суммой — для кольца и ленты (доли не бывают отрицательными).
    private var positiveCategoryTotals: [AnalyticsCategoryTotal] {
        snapshot.categoryTotals.filter { $0.total > 0 }
    }

    private func categoryColor(_ name: String) -> Color {
        categoryItem(for: name).flatMap { Color(hex: $0.colorHex) } ?? .gray
    }

    // Кольцо: доли категорий, в центре — итог или выбранная категория.
    private var categoryDonutChart: some View {
        let items = positiveCategoryTotals
        let total = items.reduce(0) { $0 + $1.total }
        let selected = donutSelectedValue.flatMap { donutCategory(atCumulative: $0, in: items) }

        return VStack(spacing: 16) {
            Chart(items) { item in
                let isSelected = selected?.category == item.category

                SectorMark(
                    angle: .value("Сумма", item.total),
                    innerRadius: .ratio(0.62),
                    outerRadius: .ratio(isSelected ? 1 : 0.93),
                    angularInset: 1.5
                )
                .cornerRadius(4)
                .foregroundStyle(categoryColor(item.category))
                .opacity(selected == nil || isSelected ? 1 : 0.35)
            }
            .chartAngleSelection(value: $donutSelectedValue)
            .chartBackground { proxy in
                GeometryReader { geometry in
                    if let plotFrame = proxy.plotFrame {
                        let frame = geometry[plotFrame]
                        VStack(spacing: 2) {
                            Text(selected?.category ?? "Всего")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                            Text(TagFormatting.rub(selected?.total ?? total))
                                .font(.title3.weight(.bold))
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)

                            if let selected {
                                Text(formattedPercent(total > 0 ? selected.total / total : 0))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: frame.width * 0.55)
                        .position(x: frame.midX, y: frame.midY)
                    }
                }
            }
            .frame(height: 240)
            .sensoryFeedback(.selection, trigger: selected?.category)

            categoryLegend(items, total: total)
        }
        .padding()
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .animation(.smooth(duration: 0.25), value: selected?.category)
    }

    private func donutCategory(atCumulative value: Double, in items: [AnalyticsCategoryTotal]) -> AnalyticsCategoryTotal? {
        var accumulated = 0.0
        for item in items {
            accumulated += item.total
            if value <= accumulated {
                return item
            }
        }
        return items.last
    }

    // Лента: одна полоса 100%, поделённая на категории, и легенда под ней.
    private var categoryStripChart: some View {
        let items = positiveCategoryTotals
        let total = items.reduce(0) { $0 + $1.total }
        let gap: CGFloat = 2

        return VStack(alignment: .leading, spacing: 16) {
            GeometryReader { geometry in
                let available = max(geometry.size.width - gap * CGFloat(max(items.count - 1, 0)), 0)

                HStack(spacing: gap) {
                    ForEach(items) { item in
                        Rectangle()
                            .fill(categoryColor(item.category))
                            .frame(width: total > 0 ? max(available * CGFloat(item.total / total), 2) : 0)
                    }
                }
            }
            .frame(height: 28)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            categoryLegend(items, total: total)
        }
        .padding()
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    /// Легенда в две колонки: цвет, категория, доля. Тап — операции категории.
    private func categoryLegend(_ items: [AnalyticsCategoryTotal], total: Double) -> some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
            alignment: .leading,
            spacing: 10
        ) {
            ForEach(items) { item in
                Button {
                    categoryNavigationTarget = item.category
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(categoryColor(item.category))
                            .frame(width: 8, height: 8)

                        Text(item.category)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Spacer(minLength: 4)

                        Text(formattedPercent(total > 0 ? item.total / total : 0))
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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

/// Варианты отображения графика по категориям.
enum CategoryChartStyle: String, CaseIterable, Identifiable {
    case bars
    case donut
    case strip

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bars: return "Полосы"
        case .donut: return "Кольцо"
        case .strip: return "Лента"
        }
    }

    var iconName: String {
        switch self {
        case .bars: return "chart.bar.xaxis"
        case .donut: return "chart.pie.fill"
        case .strip: return "rectangle.split.3x1.fill"
        }
    }
}
