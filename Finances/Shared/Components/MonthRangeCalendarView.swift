//
//  MonthRangeCalendarView.swift
//  Finances
//
//  Created by Андрей Матиенко on 20.03.2026.
//


import SwiftUI

struct MonthRangeCalendarView: View {
    let month: MonthSelection
    let startDate: Date?
    let endDate: Date?
    let onSelectDate: (Date) -> Void

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible()), count: 7)

    private var monthDate: Date {
        let comps = DateComponents(year: month.year, month: month.month, day: 1)
        return calendar.date(from: comps) ?? Date()
    }

    private var days: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: monthDate),
              let firstOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: monthDate))
        else { return [] }

        let weekday = calendar.component(.weekday, from: firstOfMonth)
        let leadingEmpty = (weekday - calendar.firstWeekday + 7) % 7

        var result: [Date?] = Array(repeating: nil, count: leadingEmpty)

        for day in range {
            let date = calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth)
            result.append(date)
        }

        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(month.title)
                .font(.title3.bold())

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(Array(days.enumerated()), id: \.offset) { _, date in
                    if let date {
                        DayCell(
                            date: date,
                            isStart: isSame(date, startDate),
                            isEnd: isSame(date, endDate),
                            isInRange: isInRange(date),
                            action: { onSelectDate(date) }
                        )
                    } else {
                        Color.clear
                            .frame(height: 36)
                    }
                }
            }
        }
    }

    private var weekdaySymbols: [String] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        return formatter.shortStandaloneWeekdaySymbols
    }

    private func isSame(_ lhs: Date, _ rhs: Date?) -> Bool {
        guard let rhs else { return false }
        return calendar.isDate(lhs, inSameDayAs: rhs)
    }

    private func isInRange(_ date: Date) -> Bool {
        guard let startDate, let endDate else { return false }
        let day = calendar.startOfDay(for: date)
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        return day >= start && day <= end
    }
}

private struct DayCell: View {
    let date: Date
    let isStart: Bool
    let isEnd: Bool
    let isInRange: Bool
    let action: () -> Void

    private let calendar = Calendar.current

    var body: some View {
        Button(action: action) {
            Text("\(calendar.component(.day, from: date))")
                .font(.subheadline)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var background: some View {
        if isStart || isEnd {
            Color.accentColor.opacity(0.9)
        } else if isInRange {
            Color.accentColor.opacity(0.2)
        } else {
            Color.gray.opacity(0.08)
        }
    }
}