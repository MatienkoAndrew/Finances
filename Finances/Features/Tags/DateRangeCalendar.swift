//
//  DateRangeCalendar.swift
//  Finances
//
//  Один календарь для периода метки: первое касание — первый день,
//  второе — последний. Дни между ними подсвечиваются полосой.
//

import SwiftUI

struct DateRangeCalendar: View {
    @Binding var start: Date
    @Binding var end: Date
    var tint: Color = .accentColor

    /// Первый день выбран, ждём касание по последнему.
    @State private var isPickingEnd = false

    /// Начало показанного месяца.
    @State private var month = Date.now
    @State private var didLoad = false

    private let calendar = Calendar.current
    private static let locale = Locale(identifier: "ru_RU")
    private static let cellHeight: CGFloat = 44

    var body: some View {
        VStack(spacing: 10) {
            header
            weekdayRow
            VStack(spacing: 6) {
                ForEach(0..<6, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { column in
                            cell(days[row * 7 + column])
                        }
                    }
                }
            }
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            month = startOfMonth(start)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            monthButton(systemImage: "chevron.left", label: "Предыдущий месяц", offset: -1)
            Spacer()
            Text(monthTitle)
                .font(.headline)
                .contentTransition(.numericText())
            Spacer()
            monthButton(systemImage: "chevron.right", label: "Следующий месяц", offset: 1)
        }
    }

    private func monthButton(systemImage: String, label: String, offset: Int) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.25)) {
                month = calendar.date(byAdding: .month, value: offset, to: month) ?? month
            }
        } label: {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .frame(width: 36, height: 36)
                .background(Color(.tertiarySystemFill), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Self.locale
        formatter.dateFormat = "LLLL yyyy"
        let title = formatter.string(from: month)
        return title.prefix(1).uppercased() + title.dropFirst()
    }

    private var weekdayRow: some View {
        let formatter = DateFormatter()
        formatter.locale = Self.locale
        let symbols = formatter.shortStandaloneWeekdaySymbols ?? []
        // Symbols начинаются с воскресенья (weekday 1); сдвигаем под первый день недели.
        let weekdays = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 }

        return HStack(spacing: 0) {
            ForEach(weekdays, id: \.self) { index in
                let symbol = symbols.indices.contains(index) ? symbols[index] : ""
                Text(symbol.prefix(1).uppercased() + symbol.dropFirst())
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(index == 0 || index == 6 ? Color.secondary : Color.primary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Days

    /// 6 недель по 7 дней: пустые клетки до первого числа и после последнего,
    /// чтобы высота календаря не прыгала от месяца к месяцу.
    private var days: [Date?] {
        let weekday = calendar.component(.weekday, from: month)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        let count = calendar.range(of: .day, in: .month, for: month)?.count ?? 30

        var days: [Date?] = Array(repeating: nil, count: leading)
        for offset in 0..<count {
            days.append(calendar.date(byAdding: .day, value: offset, to: month))
        }
        return days + Array(repeating: nil, count: max(0, 42 - days.count))
    }

    @ViewBuilder
    private func cell(_ date: Date?) -> some View {
        if let date {
            let day = calendar.startOfDay(for: date)
            let first = calendar.startOfDay(for: start)
            let last = calendar.startOfDay(for: end)
            let isEdge = day == first || day == last

            Button {
                select(day)
            } label: {
                Text("\(calendar.component(.day, from: day))")
                    .font(.body.weight(isEdge ? .semibold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(isEdge ? Color.white : Color.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: Self.cellHeight)
                    .background {
                        if isEdge {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(tint)
                                .padding(.horizontal, 3)
                        }
                    }
                    .background { band(day: day, first: first, last: last) }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityTitle(day))
            .accessibilityAddTraits(day >= first && day <= last ? .isSelected : [])
        } else {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: Self.cellHeight)
        }
    }

    /// Полоса между первым и последним днём: у краёв — только половина клетки.
    @ViewBuilder
    private func band(day: Date, first: Date, last: Date) -> some View {
        let fill = tint.opacity(0.15)
        if first < last, day >= first, day <= last {
            HStack(spacing: 0) {
                (day == first ? Color.clear : fill)
                (day == last ? Color.clear : fill)
            }
        }
    }

    private func select(_ day: Date) {
        withAnimation(.snappy(duration: 0.2)) {
            if isPickingEnd, day >= calendar.startOfDay(for: start) {
                end = day
                isPickingEnd = false
            } else {
                start = day
                end = day
                isPickingEnd = true
            }
        }
    }

    private func startOfMonth(_ date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    private func accessibilityTitle(_ day: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Self.locale
        formatter.dateFormat = "d MMMM yyyy"
        return formatter.string(from: day)
    }
}
