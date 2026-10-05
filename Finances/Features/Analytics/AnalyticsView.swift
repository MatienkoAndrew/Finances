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

    @State private var categoryNavigationTarget: String?
    /// Свёрнут ли раздел «По дням / неделям / месяцам» (запоминается).
    @AppStorage("analytics.dailySectionCollapsed") private var isDailySectionCollapsed = false
    /// Вид графика по категориям (выбор запоминается между запусками).
    @AppStorage("analytics.categoryChartStyle") private var categoryChartStyle: CategoryChartStyle = .bars
    /// Категории с подкатегориями раскрыты сразу, как в Alipay; здесь — свёрнутые вручную.
    @State private var collapsedCategories: Set<String> = []

    @State private var didInitializeAnchor = false

    /// Аналитика одной метки — открыта из её экрана: без ленты меток и
    /// переключателя режимов, внутри уже существующей навигации.
    private let focusedTag: TransactionTag?

    init(focusedTag: TransactionTag? = nil) {
        self.focusedTag = focusedTag
        _selectedMode = State(initialValue: focusedTag == nil ? .time : .tags)
        _selectedTag = State(initialValue: focusedTag)
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
    }

    private func makeReport() -> Report {
        switch selectedMode {
        case .time:
            let snapshot = AnalyticsSnapshotBuilder.build(
                transactions: transactions,
                scale: selectedScale,
                anchorDate: pageAnchorDate,
                settings: settings,
                trackedRates: trackedRates
            )
            let page = snapshot.page

            return Report(
                snapshot: snapshot,
                previousSnapshot: AnalyticsSnapshotBuilder.build(
                    transactions: transactions,
                    scale: selectedScale,
                    anchorDate: previousAnchorDate,
                    settings: settings,
                    trackedRates: trackedRates
                ),
                timeline: ExpenseTimelineData.build(
                    transactions: transactions,
                    scale: selectedScale,
                    settings: settings,
                    trackedRates: trackedRates
                ),
                tagGranularity: nil,
                availableTagGranularities: [],
                scope: AnalyticsScope(
                    title: page.displayTitle,
                    matches: { tx in page.contains(tx.date) },
                    containsDate: { date in page.contains(date) }
                )
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
            } else {
                granularity = TagAnalyticsBuilder.granularity(for: tag, taggedTransactions: tagged)
            }

            // В режиме Tags строим снапшот по эффективному периоду метки
            // (без пустых дней до/после) с авто-гранулярностью бинов.
            return Report(
                snapshot: TagAnalyticsBuilder.buildSnapshot(
                    tag: tag,
                    transactions: tagged,
                    settings: settings,
                    trackedRates: trackedRates,
                    granularity: granularity
                ),
                previousSnapshot: nil,
                timeline: nil,
                tagGranularity: granularity,
                availableTagGranularities: available,
                scope: tagScope(for: tag)
            )
        }
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
    private func tagScope(for tag: TransactionTag) -> AnalyticsScope {
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

    /// Смена метки или интервала пересоздаёт график (сбрасывает выбор столбика).
    private func tagChartIdentity(_ report: Report) -> String {
        let name = selectedTag?.name ?? ""
        let granularity = report.tagGranularity?.shortTitle ?? ""
        return name + "|" + granularity
    }

    var body: some View {
        let report = makeReport()

        if focusedTag != nil {
            content(report)
                .navigationTitle("Аналитика")
        } else {
            NavigationStack {
                content(report)
            }
        }
    }

    private func content(_ report: Report) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if selectedMode == .time {
                    periodHeroCard(report)
                    breakdownSections(report)
                } else {
                    // В режиме меток период задан самой меткой, поэтому
                    // W/M/Y и стрелки скрыты: сверху лента меток и карточка
                    // выбранной метки с итогами.
                    if focusedTag == nil {
                        tagSelector
                    }
                    if let tag = selectedTag {
                        tagHeroCard(tag, report: report)
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
                    AnalyticsScaleTabs(selection: $selectedScale)
                }
            }
            if focusedTag == nil {
                ToolbarItem(placement: .topBarTrailing) {
                    tagToggleButton
                }
            }
        }
        // Переход из графика и легенды категорий. Скрытая NavigationLink(isActive:)
        // при быстром «назад» и новом касании оставляла пустую страницу.
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
        .onChange(of: selectedScale) { _, _ in
            pageAnchorDate = snappedAnchorDate(
                min(pageAnchorDate, latestAllowedAnchorDate),
                scale: selectedScale
            )
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
        categorySection(report)
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
        let days = tagPeriodDays(snapshot)
        let perDay = days > 0 ? snapshot.totalExpensesRub / Double(days) : 0

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

            HStack(spacing: 8) {
                AnalyticsMetricTile(value: "\(snapshot.expenseCount)", title: operationsWord(snapshot.expenseCount))
                AnalyticsMetricTile(value: TagFormatting.rub(perDay), title: "в день")
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

                Text(snapshot.page.displayTitle)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .contentTransition(.opacity)

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

    /// Подложка шапки: карточка с мягким цветным отсветом в углу.
    private func heroBackground(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(RadialGradient(
                        colors: [color.opacity(0.20), color.opacity(0)],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: 320
                    ))
            }
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
                    } else {
                        // Год и режим меток — список строк.
                        timeTotalsList(report)
                    }
                }
                .transition(.opacity)
            }
        }
    }

    // Неделя и месяц: сетка-календарь с суммой по дням и подсветкой по интенсивности трат.
    private func dailyCalendar(_ snapshot: AnalyticsSnapshot) -> some View {
        var calendar = Calendar.current
        calendar.locale = Locale(identifier: "ru_RU")

        let points = snapshot.chartPoints
        let maxTotal = max(points.map(\.total).max() ?? 0, 1)
        let leadingBlanks = points.first.map { first in
            (calendar.component(.weekday, from: first.date) - calendar.firstWeekday + 7) % 7
        } ?? 0
        let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)

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
        let isToday = calendar.isDateInToday(point.date)
        let isFuture = point.date > .now
        let background = hasSpend
            ? Color.red.opacity(0.10 + 0.45 * intensity)
            : Color(.tertiarySystemFill).opacity(0.5)

        return NavigationLink {
            TransactionListByDateView(date: point.date)
        } label: {
            VStack(spacing: 2) {
                Text("\(day)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(intensity > 0.6 ? Color.white : Color.primary)

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
            ForEach(Array(snapshot.categoryTotals.enumerated()), id: \.element.id) { index, item in
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
