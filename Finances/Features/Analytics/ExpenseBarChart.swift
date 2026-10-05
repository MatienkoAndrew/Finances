//
//  ExpenseBarChart.swift
//  Finances
//
//  График расходов в стиле «Здоровья» на Swift Charts:
//   • режим времени — вся история в одной ленте, плавная прокрутка пальцем
//     с доводкой до границы недели / месяца / года;
//   • шкала значений подстраивается под видимые столбики;
//   • касание с удержанием (или тап в статичном графике) выделяет столбик,
//     и заголовок показывает его сумму и дату.
//

import SwiftUI
import Charts

/// Столбик графика расходов: интервал [start, end) и сумма в рублях.
struct ExpenseBar: Identifiable {
    let start: Date
    let end: Date
    let total: Double
    /// Подпись для выноски: «5 окт. 2026», «3 окт.–9 окт.», «Октябрь 2026».
    let title: String

    var id: Date { start }
    var mid: Date { start.addingTimeInterval(end.timeIntervalSince(start) / 2) }
}

/// Прокрутка по всей истории расходов, как в «Здоровье».
struct ExpenseChartTimeline {
    let scale: AnalyticsTimeScale
    /// Начало страницы, открытой на экране (стрелками или после прокрутки).
    let pageStart: Date
    /// Прокрутка остановилась на странице с этим началом.
    let onPageSettled: (Date) -> Void
}

/// Куда Charts довёл прокрутку графика.
///
/// Привязка `chartScrollPosition` получает позицию, только пока график движется
/// за пальцем и по инерции, а доводку до начала страницы Charts делает уже без неё.
/// Подпись периода, шкала и страница экрана оставались от промежуточного положения:
/// график показывал 29 дек. – 4 янв., а подпись — «3–9 янв.».
@Observable
private final class PageSnap {
    var target: Date?
}

/// Доводка до начала страницы, которая запоминает, куда довела.
nonisolated private struct PageSnapBehavior: ChartScrollTargetBehavior {
    let alignment: ValueAlignedChartScrollTargetBehavior
    /// Страница графика: неделя, месяц или год.
    let pageUnit: Calendar.Component
    let snap: PageSnap

    func updateTarget(_ target: inout ScrollTarget, context: ChartScrollTargetBehaviorContext) {
        let proposed = context.chartProxy.value(atX: target.rect.minX, as: Date.self)

        // Цель уже на начале страницы (листание стрелками, повторный расчёт после
        // прокрутки) — оставляем её. Стандартная доводка точную границу не узнаёт
        // и уводит график на страницу назад: стрелка «вперёд» показывала прежнюю
        // неделю под подписью следующей.
        if let proposed, Self.pageStart(near: proposed, unit: pageUnit) == nil {
            alignment.updateTarget(&target, context: context)
        }

        guard let snapped = context.chartProxy.value(atX: target.rect.minX, as: Date.self) else { return }
        // Цель считается посреди обновления прокрутки — состояние меняем после него.
        let snap = snap
        Task { @MainActor in
            snap.target = snapped
        }
    }

    /// Начало страницы, если дата отстоит от него меньше чем на пару минут
    /// (даты от Charts бывают неточны на доли секунды); иначе nil.
    static func pageStart(near date: Date, unit: Calendar.Component) -> Date? {
        guard let page = Calendar.current.dateInterval(of: unit, for: date.addingTimeInterval(60)),
              abs(page.start.timeIntervalSince(date)) < 120 else {
            return nil
        }
        return page.start
    }
}

/// Столбики за всю историю и границы оси для прокручиваемого графика.
struct ExpenseTimelineData {
    let bars: [ExpenseBar]
    let domain: Range<Date>

    /// - Parameter pageStart: начало открытой страницы. Лента растягивается до неё,
    ///   даже если трат там нет: стрелкой можно уйти раньше первой траты, и график
    ///   оставался на первой странице с данными под подписью выбранной.
    static func build(
        transactions: [Transaction],
        scale: AnalyticsTimeScale,
        pageStart: Date,
        settings: AppSettings?,
        trackedRates: [TrackedExchangeRate]
    ) -> ExpenseTimelineData {
        let calendar = Calendar.current
        let unit = scale.barUnit
        let now = Date()
        var totals: [Date: Double] = [:]
        var earliest = now

        for transaction in transactions {
            let sign: Double
            switch transaction.kind {
            case .expense:
                sign = 1
            case .income where transaction.reducesExpensesInAnalytics:
                // Курсовая разница «в плюс» уменьшает расходы, как и в снапшоте.
                sign = -1
            default:
                continue
            }

            guard let rub = TransactionRubConverter.displayRubAmount(
                for: transaction,
                settings: settings,
                trackedRates: trackedRates
            ), let interval = calendar.dateInterval(of: unit, for: transaction.date) else {
                continue
            }

            totals[interval.start, default: 0] += sign * rub
            earliest = min(earliest, transaction.date)
        }

        let first = min(calendar.dateInterval(of: scale.pageUnit, for: earliest)?.start ?? earliest, pageStart)
        let last = calendar.dateInterval(of: scale.pageUnit, for: now)?.end ?? now

        // Пустые дни не рисуем: выноска для них строится на лету.
        let bars = totals
            .filter { entry in entry.value > 0 && entry.key >= first && entry.key < last }
            .sorted { $0.key < $1.key }
            .map { entry in
                ExpenseBar(
                    start: entry.key,
                    end: calendar.date(byAdding: unit, value: 1, to: entry.key) ?? entry.key,
                    total: entry.value,
                    title: ExpenseChartFormat.title(for: entry.key, unit: unit)
                )
            }

        return ExpenseTimelineData(bars: bars, domain: first..<last)
    }
}

struct ExpenseBarChart: View {
    let bars: [ExpenseBar]
    let domain: Range<Date>
    let averageTitle: String
    /// Подпись периода под средним (для статичного графика).
    let rangeTitle: String?
    let tint: Color
    let timeline: ExpenseChartTimeline?

    private let axis: AxisLayout
    private let isDense: Bool

    @State private var scrollPosition: Date
    @State private var rawSelection: Date?
    /// Начало страницы, до которой Charts довёл прокрутку (см. `PageSnap`).
    @State private var snap = PageSnap()

    private struct AxisLayout {
        var gridDates: [Date] = []
        var labelDates: [Date] = []
        var labels: [Int: String] = [:]
    }

    /// - Parameter axisLabels: подписи оси X по одной на столбик (пустая — без подписи);
    ///   нужны только статичному графику, в режиме прокрутки подписи строятся по масштабу.
    init(
        bars: [ExpenseBar],
        domain: Range<Date>,
        averageTitle: String,
        rangeTitle: String? = nil,
        axisLabels: [String] = [],
        tint: Color = .red,
        timeline: ExpenseChartTimeline? = nil
    ) {
        self.bars = bars
        self.domain = domain
        self.averageTitle = averageTitle
        self.rangeTitle = rangeTitle
        self.tint = tint
        self.timeline = timeline

        if let timeline {
            axis = Self.timelineAxis(scale: timeline.scale, domain: domain)
            isDense = timeline.scale == .month
        } else {
            axis = Self.staticAxis(bars: bars, labels: axisLabels)
            isDense = bars.count > 16
        }

        _scrollPosition = State(initialValue: timeline?.pageStart ?? domain.lowerBound)
    }

    var body: some View {
        let selected = selectedBar
        let window = visibleWindow
        let summary = stats(in: window)

        VStack(alignment: .leading, spacing: 10) {
            header(average: summary.average, window: window, selected: selected)

            chart(selected: selected, yMax: summary.yMax, near: window)
                .animation(.easeOut(duration: 0.2), value: summary.yMax)
        }
        .sensoryFeedback(.selection, trigger: selected?.start)
    }

    // MARK: - Header

    /// Заголовок над графиком: среднее за видимый период, а пока выделен
    /// столбик — его сумма и дата (как в «Здоровье»).
    private func header(average: Double, window: Range<Date>, selected: ExpenseBar?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(selected == nil ? averageTitle : "ПОТРАЧЕНО")
                .font(.caption.weight(.semibold))
                .foregroundStyle(selected == nil ? Color.secondary : tint)

            Text(ExpenseChartFormat.rub(selected?.total ?? average))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())

            Text(selected?.title ?? rangeText(for: window))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.snappy(duration: 0.2), value: selected?.start)
    }

    private func rangeText(for window: Range<Date>) -> String {
        guard let timeline else { return rangeTitle ?? "" }
        return ExpenseChartFormat.range(
            start: window.lowerBound,
            endExclusive: window.upperBound,
            unit: timeline.scale.barUnit
        )
    }

    // MARK: - Chart

    /// - Parameter window: видимое окно — рисуется только то, что рядом с ним.
    @ViewBuilder
    private func chart(selected: ExpenseBar?, yMax: Double, near window: Range<Date>) -> some View {
        let insetRatio: Double = isDense ? 0.12 : 0.16
        let cornerRadius: CGFloat = isDense ? 2.5 : 5
        let drawn = drawnRange(around: window)
        let drawnBars = bars.filter { $0.end > drawn.lowerBound && $0.start < drawn.upperBound }

        let base = Chart {
            ForEach(drawnBars) { (bar: ExpenseBar) in
                barMark(
                    bar,
                    isDimmed: selected != nil && selected?.start != bar.start,
                    yMax: yMax,
                    insetRatio: insetRatio,
                    cornerRadius: cornerRadius
                )
            }

            if let selected {
                RuleMark(x: .value("Выбрано", selected.mid))
                    .foregroundStyle(Color.secondary.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .zIndex(-1)
            }
        }
        .chartXScale(domain: domain.lowerBound...domain.upperBound)
        .chartYScale(domain: 0...yMax)
        .chartXAxis {
            AxisMarks(values: axis.gridDates.filter { drawn.contains($0) }) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
            }
            AxisMarks(values: axis.labelDates.filter { drawn.contains($0) }) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self), let text = axis.labels[Self.key(date)] {
                        Text(text)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: [0, yMax / 2, yMax]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        if timeline != nil {
                            // Ширина подписей не зависит от шкалы: иначе при её смене во время
                            // прокрутки (20к → 7к) сужалась область графика, Charts пересчитывал
                            // доводку, и график отскакивал на прежнюю неделю.
                            Text(ExpenseChartFormat.compact(amount))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .frame(width: Self.yAxisLabelWidth, alignment: .leading)
                        } else {
                            Text(ExpenseChartFormat.compact(amount))
                        }
                    }
                }
            }
        }
        .chartXSelection(value: $rawSelection)
        .frame(height: 220)

        if let timeline {
            base
                .chartScrollableAxes(.horizontal)
                .chartXVisibleDomain(length: pageLength)
                .chartScrollPosition(x: $scrollPosition)
                .chartScrollTargetBehavior(PageSnapBehavior(
                    alignment: ValueAlignedChartScrollTargetBehavior(matching: timeline.scale.pageStartComponents),
                    pageUnit: timeline.scale.pageUnit,
                    snap: snap
                ))
                .onChange(of: timeline.pageStart) { _, newStart in
                    // Страницу сменили стрелками — докручиваем график к ней.
                    if abs(scrollPosition.timeIntervalSince(newStart)) > 1 {
                        withAnimation(.snappy(duration: 0.35)) {
                            scrollPosition = newStart
                        }
                    }
                }
                .task(id: SettleKey(position: scrollPosition, snapped: snap.target)) {
                    // Прокрутка «успокоилась» — подтягиваем позицию к странице, до которой
                    // её довёл Charts, и сообщаем экрану новую страницу.
                    try? await Task.sleep(for: .milliseconds(250))
                    guard !Task.isCancelled else { return }
                    settleScroll()
                }
        } else {
            base
        }
    }

    /// Столбик — прямоугольник на интервале [start, end) с отступами по краям,
    /// так ширина верна и для дней, и для недель, и для неполных интервалов меток.
    private func barMark(
        _ bar: ExpenseBar,
        isDimmed: Bool,
        yMax: Double,
        insetRatio: Double,
        cornerRadius: CGFloat
    ) -> some ChartContent {
        let inset = bar.end.timeIntervalSince(bar.start) * insetRatio
        let height = min(max(bar.total, 0), yMax)

        return RectangleMark(
            xStart: .value("Начало", bar.start.addingTimeInterval(inset)),
            xEnd: .value("Конец", bar.end.addingTimeInterval(-inset)),
            yStart: .value("Ноль", 0.0),
            yEnd: .value("Сумма", height)
        )
        .foregroundStyle(tint.gradient)
        .cornerRadius(cornerRadius)
        .opacity(isDimmed ? 0.35 : 1)
    }

    // MARK: - Visible range

    /// Длина одной страницы (неделя / месяц / год) — ширина видимого окна.
    private var pageLength: TimeInterval {
        guard let timeline,
              let page = Calendar.current.dateInterval(of: timeline.scale.pageUnit, for: timeline.pageStart) else {
            return domain.upperBound.timeIntervalSince(domain.lowerBound)
        }
        return page.duration
    }

    /// Что рисовать: видимое окно и по две страницы с каждой стороны, чтобы при
    /// прокрутке края не пустели. У статичного графика — весь домен.
    ///
    /// Прокручиваемый график перерисовывается на каждом кадре прокрутки (его тело
    /// читает позицию), а столбиков, линий сетки и подписей за всю историю — сотни;
    /// их пересчёт и давал рывки.
    private func drawnRange(around window: Range<Date>) -> Range<Date> {
        guard timeline != nil else { return domain }
        let margin = pageLength * 2
        return window.lowerBound.addingTimeInterval(-margin)..<window.upperBound.addingTimeInterval(margin)
    }

    private var visibleWindow: Range<Date> {
        guard timeline != nil else { return domain }
        let end = min(scrollPosition.addingTimeInterval(pageLength), domain.upperBound)
        return scrollPosition..<max(end, scrollPosition)
    }

    /// Среднее за прошедшие единицы окна и верх шкалы по видимым столбикам.
    private func stats(in window: Range<Date>) -> (average: Double, yMax: Double) {
        let visible = bars.filter { window.contains($0.mid) }
        let sum = visible.reduce(0) { $0 + $1.total }
        let peak = visible.map(\.total).max() ?? 0

        let units: Int
        if let timeline {
            units = Self.elapsedUnits(in: window, unit: timeline.scale.barUnit)
        } else {
            units = bars.count
        }

        let average = units > 0 ? sum / Double(units) : 0
        return (average, Self.niceAxisMaximum(for: peak))
    }

    private var selectedBar: ExpenseBar? {
        guard let rawSelection else { return nil }
        if let bar = bars.first(where: { $0.start <= rawSelection && rawSelection < $0.end }) {
            return bar
        }
        // В режиме прокрутки пустые дни не хранятся — собираем пустой столбик.
        guard let unit = timeline?.scale.barUnit,
              let interval = Calendar.current.dateInterval(of: unit, for: rawSelection) else {
            return nil
        }
        return ExpenseBar(
            start: interval.start,
            end: interval.end,
            total: 0,
            title: ExpenseChartFormat.title(for: interval.start, unit: unit)
        )
    }

    /// Когда заново ждать, пока прокрутка успокоится: сдвинулась позиция
    /// или Charts выбрал, куда довести график.
    private struct SettleKey: Equatable {
        let position: Date
        let snapped: Date?
    }

    /// Прокрутка остановилась: сверяем позицию с тем, что на экране, и сообщаем
    /// экрану страницу. По позиции строятся подпись периода и шкала.
    private func settleScroll() {
        guard let timeline else { return }
        let unit = timeline.scale.pageUnit
        let snapped = snap.target
        snap.target = nil

        var position = scrollPosition
        // Позиция между страницами — её оставила прокрутка пальцем, а доводку до
        // страницы Charts сделал уже без привязки: берём страницу из доводки.
        // Позиции на границе страницы (листание стрелками) доверяем: доводка
        // в этот момент могла считаться по ленте до её расширения.
        if PageSnapBehavior.pageStart(near: position, unit: unit) == nil,
           let snapped,
           let start = PageSnapBehavior.pageStart(near: snapped, unit: unit) {
            scrollPosition = start
            position = start
        }

        // Пока палец держит график между страницами — ничего не сообщаем.
        guard let start = PageSnapBehavior.pageStart(near: position, unit: unit),
              abs(start.timeIntervalSince(timeline.pageStart)) > 1 else {
            return
        }
        timeline.onPageSettled(start)
    }

    // MARK: - Helpers

    /// Хватает на «12,5к» и «1,8М».
    private static let yAxisLabelWidth: CGFloat = 32

    /// Сколько дней / месяцев окна уже наступило (будущее в среднее не входит).
    private static func elapsedUnits(in window: Range<Date>, unit: Calendar.Component) -> Int {
        let calendar = Calendar.current
        let todayEnd = calendar.dateInterval(of: unit, for: .now)?.end ?? .now
        let end = min(window.upperBound, todayEnd)
        guard var current = calendar.dateInterval(of: unit, for: window.lowerBound)?.start else { return 0 }

        var count = 0
        while current < end {
            // Единица, начавшаяся до окна, считается, только если её большая часть в окне.
            let next = calendar.date(byAdding: unit, value: 1, to: current) ?? end
            guard next > current else { break }
            let mid = current.addingTimeInterval(next.timeIntervalSince(current) / 2)
            if mid >= window.lowerBound && mid < end {
                count += 1
            }
            current = next
        }
        return count
    }

    // Верх шкалы: максимум, округлённый вверх до «круглого» шага (22к → 30к).
    private static func niceAxisMaximum(for value: Double) -> Double {
        guard value > 0 else { return 1000 }
        let step = pow(10, floor(log10(value)))
        return (floor(value / step) + 1) * step
    }

    private static func key(_ date: Date) -> Int {
        Int(date.timeIntervalSince1970.rounded())
    }

    private static func timelineAxis(scale: AnalyticsTimeScale, domain: Range<Date>) -> AxisLayout {
        let calendar = Calendar.current
        let unit = scale.barUnit
        var axis = AxisLayout()
        var current = domain.lowerBound

        while current < domain.upperBound {
            let next = calendar.date(byAdding: unit, value: 1, to: current) ?? domain.upperBound
            guard next > current else { break }
            let mid = current.addingTimeInterval(next.timeIntervalSince(current) / 2)

            let label: String?
            switch scale {
            case .week:
                label = ExpenseChartFormat.weekday(current)
            case .month:
                // Подписи и линии — только по понедельникам, как раньше.
                label = calendar.component(.weekday, from: current) == calendar.firstWeekday
                    ? ExpenseChartFormat.dayNumber(current)
                    : nil
            case .year:
                label = ExpenseChartFormat.monthInitial(current)
            }

            if let label {
                axis.gridDates.append(current)
                axis.labelDates.append(mid)
                axis.labels[key(mid)] = label
            }
            current = next
        }
        return axis
    }

    private static func staticAxis(bars: [ExpenseBar], labels: [String]) -> AxisLayout {
        var axis = AxisLayout()
        for (index, bar) in bars.enumerated() {
            guard index < labels.count, !labels[index].isEmpty else { continue }
            axis.gridDates.append(bar.start)
            axis.labelDates.append(bar.mid)
            axis.labels[key(bar.mid)] = labels[index]
        }
        return axis
    }
}

// MARK: - Scale units

extension AnalyticsTimeScale {
    /// Ширина одного столбика.
    var barUnit: Calendar.Component {
        switch self {
        case .week, .month: return .day
        case .year: return .month
        }
    }

    /// Страница, к границе которой доводится прокрутка.
    var pageUnit: Calendar.Component {
        switch self {
        case .week: return .weekOfYear
        case .month: return .month
        case .year: return .year
        }
    }

    var pageStartComponents: DateComponents {
        switch self {
        case .week: return DateComponents(hour: 0, weekday: Calendar.current.firstWeekday)
        case .month: return DateComponents(day: 1, hour: 0)
        case .year: return DateComponents(month: 1, day: 1, hour: 0)
        }
    }
}

// MARK: - Formatting

enum ExpenseChartFormat {
    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = format
        return formatter
    }

    private static let dayMonthYear = formatter("d MMM yyyy")
    private static let dayMonth = formatter("d MMM")
    private static let day = formatter("d")
    private static let weekdayShort = formatter("EEE")
    private static let monthFull = formatter("LLLL")
    private static let monthYear = formatter("LLLL yyyy")
    private static let monthShort = formatter("LLL")
    private static let monthShortYear = formatter("LLL yyyy")
    private static let year = formatter("yyyy")

    static func title(for start: Date, unit: Calendar.Component) -> String {
        unit == .month ? monthYear.string(from: start).capitalized : dayMonthYear.string(from: start)
    }

    static func weekday(_ date: Date) -> String {
        weekdayShort.string(from: date)
    }

    static func dayNumber(_ date: Date) -> String {
        day.string(from: date)
    }

    static func monthInitial(_ date: Date) -> String {
        String(monthFull.string(from: date).prefix(1)).uppercased()
    }

    /// «1–31 окт. 2026», «28 сент. – 4 окт. 2026», «2026», «окт. 2025 – сент. 2026».
    static func range(start: Date, endExclusive: Date, unit: Calendar.Component) -> String {
        let calendar = Calendar.current
        let last = calendar.date(byAdding: unit, value: -1, to: endExclusive).map { max($0, start) } ?? start
        let sameYear = calendar.component(.year, from: start) == calendar.component(.year, from: last)
        let sameMonth = sameYear && calendar.component(.month, from: start) == calendar.component(.month, from: last)

        if unit == .month {
            if sameYear && calendar.component(.month, from: start) == 1 && calendar.component(.month, from: last) == 12 {
                return year.string(from: start)
            }
            if sameMonth {
                return monthYear.string(from: start).capitalized
            }
            let startText = sameYear ? monthShort.string(from: start) : monthShortYear.string(from: start)
            return "\(startText) – \(monthShortYear.string(from: last))"
        }

        if calendar.isDate(start, inSameDayAs: last) {
            return dayMonthYear.string(from: start)
        }
        if sameMonth {
            return "\(day.string(from: start))–\(dayMonthYear.string(from: last))"
        }
        let startText = sameYear ? dayMonth.string(from: start) : dayMonthYear.string(from: start)
        return "\(startText) – \(dayMonthYear.string(from: last))"
    }

    static func rub(_ value: Double) -> String {
        value.formatted(.currency(code: "RUB").locale(Locale(identifier: "ru_RU")).precision(.fractionLength(0)))
    }

    // Компактная подпись оси: 300к, 1,8М (как в «Здоровье»).
    static func compact(_ value: Double) -> String {
        guard value > 0 else { return "0" }
        var scaled = value
        var suffix = ""
        if value >= 1_000_000 {
            scaled = value / 1_000_000
            suffix = "М"
        } else if value >= 1_000 {
            scaled = value / 1_000
            suffix = "к"
        }
        let number = scaled.formatted(.number.locale(Locale(identifier: "ru_RU")).precision(.fractionLength(0...1)).grouping(.never))
        return number + suffix
    }
}
