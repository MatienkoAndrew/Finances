//
//  RangeCalendarView.swift
//  Finances
//
//  Календарь для выбора периода: касание дня — начало, второе касание — конец,
//  касание названия месяца — весь месяц. Месяцы листаются стрелками.
//

import SwiftUI

struct RangeCalendarView: View {
    /// Первый день периода; nil — период не выбран.
    @Binding var start: Date?
    /// Последний день (включительно); nil — пока выбран один день.
    @Binding var end: Date?
    /// Дни, в которые есть операции, — помечаются точкой.
    var activeDays: Set<Date> = []

    @State private var visibleMonth: Date = Self.calendar.dateInterval(of: .month, for: .now)?.start ?? .now

    private static let calendar: Calendar = {
        var calendar = Calendar.current
        calendar.locale = Locale(identifier: "ru_RU")
        calendar.firstWeekday = 2
        return calendar
    }()

    private var calendar: Calendar { Self.calendar }
    private var today: Date { calendar.startOfDay(for: .now) }

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "LLLL yyyy"
        return formatter
    }()

    var body: some View {
        VStack(spacing: 10) {
            header
            weekdayRow
            daysGrid
        }
        .padding(.vertical, 4)
        .onAppear {
            // Открываем месяц выбранного периода, если он есть.
            if let start, let month = calendar.dateInterval(of: .month, for: end ?? start)?.start {
                visibleMonth = month
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            arrow("chevron.left") { shiftMonth(-1) }
                .accessibilityLabel("Предыдущий месяц")

            Spacer()

            Button(action: selectWholeMonth) {
                HStack(spacing: 4) {
                    Text(Self.monthFormatter.string(from: visibleMonth).capitalized(with: Locale(identifier: "ru_RU")))
                        .font(.headline)
                    if isWholeMonthSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isWholeMonthSelected ? Color.accentColor.opacity(0.14) : Color(.tertiarySystemFill), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Выбирает весь месяц")

            Spacer()

            arrow("chevron.right") { shiftMonth(1) }
                .disabled(!canGoForward)
                .opacity(canGoForward ? 1 : 0.3)
                .accessibilityLabel("Следующий месяц")
        }
    }

    private func arrow(_ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.bold))
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var weekdayRow: some View {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let ordered = Array(symbols[(calendar.firstWeekday - 1)...] + symbols[..<(calendar.firstWeekday - 1)])
        return HStack(spacing: 0) {
            ForEach(Array(ordered.enumerated()), id: \.offset) { _, symbol in
                Text(symbol.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Grid

    private var monthDays: [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: visibleMonth) else { return [] }
        let weekday = calendar.component(.weekday, from: interval.start)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        let count = calendar.range(of: .day, in: .month, for: interval.start)?.count ?? 30
        let days = (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) }
        return Array(repeating: nil, count: leading) + days.map(Optional.some)
    }

    private var daysGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(Array(monthDays.enumerated()), id: \.offset) { _, day in
                if let day {
                    dayCell(day)
                } else {
                    Color.clear.frame(height: 40)
                }
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let isFuture = day > today
        let isEdge = isSameDay(day, start) || isSameDay(day, end)
        let inRange = isInRange(day)
        let isToday = calendar.isDate(day, inSameDayAs: today)

        return Button {
            select(day)
        } label: {
            ZStack {
                // Полоса диапазона: тянется от начала до конца периода.
                if inRange {
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.14))
                        .padding(.leading, isSameDay(day, start) ? 20 : 0)
                        .padding(.trailing, isSameDay(day, end ?? start) ? 20 : 0)
                }
                if isEdge {
                    Circle().fill(Color.accentColor)
                        .frame(width: 38, height: 38)
                }
                VStack(spacing: 1) {
                    Text("\(calendar.component(.day, from: day))")
                        .font(.subheadline.weight(isEdge || isToday ? .semibold : .regular))
                        .foregroundStyle(isEdge ? Color.white : (isFuture ? Color.secondary.opacity(0.5) : (isToday ? Color.accentColor : Color.primary)))
                    Circle()
                        .fill(isEdge ? Color.white : Color.secondary)
                        .frame(width: 4, height: 4)
                        .opacity(activeDays.contains(day) ? 0.7 : 0)
                }
            }
            .frame(height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
    }

    // MARK: - Selection

    private func select(_ day: Date) {
        withAnimation(.snappy(duration: 0.2)) {
            if let currentStart = start, end == nil, !calendar.isDate(day, inSameDayAs: currentStart) {
                // Второе касание — конец периода (раньше начала — меняем местами).
                if day < currentStart {
                    start = day
                    end = currentStart
                } else {
                    end = day
                }
            } else {
                start = day
                end = nil
            }
        }
    }

    private func selectWholeMonth() {
        guard let interval = calendar.dateInterval(of: .month, for: visibleMonth),
              let last = calendar.date(byAdding: .day, value: -1, to: interval.end) else { return }
        withAnimation(.snappy(duration: 0.2)) {
            start = interval.start
            end = last
        }
    }

    private var isWholeMonthSelected: Bool {
        guard let start, let end,
              let interval = calendar.dateInterval(of: .month, for: visibleMonth),
              let last = calendar.date(byAdding: .day, value: -1, to: interval.end) else { return false }
        return calendar.isDate(start, inSameDayAs: interval.start) && calendar.isDate(end, inSameDayAs: last)
    }

    private func isInRange(_ day: Date) -> Bool {
        guard let start, let end else { return false }
        return day >= calendar.startOfDay(for: start) && day <= calendar.startOfDay(for: end)
    }

    private func isSameDay(_ day: Date, _ other: Date?) -> Bool {
        guard let other else { return false }
        return calendar.isDate(day, inSameDayAs: other)
    }

    private var canGoForward: Bool {
        guard let next = calendar.date(byAdding: .month, value: 1, to: visibleMonth) else { return false }
        return next <= today
    }

    private func shiftMonth(_ value: Int) {
        if let month = calendar.date(byAdding: .month, value: value, to: visibleMonth) {
            withAnimation(.snappy(duration: 0.2)) { visibleMonth = month }
        }
    }
}
