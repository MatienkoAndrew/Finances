import SwiftUI
import SwiftData
import Charts

struct AnalyticsView: View {
    @AllTransactions
    private var allTransactions: [Transaction]

    /// Аналитика по выборке из списка операций: только подходящие под фильтр.
    private let transactionFilter: TransactionFilter?

    /// Подходит ли операция под фильтр выборки (без фильтра — любая).
    private var filterMatches: (Transaction) -> Bool {
        guard let transactionFilter else { return { _ in true } }
        let interval = transactionFilter.dateInterval()
        return { transactionFilter.matches($0, interval: interval) }
    }

    @Query(sort: \ExpenseCategoryItem.name, order: .forward)
    private var categories: [ExpenseCategoryItem]

    @Query(sort: \TrackedExchangeRate.code, order: .forward)
    private var trackedRates: [TrackedExchangeRate]
    
    @Query(sort: \TransactionTag.createdAt, order: .reverse)
    private var tags: [TransactionTag]

    @Query
    private var settingsList: [AppSettings]

    @State private var selectedMode: AnalyticsViewMode = .time
    @State private var selectedScale: AnalyticsTimeScale = .month
    @State private var pageAnchorDate: Date = .now
    
    // Для режима Tags
    @State private var selectedTag: TransactionTag?
    /// Интервал графика, выбранный вручную; nil — автоматический по длине метки.
    @State private var tagGranularityOverride: TagBinGranularity?

    @State private var categoryNavigationTarget: String?
    /// Свёрнут ли раздел «По дням / неделям / месяцам» (запоминается).
    @AppStorage("analytics.dailySectionCollapsed") private var isDailySectionCollapsed = false
    /// Вид графика по категориям (выбор запоминается между запусками).
    @AppStorage("analytics.categoryChartStyle") private var categoryChartStyle: CategoryChartStyle = .bars
    /// Порядок строк в списке категорий (запоминается).
    @AppStorage(CategoryListSort.storageKey) private var categorySort: CategoryListSort = .amount
    @State private var isShowingPeriodPicker = false

    /// Самый ранний год с операциями — граница выбора месяца.
    private var earliestYear: Int {
        let calendar = Calendar.current
        let current = calendar.component(.year, from: .now)
        return allTransactions.map(\.date).min().map { calendar.component(.year, from: $0) } ?? current
    }
    /// Категории с подкатегориями раскрыты сразу, как в Alipay; здесь — свёрнутые вручную.
    @State private var collapsedCategories: Set<String> = []

    @State private var didInitializeAnchor = false
    @AppStorage(ReconciliationStatus.visibilityKey) private var isReconciliationVisible = true

    /// Аналитика одной метки — открыта из её экрана: без ленты меток и
    /// переключателя режимов, внутри уже существующей навигации.
    private let focusedTag: TransactionTag?
    /// Открыт внутри чужой навигации (из метки или из сводки на экране
    /// транзакций): без своего NavigationStack и без переключателя меток.
    private let isEmbedded: Bool

    init(focusedTag: TransactionTag? = nil) {
        self.focusedTag = focusedTag
        transactionFilter = nil
        isEmbedded = focusedTag != nil
        _selectedMode = State(initialValue: focusedTag == nil ? .time : .tags)
        _selectedTag = State(initialValue: focusedTag)
    }

    /// Аналитика месяца — открыта из сводки на экране транзакций.
    init(month: Date, filter: TransactionFilter? = nil) {
        focusedTag = nil
        transactionFilter = filter
        isEmbedded = true
        _selectedScale = State(initialValue: .month)
        _pageAnchorDate = State(initialValue: AnalyticsSnapshotBuilder.makePage(for: .month, anchorDate: month).startDate)
        _didInitializeAnchor = State(initialValue: true)
    }

    private var settings: AppSettings? {
        settingsList.first
    }
    
    // MARK: - Report

    /// Всё, что показывает экран, — посчитанное один раз за отрисовку.
    ///
    /// Раньше снапшот был вычисляемым свойством, и каждое обращение к нему
    /// (шапка, строки категорий и мест, ссылки на списки — за отрисовку их
    /// набиралось больше сотни) заново проходило по всем операциям. Экран замирал
    /// на доли секунды, и не только открытый: вкладка перерисовывается при каждом
    /// сохранении в базу, даже когда на экране другая.
    private struct Report {
        let snapshot: AnalyticsSnapshot
        /// Тот же масштаб периодом раньше — для плашки тренда (режим времени).
        let previousSnapshot: AnalyticsSnapshot?
        /// Вся история столбиками — для прокручиваемого графика (режим времени).
        let timeline: ExpenseTimelineData?
        /// Интервал графика метки: ручной выбор, если он допустим для её периода,
        /// иначе автоматический. Нужен для подзаголовков «ДЕНЬ/НЕДЕЛЯ/МЕСЯЦ».
        let tagGranularity: TagBinGranularity?
        /// Интервалы, между которыми можно переключать график метки.
        let availableTagGranularities: [TagBinGranularity]
        /// Какие операции показывают списки по ссылкам: все расходы, категория, место.
        let scope: AnalyticsScope
        /// Траты метки по дням (начало дня → ₽) — для клеток в строках недель.
        var tagDailyTotals: [Date: Double] = [:]
        /// «Что изменилось»: разница с прошлым периодом по категориям (режим времени).
        var comparison: AnalyticsPeriodComparison? = nil
        /// «Kaspi сверена по 18 ноября · 3 оплаты Apple Pay ждут выписку» —
        /// когда данные периода могут быть неполными; nil — период сверен целиком.
        var coverageNote: String? = nil
        /// Цифры поездки: полная стоимость и траты в день за дни пребывания (режим меток).
        var tripStats: TripStats? = nil
    }

    private func coverageNote(for page: AnalyticsPeriodPage) -> String? {
        // Скрытый статус не считаем вовсе.
        guard isReconciliationVisible else { return nil }
        let status = ReconciliationStatus.cached(transactions: allTransactions)
        let awaiting = status.awaitingStatement.filter { page.contains($0.date) }.count
        guard !status.isFullyCovered(start: page.startDate, endExclusive: page.endDateExclusive) || awaiting > 0 else {
            return nil
        }
        var parts = [status.coverageLine]
        if awaiting > 0 {
            let word = ReconciliationStatus.word(awaiting, "оплата", "оплаты", "оплат")
            parts.append("\(awaiting) \(word) Apple Pay \(awaiting == 1 ? "ждёт" : "ждут") выписку")
        }
        return parts.joined(separator: " · ")
    }

    private func makeReport() -> Report {
        // Курсовые разницы считаются внутри своих покупок — пары ищутся один раз на отчёт.
        // Пары ищутся по всем операциям: курсовая разница или возврат могут не попасть в фильтр.
        let folded = ExchangeRateDifferenceMatcher.fold(allTransactions)
        let filterMatches = filterMatches
        let transactions = transactionFilter == nil ? allTransactions : allTransactions.filter(filterMatches)

        switch selectedMode {
        case .time:
            let snapshot = AnalyticsSnapshotBuilder.build(
                transactions: transactions,
                scale: selectedScale,
                anchorDate: pageAnchorDate,
                settings: settings,
                trackedRates: trackedRates,
                folded: folded
            )
            let page = snapshot.page

            return Report(
                snapshot: snapshot,
                previousSnapshot: AnalyticsSnapshotBuilder.build(
                    transactions: transactions,
                    scale: selectedScale,
                    anchorDate: previousAnchorDate,
                    settings: settings,
                    trackedRates: trackedRates,
                    folded: folded
                ),
                timeline: ExpenseTimelineData.build(
                    transactions: transactions,
                    scale: selectedScale,
                    pageStart: page.startDate,
                    settings: settings,
                    trackedRates: trackedRates,
                    folded: folded
                ),
                tagGranularity: nil,
                availableTagGranularities: [],
                scope: AnalyticsScope(
                    title: page.displayTitle,
                    matches: { tx in page.contains(tx.date) && filterMatches(tx) },
                    containsDate: { date in page.contains(date) }
                ),
                comparison: AnalyticsPeriodComparisonBuilder.build(
                    transactions: transactions,
                    scale: selectedScale,
                    page: page,
                    settings: settings,
                    trackedRates: trackedRates,
                    folded: folded,
                    restrict: transactionFilter == nil ? nil : filterMatches
                ),
                coverageNote: coverageNote(for: page)
            )

        case .tags:
            guard let tag = selectedTag else {
                let emptyPage = AnalyticsPeriodPage(
                    startDate: .now,
                    endDateExclusive: .now,
                    displayTitle: "Нет метки",
                    binCount: 0
                )
                return Report(
                    snapshot: AnalyticsSnapshot.empty(for: emptyPage),
                    previousSnapshot: nil,
                    timeline: nil,
                    tagGranularity: nil,
                    availableTagGranularities: [],
                    scope: AnalyticsScope(
                        title: "Нет метки",
                        matches: { _ in false },
                        containsDate: { _ in false }
                    )
                )
            }

            let tagged = transactions.filter { $0.hasTag(tag.name) }
            let available = TagAnalyticsBuilder.availableGranularities(for: tag, taggedTransactions: tagged)
            let granularity: TagBinGranularity?
            if let tagGranularityOverride, available.contains(tagGranularityOverride) {
                granularity = tagGranularityOverride
            } else if available.contains(.daily) {
                // По умолчанию — дни (календарь), если период не слишком длинный.
                granularity = .daily
            } else {
                granularity = TagAnalyticsBuilder.granularity(for: tag, taggedTransactions: tagged)
            }

            // Для недель нужны ещё и траты по дням — клетки Пн–Вс в каждой строке.
            var dailyTotals: [Date: Double] = [:]
            if granularity == .weekly {
                let daily = TagAnalyticsBuilder.buildSnapshot(
                    tag: tag,
                    transactions: tagged,
                    settings: settings,
                    trackedRates: trackedRates,
                    granularity: .daily,
                    folded: folded
                )
                for point in daily.chartPoints {
                    dailyTotals[Calendar.current.startOfDay(for: point.date)] = point.total
                }
            }

            // В режиме Tags строим снапшот по эффективному периоду метки
            // (без пустых дней до/после) с авто-гранулярностью бинов.
            return Report(
                snapshot: TagAnalyticsBuilder.buildSnapshot(
                    tag: tag,
                    transactions: tagged,
                    settings: settings,
                    trackedRates: trackedRates,
                    granularity: granularity,
                    folded: folded
                ),
                previousSnapshot: nil,
                timeline: nil,
                tagGranularity: granularity,
                availableTagGranularities: available,
                scope: tagScope(for: tag, taggedTransactions: tagged),
                tagDailyTotals: dailyTotals,
                tripStats: TripStats.make(
                    tag: tag,
                    transactions: tagged,
                    settings: settings,
                    trackedRates: trackedRates,
                    folded: folded
                )
            )
        }
    }

    /// Последний посчитанный отчёт — для скрытой вкладки.
    private final class ReportCache {
        var report: Report?
    }

    @State private var reportCache = ReportCache()
    @Environment(\.isTabVisible) private var isTabVisible

    /// Пока вкладка скрыта, после сохранений в базу отчёт не пересчитывается:
    /// это несколько проходов по всем операциям, а экрана всё равно не видно.
    /// Открыли вкладку — отчёт строится заново по свежим данным.
    private func currentReport() -> Report {
        if !isTabVisible, let cached = reportCache.report {
            return cached
        }
        let report = makeReport()
        reportCache.report = report
        return report
    }

    /// Начало периода того же масштаба, но раньше — для сравнения в шапке.
    private var previousAnchorDate: Date {
        let calendar = Calendar.current

        switch selectedScale {
        case .week:
            return calendar.date(byAdding: .weekOfYear, value: -1, to: pageAnchorDate) ?? pageAnchorDate
        case .month:
            return calendar.date(byAdding: .month, value: -1, to: pageAnchorDate) ?? pageAnchorDate
        case .year:
            return calendar.date(byAdding: .year, value: -1, to: pageAnchorDate) ?? pageAnchorDate
        }
    }

    /// В режиме меток drill-down должен показывать ТОЛЬКО транзакции
    /// с этим тегом — иначе после ручного снятия метки транзакция
    /// продолжала бы всплывать в детализации по диапазону дат.
    private func tagScope(for tag: TransactionTag, taggedTransactions: [Transaction]) -> AnalyticsScope {
        let tagName = tag.name
        // Тот же период, что и у снапшота: даты метки, расширенные до дат
        // помеченных транзакций (билет, купленный до поездки, тоже виден).
        guard let period = TagAnalyticsBuilder.effectivePeriod(
            for: tag,
            taggedTransactions: taggedTransactions
        ) else {
            return AnalyticsScope(
                title: tag.name,
                matches: { tx in tx.hasTag(tagName) },
                containsDate: { _ in true }
            )
        }
        let start = period.start
        let endExclusive = period.endExclusive
        return AnalyticsScope(
            title: tag.name,
            matches: { tx in
                tx.hasTag(tagName) && tx.date >= start && tx.date < endExclusive
            },
            containsDate: { date in date >= start && date < endExclusive }
        )
    }

    /// Смена метки или интервала пересоздаёт график (сбрасывает выбор столбика).
    private func tagChartIdentity(_ report: Report) -> String {
        let name = selectedTag?.name ?? ""
        let granularity = report.tagGranularity?.shortTitle ?? ""
        return name + "|" + granularity
    }

    var body: some View {
        let report = currentReport()

        if isEmbedded {
            content(report)
                .navigationTitle(transactionFilter == nil ? "Аналитика" : "Аналитика выборки")
        } else {
            NavigationStack {
                content(report)
            }
        }
    }

    /// Кнопки разделов закреплены, когда есть отчёт: в режиме меток — при выбранной метке.
    private var showsSectionBar: Bool {
        selectedMode == .time || selectedTag != nil
    }

    private func content(_ report: Report) -> some View {
        ScrollViewReader { proxy in
            reportScroll(report)
                .safeAreaInset(edge: .top, spacing: 0) {
                    if showsSectionBar {
                        AnalyticsSectionBar(dailyTitle: dailySectionTitle(report)) { section in
                            if section == .daily, isDailySectionCollapsed {
                                isDailySectionCollapsed = false
                            }
                            // Ленивый стек не знает высот непостроенных разделов: первый
                            // переход их строит и встаёт примерно, второй — точно на раздел.
                            proxy.scrollTo(section, anchor: .top)
                            DispatchQueue.main.async {
                                withAnimation(.snappy(duration: 0.25)) {
                                    proxy.scrollTo(section, anchor: .top)
                                }
                            }
                        }
                    }
                }
        }
    }

    private func reportScroll(_ report: Report) -> some View {
        ScrollView {
            // Ленивый стек: при смене масштаба строятся только видимые разделы.
            LazyVStack(alignment: .leading, spacing: 24) {
                if selectedMode == .time {
                    periodHeroCard(report)
                        .id(AnalyticsReportSection.overview)
                    breakdownSections(report)
                    comparisonSection(report)
                } else {
                    // В режиме меток период задан самой меткой, поэтому
                    // W/M/Y и стрелки скрыты: сверху лента меток и карточка
                    // выбранной метки с итогами.
                    if focusedTag == nil {
                        tagSelector
                    }
                    if let tag = selectedTag {
                        tagHeroCard(tag, report: report)
                            .id(AnalyticsReportSection.overview)
                        breakdownSections(report)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if selectedMode == .time {
                ToolbarItem(placement: .principal) {
                    AnalyticsScaleTabs(selection: Binding(
                        get: { selectedScale },
                        set: { selectScale($0) }
                    ))
                }
            }
            if !isEmbedded {
                ToolbarItem(placement: .topBarTrailing) {
                    tagToggleButton
                }
            }
        }
        // Переход из графика и легенды категорий. Скрытая NavigationLink(isActive:)
        // при быстром «назад» и новом касании оставляла пустую страницу.
        .sheet(isPresented: $isShowingPeriodPicker) {
            AnalyticsPeriodPickerSheet(
                scale: selectedScale,
                current: report.snapshot.page.startDate,
                earliestYear: earliestYear
            ) { date in
                withAnimation(.snappy(duration: 0.3)) {
                    pageAnchorDate = snappedAnchorDate(clampAnchorDate(date), scale: selectedScale)
                }
            }
        }
        .navigationDestination(item: $categoryNavigationTarget) { categoryTitle in
            TransactionListByCategoryView(
                categoryTitle: categoryTitle,
                scope: report.scope
            )
        }
        .onAppear {
            guard !didInitializeAnchor else { return }
            didInitializeAnchor = true
            pageAnchorDate = latestAllowedAnchorDate
        }
        .onChange(of: selectedMode) { _, newMode in
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
    private func breakdownSections(_ report: Report) -> some View {
        chartSection(report)

        // Разбивки идут одна за другой, без переключателя.
        dailySection(report)
            .id(AnalyticsReportSection.daily)
        categorySection(report)
            .id(AnalyticsReportSection.categories)
        merchantSection(report)
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
                                .background(Color(.secondarySystemGroupedBackground), in: Circle())
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
            .background(Capsule().fill(isSelected ? color.opacity(0.16) : Color(.secondarySystemGroupedBackground)))
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
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    /// Карточка выбранной метки: иконка, период, сумма и ключевые цифры.
    private func tagHeroCard(_ tag: TransactionTag, report: Report) -> some View {
        let snapshot = report.snapshot
        let color = tagColor(tag)
        // Дни и траты в день — только за дни пребывания: заранее купленный билет
        // входит в полную стоимость, но не растягивает поездку.
        let trip = report.tripStats
        let days = trip?.stayDays ?? tagPeriodDays(snapshot)
        let perDay = trip?.perDayOnSite ?? (days > 0 ? snapshot.totalExpensesRub / Double(days) : 0)

        return VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                TagIconView(icon: tag.icon, colorHex: tag.colorHex, size: 48)

                VStack(alignment: .leading, spacing: 2) {
                    Text(tag.name)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)

                    Text(tagPeriodLine(for: tag, snapshot: snapshot))
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

            VStack(alignment: .leading, spacing: 6) {
                Text("ПОТРАЧЕНО ВСЕГО")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                heroAmount(snapshot.totalExpensesRub)
            }

            if let trip, trip.beforeRub >= 0.5 {
                Text("Включая \(TagFormatting.rub(trip.beforeRub)) до поездки — билеты и брони")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                AnalyticsMetricTile(value: "\(snapshot.expenseCount)", title: operationsWord(snapshot.expenseCount))
                AnalyticsMetricTile(value: TagFormatting.rub(perDay), title: "в день на месте")
                AnalyticsMetricTile(value: "\(days)", title: daysWord(days))
            }

            NavigationLink {
                TransactionListByKindView(
                    kind: .expense,
                    scope: report.scope
                )
            } label: {
                heroLinkLabel("Все расходы по метке", color: color)
            }
            .buttonStyle(.plain)

            if tags.count > 1 {
                NavigationLink {
                    TripComparisonView(initialTagName: tag.name)
                } label: {
                    heroLinkLabel("Сравнить с другой поездкой", color: color)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(heroBackground(color))
    }

    /// Переключатель интервала графика метки: Дни / Недели / Месяцы.
    @ViewBuilder
    private func tagGranularityPicker(_ report: Report) -> some View {
        let options = report.availableTagGranularities
        if options.count > 1, let current = report.tagGranularity {
            Picker(
                "Интервал",
                selection: Binding(
                    get: { current },
                    set: { newValue in
                        withAnimation(.snappy(duration: 0.25)) {
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

    /// Явный период метки, а без него — фактический диапазон её операций.
    private func tagPeriodLine(for tag: TransactionTag, snapshot: AnalyticsSnapshot) -> String {
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
    private func tagPeriodDays(_ snapshot: AnalyticsSnapshot) -> Int {
        let page = snapshot.page
        guard page.binCount > 0 else { return 0 }
        let days = Calendar.current.dateComponents([.day], from: page.startDate, to: page.endDateExclusive).day ?? 0
        return max(days, 1)
    }

    // MARK: - Hero

    /// Шапка периода: переключение страниц, итог, тренд к прошлому периоду
    /// и ключевые цифры.
    private func periodHeroCard(_ report: Report) -> some View {
        let snapshot = report.snapshot
        let isYear = selectedScale == .year

        return VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                periodArrow("chevron.left", isEnabled: true, action: moveToPreviousPeriod)
                    .accessibilityLabel("Предыдущий период")

                Spacer(minLength: 0)

                // Название периода — кнопка выбора месяца (или года).
                Button {
                    isShowingPeriodPicker = true
                } label: {
                    HStack(spacing: 4) {
                        Text(snapshot.page.displayTitle)
                            .font(.headline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .contentTransition(.opacity)
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(.tertiarySystemFill), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Выбрать месяц и год")

                Spacer(minLength: 0)

                periodArrow("chevron.right", isEnabled: canMoveToNextPeriod, action: moveToNextPeriod)
                    .accessibilityLabel("Следующий период")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("ПОТРАЧЕНО")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                heroAmount(snapshot.totalExpensesRub)

                if let delta = trendDeltaFraction(report), abs(delta) >= 0.005 {
                    HStack(spacing: 6) {
                        AnalyticsTrendBadge(delta: delta)
                        Text(trendCaption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .transition(.opacity)
                }
            }

            HStack(spacing: 8) {
                AnalyticsMetricTile(
                    value: "\(snapshot.expenseCount)",
                    title: operationsWord(snapshot.expenseCount)
                )
                AnalyticsMetricTile(
                    value: TagFormatting.rub(snapshot.averageExpensePerBin),
                    title: isYear ? "в месяц" : "в день"
                )
                AnalyticsMetricTile(
                    value: snapshot.peakChartPoint.flatMap { $0.total > 0 ? TagFormatting.rub($0.total) : nil } ?? "—",
                    title: "максимум"
                )
            }

            if isReconciliationVisible, let note = report.coverageNote {
                HStack(alignment: .top, spacing: 8) {
                    Label(note, systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Button {
                        withAnimation { isReconciliationVisible = false }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Скрыть статус сверки")
                }
            }

            NavigationLink {
                TransactionListByKindView(
                    kind: .expense,
                    scope: report.scope
                )
            } label: {
                heroLinkLabel("Все расходы за период", color: .red)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(heroBackground(.red))
        .animation(.snappy(duration: 0.25), value: snapshot.page.startDate)
    }

    private func periodArrow(_ systemImage: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(isEnabled ? Color.primary : Color.secondary.opacity(0.35))
                .frame(width: 34, height: 34)
                .background(Color(.tertiarySystemFill), in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    /// Крупная сумма: рубли жирно, копейки и знак — мельче и светлее.
    private func heroAmount(_ value: Double) -> some View {
        let text = formattedRubAmount(value)
        let parts = text.split(separator: ",", maxSplits: 1).map(String.init)
        let whole = parts.first ?? text
        let fraction = parts.count > 1 ? "," + parts[1] : ""

        return (
            Text(whole)
                .font(.system(size: 40, weight: .bold, design: .rounded))
            + Text(fraction)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        )
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .contentTransition(.numericText(value: value))
    }

    private func heroLinkLabel(_ title: String, color: Color) -> some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
    }

    private func heroBackground(_ color: Color) -> some View {
        AnalyticsHeroBackground(color: color)
    }

    private var trendCaption: String {
        switch selectedScale {
        case .week: return "в день к прошлой неделе"
        case .month: return "в день к прошлому месяцу"
        case .year: return "в месяц к прошлому году"
        }
    }

    private func operationsWord(_ count: Int) -> String {
        let mod10 = count % 10
        let mod100 = count % 100
        if mod10 == 1 && mod100 != 11 { return "операция" }
        if (2...4).contains(mod10) && !(12...14).contains(mod100) { return "операции" }
        return "операций"
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.title3.weight(.semibold))
            .padding(.horizontal, 4)
    }

    // MARK: - Comparison

    @ViewBuilder
    private func comparisonSection(_ report: Report) -> some View {
        if let comparison = report.comparison {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("Что изменилось")
                AnalyticsComparisonCard(
                    comparison: comparison,
                    categoryItem: { categoryItem(for: $0) }
                )
            }
        }
    }

    // MARK: - Expense chart

    private func chartSection(_ report: Report) -> some View {
        let snapshot = report.snapshot

        return VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Динамика")

            VStack(alignment: .leading, spacing: 14) {
                if selectedMode == .tags {
                    tagGranularityPicker(report)
                }

                if let timeline = report.timeline {
                    // Вся история одной лентой: листается пальцем, как в «Здоровье»,
                    // и доводится до границы недели / месяца / года.
                    ExpenseBarChart(
                        bars: timeline.bars,
                        domain: timeline.domain,
                        averageTitle: selectedScale.averageTitle,
                        timeline: ExpenseChartTimeline(
                            scale: selectedScale,
                            pageStart: snapshot.page.startDate,
                            onPageSettled: settlePage(at:)
                        )
                    )
                    .id(selectedScale)
                } else if let first = snapshot.chartPoints.first {
                    let points = snapshot.chartPoints
                    let pageEnd = snapshot.page.endDateExclusive
                    let bars = points.enumerated().map { index, point in
                        ExpenseBar(
                            start: point.date,
                            end: index + 1 < points.count ? points[index + 1].date : pageEnd,
                            total: point.total,
                            title: point.title
                        )
                    }
                    ExpenseBarChart(
                        bars: bars,
                        domain: first.date..<pageEnd,
                        averageTitle: report.tagGranularity?.averageTitle ?? "СРЕДНЕЕ",
                        rangeTitle: snapshot.page.displayTitle,
                        axisLabels: points.map(\.axisLabel),
                        tint: selectedTag.map(tagColor) ?? .red
                    )
                    .id(tagChartIdentity(report))
                } else {
                    emptyText("Нет расходов для выбранного периода")
                }
            }
            .analyticsCard()
        }
    }

    private func emptyText(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
    }

    // MARK: - Lower sections

    private func dailySection(_ report: Report) -> some View {
        let snapshot = report.snapshot

        return VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.snappy(duration: 0.25)) {
                    isDailySectionCollapsed.toggle()
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(dailySectionTitle(report))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)

                    Spacer()

                    // В свёрнутом виде — самый дорогой день/неделя/месяц.
                    if isDailySectionCollapsed, let peak = snapshot.peakChartPoint, peak.total > 0 {
                        Text("макс. \(TagFormatting.rub(peak.total))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    Image(systemName: "chevron.down")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isDailySectionCollapsed ? -90 : 0))
                }
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(isDailySectionCollapsed ? "Развернуть" : "Свернуть")

            if !isDailySectionCollapsed {
                Group {
                    if snapshot.chartPoints.isEmpty {
                        emptyText("Нет расходов для выбранного периода")
                            .analyticsCard()
                    } else if selectedMode == .time && selectedScale != .year {
                        // Неделя — одна строка той же сетки, что и у месяца.
                        dailyCalendar(snapshot)
                            .analyticsCard(padding: 12)
                    } else if selectedMode == .tags,
                              report.tagGranularity == .daily,
                              let tag = selectedTag {
                        // Метка по дням — тот же календарь, но только траты с меткой.
                        dailyCalendar(snapshot, tag: tag)
                            .analyticsCard(padding: 12)
                    } else if selectedMode == .tags,
                              report.tagGranularity == .weekly,
                              let tag = selectedTag {
                        weekRows(report, tag: tag)
                            .analyticsCard(padding: 12)
                    } else if (selectedMode == .tags && report.tagGranularity == .monthly)
                                || (selectedMode == .time && selectedScale == .year) {
                        monthTiles(snapshot, tag: selectedMode == .tags ? selectedTag : nil)
                            .analyticsCard(padding: 12)
                    } else {
                        // Год, недели и месяцы метки — список строк.
                        timeTotalsList(report)
                    }
                }
                .transition(.opacity)
            }
        }
    }

    // Неделя и месяц: сетка-календарь с суммой по дням и подсветкой по интенсивности трат.
    /// `tag` задан в режиме меток: клетка открывает только траты с меткой,
    /// а если период захватывает несколько месяцев, первое число подписано месяцем.
    private func dailyCalendar(_ snapshot: AnalyticsSnapshot, tag: TransactionTag? = nil) -> some View {
        var calendar = Calendar.current
        calendar.locale = Locale(identifier: "ru_RU")

        let points = snapshot.chartPoints
        let maxTotal = max(points.map(\.total).max() ?? 0, 1)
        let leadingBlanks = points.first.map { first in
            (calendar.component(.weekday, from: first.date) - calendar.firstWeekday + 7) % 7
        } ?? 0
        let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)
        let spansMonths: Bool = {
            guard tag != nil, let first = points.first, let last = points.last else { return false }
            return !calendar.isDate(first.date, equalTo: last.date, toGranularity: .month)
        }()

        return VStack(spacing: 8) {
            HStack(spacing: 5) {
                ForEach(orderedWeekdaySymbols(calendar), id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: columns, spacing: 5) {
                ForEach(0..<leadingBlanks, id: \.self) { _ in
                    Color.clear.frame(height: 48)
                }

                ForEach(points) { point in
                    monthDayCell(
                        point,
                        maxTotal: maxTotal,
                        calendar: calendar,
                        tag: tag,
                        showsMonth: spansMonths && (
                            point.id == points.first?.id ||
                            calendar.component(.day, from: point.date) == 1
                        )
                    )
                }
            }
        }
    }

    private func monthDayCell(
        _ point: AnalyticsChartPoint,
        maxTotal: Double,
        calendar: Calendar,
        tag: TransactionTag? = nil,
        showsMonth: Bool = false
    ) -> some View {
        let day = calendar.component(.day, from: point.date)
        let dayLabel: String = {
            guard showsMonth else { return "\(day)" }
            let month = AnalyticsDateFormat.monthShort.string(from: point.date)
                .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return "\(day) \(month)"
        }()
        let hasSpend = point.total > 0
        let intensity = hasSpend ? min(point.total / maxTotal, 1) : 0
        let isToday = calendar.isDateInToday(point.date)
        let isFuture = point.date > .now
        let background = hasSpend
            ? Color.red.opacity(0.10 + 0.45 * intensity)
            : Color(.tertiarySystemFill).opacity(0.5)

        return NavigationLink {
            if let tag {
                TransactionListByKindView(
                    kind: .expense,
                    scope: tagBinScope(
                        for: AnalyticsTimeTotal(id: point.id, date: point.date, title: point.title, total: point.total),
                        tag: tag,
                        granularity: .daily
                    )
                )
            } else {
                TransactionListByDateView(date: point.date)
            }
        } label: {
            VStack(spacing: 2) {
                Text(dayLabel)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(intensity > 0.6 ? Color.white : Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Text(hasSpend ? dayCellAmount(point.total) : " ")
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(intensity > 0.6 ? Color.white.opacity(0.9) : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                if isToday {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.red, lineWidth: 1.5)
                }
            }
            .opacity(isFuture ? 0.4 : 1)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Weeks & months

    private static let weekLabelWidth: CGFloat = 78
    private static let weekAmountWidth: CGFloat = 64

    /// Недели метки: строка на неделю — даты, семь клеток Пн–Вс
    /// с подсветкой по тратам дня и сумма за неделю.
    private func weekRows(_ report: Report, tag: TransactionTag) -> some View {
        let calendar = TagAnalyticsBuilder.weekCalendar
        let weeks = report.snapshot.chartPoints
        let page = report.snapshot.page
        let maxDay = max(report.tagDailyTotals.values.max() ?? 0, 1)
        let maxWeek = weeks.map(\.total).max() ?? 0

        return VStack(spacing: 4) {
            HStack(spacing: 8) {
                Color.clear.frame(width: Self.weekLabelWidth, height: 1)
                HStack(spacing: 3) {
                    ForEach(orderedWeekdaySymbols(calendar), id: \.self) { symbol in
                        Text(symbol)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                Color.clear.frame(width: Self.weekAmountWidth, height: 1)
            }

            ForEach(weeks) { week in
                NavigationLink {
                    TransactionListByKindView(
                        kind: .expense,
                        scope: tagBinScope(
                            for: AnalyticsTimeTotal(id: week.id, date: week.date, title: week.title, total: week.total),
                            tag: tag,
                            granularity: .weekly
                        )
                    )
                } label: {
                    weekRow(
                        week,
                        page: page,
                        dailyTotals: report.tagDailyTotals,
                        maxDay: maxDay,
                        isPeak: week.total > 0 && week.total == maxWeek,
                        calendar: calendar
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func weekRow(
        _ week: AnalyticsChartPoint,
        page: AnalyticsPeriodPage,
        dailyTotals: [Date: Double],
        maxDay: Double,
        isPeak: Bool,
        calendar: Calendar
    ) -> some View {
        let weekInterval = calendar.dateInterval(of: .weekOfYear, for: week.date)
        let weekStart = weekInterval?.start ?? week.date
        let weekEnd = min(weekInterval?.end ?? week.date, page.endDateExclusive)
        let lastDay = calendar.date(byAdding: .day, value: -1, to: weekEnd) ?? week.date
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }

        return HStack(spacing: 8) {
            Text(weekRangeLabel(from: week.date, to: lastDay, calendar: calendar))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(week.total > 0 ? Color.primary : Color.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: Self.weekLabelWidth, alignment: .leading)

            HStack(spacing: 3) {
                ForEach(days, id: \.self) { day in
                    let inPeriod = day >= page.startDate && day < page.endDateExclusive
                    let total = dailyTotals[calendar.startOfDay(for: day)] ?? 0
                    let intensity = total > 0 ? min(total / maxDay, 1) : 0
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(
                            !inPeriod ? Color.clear
                                : total > 0 ? Color.red.opacity(0.12 + 0.6 * intensity)
                                : Color(.tertiarySystemFill).opacity(0.6)
                        )
                        .overlay {
                            if !inPeriod {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .strokeBorder(Color(.tertiarySystemFill), lineWidth: 1)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                }
            }

            Text(week.total > 0 ? weekAmount(week.total) : "—")
                .font(.footnote.weight(isPeak ? .bold : .semibold))
                .monospacedDigit()
                .foregroundStyle(week.total > 0 ? Color.primary : Color.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: Self.weekAmountWidth, alignment: .trailing)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    /// «3–9 нояб» или «27 окт – 2 нояб».
    private func weekRangeLabel(from start: Date, to end: Date, calendar: Calendar) -> String {
        let startDay = calendar.component(.day, from: start)
        let endDay = calendar.component(.day, from: end)
        let endMonth = shortMonth(end)
        if calendar.isDate(start, inSameDayAs: end) {
            return "\(startDay) \(endMonth)"
        }
        if calendar.isDate(start, equalTo: end, toGranularity: .month) {
            return "\(startDay)–\(endDay) \(endMonth)"
        }
        return "\(startDay) \(shortMonth(start)) – \(endDay) \(endMonth)"
    }

    private func shortMonth(_ date: Date) -> String {
        AnalyticsDateFormat.monthShort.string(from: date)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    private func weekAmount(_ value: Double) -> String {
        value < 1_000 ? "\(Int(value.rounded())) ₽" : "\(ExpenseChartFormat.compact(value)) ₽"
    }

    private static let standaloneMonthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "LLLL"
        return formatter
    }()

    /// Месяцы (метка или год): плитки по три в ряд, цвет — доля от самого дорогого.
    /// `tag` задан — плитка открывает траты метки за месяц, иначе все расходы месяца.
    private func monthTiles(_ snapshot: AnalyticsSnapshot, tag: TransactionTag?) -> some View {
        let calendar = Calendar.current
        let points = snapshot.chartPoints
        let maxTotal = max(points.map(\.total).max() ?? 0, 1)
        let years = Set(points.map { calendar.component(.year, from: $0.date) })
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(points) { point in
                NavigationLink {
                    if let tag {
                        TransactionListByKindView(
                            kind: .expense,
                            scope: tagBinScope(
                                for: AnalyticsTimeTotal(id: point.id, date: point.date, title: point.title, total: point.total),
                                tag: tag,
                                granularity: .monthly
                            )
                        )
                    } else {
                        TransactionListByKindView(kind: .expense, scope: monthScope(for: point.date))
                    }
                } label: {
                    monthTile(point, maxTotal: maxTotal, showsYear: years.count > 1, calendar: calendar)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func monthTile(
        _ point: AnalyticsChartPoint,
        maxTotal: Double,
        showsYear: Bool,
        calendar: Calendar
    ) -> some View {
        let hasSpend = point.total > 0
        let intensity = hasSpend ? min(point.total / maxTotal, 1) : 0
        let isCurrent = calendar.isDate(point.date, equalTo: .now, toGranularity: .month)
        let isFuture = point.date > .now
        let onDark = intensity > 0.6
        var name = Self.standaloneMonthFormatter.string(from: point.date).capitalized
        if showsYear {
            name += " ’\(calendar.component(.year, from: point.date) % 100)"
        }
        let background = hasSpend
            ? Color.red.opacity(0.10 + 0.45 * intensity)
            : Color(.tertiarySystemFill).opacity(0.5)

        return VStack(alignment: .leading, spacing: 4) {
            Text(name)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(onDark ? Color.white : Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(hasSpend ? weekAmount(point.total) : " ")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(onDark ? Color.white.opacity(0.9) : Color.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .frame(height: 58)
        .background(background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            if isCurrent {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.red, lineWidth: 1.5)
            }
        }
        .opacity(isFuture ? 0.4 : 1)
    }

    /// Сумма в клетке: до тысячи — целым числом, дальше — «12,5к».
    private func dayCellAmount(_ value: Double) -> String {
        value < 1_000 ? "\(Int(value.rounded()))" : ExpenseChartFormat.compact(value)
    }

    // Короткие названия дней недели в порядке от firstWeekday (Пн … Вс для ru).
    private func orderedWeekdaySymbols(_ calendar: Calendar) -> [String] {
        let symbols = calendar.shortWeekdaySymbols.map { $0.capitalized }
        let shift = calendar.firstWeekday - 1
        guard shift > 0 else { return symbols }
        return Array(symbols[shift...] + symbols[..<shift])
    }

    private func dailySectionTitle(_ report: Report) -> String {
        if selectedMode == .tags, let granularity = report.tagGranularity {
            return granularity.sectionTitle
        }
        return selectedScale == .year ? "По месяцам" : "По дням"
    }

    /// Год и метки: строки на одной карточке с полоской относительно самого дорогого.
    private func timeTotalsList(_ report: Report) -> some View {
        let items = report.snapshot.lowerTimeTotals
        let maxTotal = items.map(\.total).max() ?? 0
        let color = selectedMode == .tags ? (selectedTag.map(tagColor) ?? .red) : .red

        return SettingsCard {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Divider()
                        .padding(.leading, 16)
                }
                dailySectionRow(for: item, maxTotal: maxTotal, color: color, granularity: report.tagGranularity)
            }
        }
    }

    @ViewBuilder
    private func dailySectionRow(
        for item: AnalyticsTimeTotal,
        maxTotal: Double,
        color: Color,
        granularity: TagBinGranularity?
    ) -> some View {
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
                timeTotalRowLabel(for: item, maxTotal: maxTotal, color: color)
            }
            .buttonStyle(SettingsPressStyle())
        } else if let tag = selectedTag {
            // В режиме Tags строки кликабельны: переход к списку расходов
            // с этим тегом за данный день/неделю/месяц.
            NavigationLink {
                TransactionListByKindView(
                    kind: .expense,
                    scope: tagBinScope(for: item, tag: tag, granularity: granularity)
                )
            } label: {
                timeTotalRowLabel(for: item, maxTotal: maxTotal, color: color)
            }
            .buttonStyle(SettingsPressStyle())
        } else {
            timeTotalRowLabel(for: item, maxTotal: maxTotal, color: color)
        }
    }

    /// Создаёт скоуп для конкретного бина (день/неделя/месяц) в режиме Tags.
    private func tagBinScope(
        for item: AnalyticsTimeTotal,
        tag: TransactionTag,
        granularity: TagBinGranularity?
    ) -> AnalyticsScope {
        let calendar = Calendar.current
        let tagName = tag.name
        let binStart = item.date

        let binEndExclusive: Date
        switch granularity {
        case .daily, nil:
            binEndExclusive = calendar.date(byAdding: .day, value: 1, to: binStart) ?? binStart
        case .weekly:
            binEndExclusive = TagAnalyticsBuilder.weekCalendar.dateInterval(of: .weekOfYear, for: binStart)?.end
                ?? calendar.date(byAdding: .day, value: 7, to: binStart)
                ?? binStart
        case .monthly:
            binEndExclusive = calendar.dateInterval(of: .month, for: binStart)?.end
                ?? calendar.date(byAdding: .month, value: 1, to: binStart)
                ?? binStart
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

    /// Строка периода: сумма и полоска относительно самого дорогого.
    private func timeTotalRowLabel(for item: AnalyticsTimeTotal, maxTotal: Double, color: Color) -> some View {
        let share = maxTotal > 0 ? max(item.total, 0) / maxTotal : 0

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(item.title)
                    .foregroundStyle(item.total > 0 ? Color.primary : Color.secondary)
                Spacer(minLength: 8)
                Text(formattedRubAmount(item.total))
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(item.total > 0 ? Color.primary : Color.secondary)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }

            AnalyticsShareBar(share: share, color: color)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    // MARK: - Categories

    /// Категории: график выбранного вида и список с подкатегориями.
    private func categorySection(_ report: Report) -> some View {
        let snapshot = report.snapshot

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionHeader("Категории")

                if !snapshot.categoryTotals.isEmpty {
                    SortMenu(
                        options: CategoryListSort.allCases,
                        selection: $categorySort,
                        title: \.title,
                        systemImage: \.systemImage
                    )
                }

                Spacer()

                // Вид графика: полосы, кольцо или лента — запоминается.
                if !snapshot.categoryTotals.isEmpty {
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
            }

            if snapshot.categoryTotals.isEmpty {
                emptyText("Нет данных для выбранного периода")
                    .analyticsCard()
            } else {
                switch categoryChartStyle {
                case .bars:
                    CategoryBarsChart(
                        totals: snapshot.categoryTotals,
                        totalExpenses: snapshot.totalExpensesRub,
                        colors: categoryColors(for: snapshot.categoryTotals),
                        onOpenCategory: { categoryNavigationTarget = $0 }
                    )
                case .donut:
                    categoryDonutChart(snapshot)
                case .strip:
                    categoryStripChart(snapshot)
                }

                categoryList(snapshot, scope: report.scope)
            }
        }
    }

    private func categoryList(_ snapshot: AnalyticsSnapshot, scope: AnalyticsScope) -> some View {
        let maxTotal = snapshot.categoryTotals.map(\.total).max() ?? 0

        return SettingsCard {
            ForEach(Array(categorySort.sorted(snapshot.categoryTotals).enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    SettingsDivider()
                }
                categoryRow(
                    item,
                    maxTotal: maxTotal,
                    share: item.share(of: snapshot.totalExpensesRub),
                    scope: scope
                )
            }
        }
    }

    /// Строка категории. Категория с подкатегориями раскрывает их списком
    /// (свёрнуть — тапом по строке), остальные сразу ведут к операциям.
    /// - Parameter share: доля категории во всех расходах периода.
    @ViewBuilder
    private func categoryRow(
        _ item: AnalyticsCategoryTotal,
        maxTotal: Double,
        share: Double,
        scope: AnalyticsScope
    ) -> some View {
        let isExpanded = !collapsedCategories.contains(item.category)

        if item.subcategories.isEmpty {
            NavigationLink {
                TransactionListByCategoryView(categoryTitle: item.category, scope: scope)
            } label: {
                categoryRowLabel(item, maxTotal: maxTotal, share: share, accessoryRotation: nil)
            }
            .buttonStyle(SettingsPressStyle())
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
                categoryRowLabel(item, maxTotal: maxTotal, share: share, accessoryRotation: isExpanded ? 180 : 0)
            }
            .buttonStyle(SettingsPressStyle())

            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(item.subcategories) { subcategory in
                        NavigationLink {
                            TransactionListByCategoryView(
                                categoryTitle: item.category,
                                subcategoryTitle: subcategory.name,
                                scope: scope
                            )
                        } label: {
                            subcategoryRow(subcategory, in: item)
                        }
                        .buttonStyle(SettingsPressStyle())
                    }

                    NavigationLink {
                        TransactionListByCategoryView(categoryTitle: item.category, scope: scope)
                    } label: {
                        HStack(spacing: 4) {
                            Text("Все операции категории")
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.semibold))
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(categoryColor(item.category))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 62)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(SettingsPressStyle())
                }
                .padding(.bottom, 4)
            }
        }
    }

    /// - Parameter accessoryRotation: nil — шеврон перехода, иначе — раскрытия с поворотом.
    private func categoryRowLabel(
        _ item: AnalyticsCategoryTotal,
        maxTotal: Double,
        share categoryShare: Double,
        accessoryRotation: Double?
    ) -> some View {
        let color = categoryColor(item.category)
        let share = maxTotal > 0 ? max(item.total, 0) / maxTotal : 0

        return HStack(spacing: 14) {
            AnalyticsCategoryIcon(category: categoryItem(for: item.category))

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.category)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text(formattedRubAmount(item.total))
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .fixedSize()
                }

                HStack(spacing: 8) {
                    AnalyticsShareBar(share: share, color: color)

                    Text("\(formattedPercent(categoryShare)) · \(item.count) шт.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .fixedSize()
                }
            }

            Image(systemName: accessoryRotation == nil ? "chevron.right" : "chevron.down")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(accessoryRotation ?? 0))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func subcategoryRow(_ subcategory: AnalyticsSubcategoryTotal, in category: AnalyticsCategoryTotal) -> some View {
        let share = category.total > 0 ? subcategory.total / category.total : 0

        return HStack(spacing: 10) {
            Text(subcategory.emoji ?? "•")
                .font(.callout)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(subcategory.name)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("\(formattedPercent(share)) · \(subcategory.count) шт.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer(minLength: 8)

            Text(formattedRubAmount(subcategory.total))
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
                .fixedSize()

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.leading, 58)
        .padding(.trailing, 16)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }

    // MARK: - Merchants

    private func merchantSection(_ report: Report) -> some View {
        let snapshot = report.snapshot

        return VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Топ мест и сервисов")

            if snapshot.merchantTotals.isEmpty {
                emptyText("Нет расходов для выбранного периода")
                    .analyticsCard()
            } else {
                let maxTotal = snapshot.merchantTotals.map(\.total).max() ?? 0

                SettingsCard {
                    ForEach(Array(snapshot.merchantTotals.enumerated()), id: \.offset) { index, item in
                        if index > 0 {
                            SettingsDivider()
                        }

                        NavigationLink {
                            TransactionListByMerchantView(
                                merchantTitle: item.merchant,
                                scope: report.scope
                            )
                        } label: {
                            merchantRow(rank: index + 1, item: item, maxTotal: maxTotal)
                        }
                        .buttonStyle(SettingsPressStyle())
                    }
                }
            }
        }
    }

    /// Строка места: номер в рейтинге (первые три — на цветной плашке), сумма и доля.
    private func merchantRow(rank: Int, item: AnalyticsMerchantTotal, maxTotal: Double) -> some View {
        let isTop = rank <= 3
        let share = maxTotal > 0 ? max(item.total, 0) / maxTotal : 0

        return HStack(spacing: 14) {
            Text("\(rank)")
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(isTop ? Color.white : Color.secondary)
                .frame(width: 32, height: 32)
                .background {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(isTop ? AnyShapeStyle(Color.orange.gradient) : AnyShapeStyle(Color(.tertiarySystemFill)))
                }

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.merchant)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text(formattedRubAmount(item.total))
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .fixedSize()
                }

                AnalyticsShareBar(share: share, color: .orange)
            }

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    // MARK: - Category charts

    /// Категории с положительной суммой — для кольца и ленты (доли не бывают отрицательными).
    private func positiveCategoryTotals(_ snapshot: AnalyticsSnapshot) -> [AnalyticsCategoryTotal] {
        snapshot.categoryTotals.filter { $0.total > 0 }
    }

    private func categoryColor(_ name: String) -> Color {
        categoryItem(for: name).flatMap { Color(hex: $0.colorHex) } ?? .gray
    }

    /// Цвета категорий для графиков, которые живут в отдельных видах.
    private func categoryColors(for items: [AnalyticsCategoryTotal]) -> [String: Color] {
        Dictionary(
            items.map { ($0.category, categoryColor($0.category)) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    // Кольцо: доли категорий, в центре — итог или выбранная категория.
    private func categoryDonutChart(_ snapshot: AnalyticsSnapshot) -> some View {
        let items = positiveCategoryTotals(snapshot)
        let total = items.reduce(0) { $0 + $1.total }

        return VStack(spacing: 16) {
            CategoryDonutChart(items: items, total: total, colors: categoryColors(for: items))

            categoryLegend(items, total: total)
        }
        .analyticsCard()
    }

    // Лента: одна полоса 100%, поделённая на категории, и легенда под ней.
    private func categoryStripChart(_ snapshot: AnalyticsSnapshot) -> some View {
        let items = positiveCategoryTotals(snapshot)
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
        .analyticsCard()
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

    // MARK: - Chart paging

    private var latestAllowedAnchorDate: Date {
        AnalyticsSnapshotBuilder.makePage(for: selectedScale, anchorDate: .now).startDate
    }

    /// Смена масштаба: масштаб и дата страницы меняются вместе — отчёт строится
    /// один раз, а не дважды (раньше дату подгонял отдельный onChange).
    private func selectScale(_ scale: AnalyticsTimeScale) {
        guard scale != selectedScale else { return }
        let latest = AnalyticsSnapshotBuilder.makePage(for: scale, anchorDate: .now).startDate
        selectedScale = scale
        pageAnchorDate = snappedAnchorDate(min(pageAnchorDate, latest), scale: scale)
    }

    /// График долистали до другой страницы — переключаем на неё весь экран.
    private func settlePage(at pageStart: Date) {
        let target = snappedAnchorDate(clampAnchorDate(pageStart), scale: selectedScale)
        let currentPage = AnalyticsSnapshotBuilder.makePage(for: selectedScale, anchorDate: pageAnchorDate)
        guard !currentPage.contains(target) else { return }
        pageAnchorDate = target
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
        }
    }

    // MARK: - Trend / insights helpers

    private func trendDeltaFraction(_ report: Report) -> Double? {
        guard let previous = report.previousSnapshot, previous.averageExpensePerBin > 0 else { return nil }
        return (report.snapshot.averageExpensePerBin - previous.averageExpensePerBin) / previous.averageExpensePerBin
    }

    private func formattedPercent(_ value: Double) -> String {
        AnalyticsFormat.percent(value)
    }

    private func categoryItem(for categoryName: String) -> ExpenseCategoryItem? {
        CategoryLookup.findCategory(named: categoryName, in: categories)
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
        AnalyticsFormat.monthYear(date)
    }

    private func formattedRubAmount(_ value: Double) -> String {
        AnalyticsFormat.rub(value)
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

// MARK: - Category charts with finger selection

/// Полосы категорий: ведёшь пальцем — полоса выделяется, короткое касание
/// открывает операции категории.
///
/// Выделение хранится здесь, а не в `AnalyticsView`: пока палец двигается,
/// перерисовывается только график, а не весь экран аналитики.
private struct CategoryBarsChart: View {
    let totals: [AnalyticsCategoryTotal]
    /// Все расходы периода — от них считаются доли у полос.
    let totalExpenses: Double
    let colors: [String: Color]
    let onOpenCategory: (String) -> Void

    @State private var selectedCategoryName: String?
    @State private var lastHapticCategoryName: String?

    var body: some View {
        Chart {
            ForEach(totals) { item in
                let isSelected = selectedCategoryName == item.category
                let color = colors[item.category] ?? .gray

                BarMark(
                    x: .value("Сумма", item.total),
                    y: .value("Категория", item.category),
                    height: .fixed(isSelected ? 26 : 18)
                )
                .foregroundStyle(isSelected ? color : color.opacity(0.72))
                .cornerRadius(isSelected ? 8 : 5)
                .annotation(position: .trailing) {
                    Text(AnalyticsFormat.percent(item.share(of: totalExpenses)))
                        .font(isSelected ? .caption.bold() : .caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(height: chartHeight)
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
                                    onOpenCategory(selectedCategoryName)
                                }

                                selectedCategoryName = nil
                                lastHapticCategoryName = nil
                            }
                    )
            }
        }
        .analyticsCard()
        .animation(.smooth(duration: 0.25), value: selectedCategoryName)
    }

    private var chartHeight: CGFloat {
        let count = max(totals.count, 1)
        let base = CGFloat(count) * 44
        return min(max(base, 180), 420)
    }

    private func nearestCategory(at yInPlot: CGFloat, plotHeight: CGFloat) -> String? {
        guard !totals.isEmpty, plotHeight > 0 else { return nil }

        let rowHeight = plotHeight / CGFloat(totals.count)
        let rawIndex = Int((yInPlot / rowHeight).rounded(.down))
        let index = min(max(rawIndex, 0), totals.count - 1)

        return totals[index].category
    }
}

/// Кольцо долей категорий: палец на кольце показывает категорию в центре.
///
/// Выбор хранится здесь же: пока палец двигается, перерисовывается только кольцо.
private struct CategoryDonutChart: View {
    let items: [AnalyticsCategoryTotal]
    let total: Double
    let colors: [String: Color]

    /// Значение под пальцем (накопленная сумма).
    @State private var selectedValue: Double?

    var body: some View {
        let selected = selectedValue.flatMap { category(atCumulative: $0) }

        Chart(items) { item in
            let isSelected = selected?.category == item.category

            SectorMark(
                angle: .value("Сумма", item.total),
                innerRadius: .ratio(0.62),
                outerRadius: .ratio(isSelected ? 1 : 0.93),
                angularInset: 1.5
            )
            .cornerRadius(4)
            .foregroundStyle(colors[item.category] ?? .gray)
            .opacity(selected == nil || isSelected ? 1 : 0.35)
        }
        .chartAngleSelection(value: $selectedValue)
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
                            Text(AnalyticsFormat.percent(total > 0 ? selected.total / total : 0))
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
        .animation(.smooth(duration: 0.25), value: selected?.category)
    }

    private func category(atCumulative value: Double) -> AnalyticsCategoryTotal? {
        var accumulated = 0.0
        for item in items {
            accumulated += item.total
            if value <= accumulated {
                return item
            }
        }
        return items.last
    }
}

private extension AnalyticsCategoryTotal {
    /// Доля категории во всех расходах периода.
    func share(of totalExpenses: Double) -> Double {
        totalExpenses > 0 ? total / totalExpenses : 0
    }
}

/// Форматтеры аналитики создаются один раз: NumberFormatter и DateFormatter
/// дорогие, а суммы и доли форматируются в каждой строке на каждой отрисовке.
private enum AnalyticsFormat {
    private static let rubFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.groupingSeparator = " "
        formatter.decimalSeparator = ","
        return formatter
    }()

    private static let percentFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return formatter
    }()

    private static let monthYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "LLL yyyy"
        return formatter
    }()

    /// «1 234,50 ₽».
    static func rub(_ value: Double) -> String {
        let number = rubFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
        return "\(number) ₽"
    }

    /// «12 %».
    static func percent(_ value: Double) -> String {
        percentFormatter.string(from: NSNumber(value: value)) ?? "\(Int(value * 100))%"
    }

    /// «Окт. 2026».
    static func monthYear(_ date: Date) -> String {
        monthYearFormatter.string(from: date).capitalized
    }
}
