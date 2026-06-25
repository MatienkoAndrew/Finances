//
//  DateRangeSelection.swift
//  Finances
//
//  Created by Андрей Матиенко on 20.03.2026.
//


import Foundation

struct DateRangeSelection {
    var startDate: Date?
    var endDate: Date?

    var isComplete: Bool {
        startDate != nil && endDate != nil
    }

    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard let startDate, let endDate else { return false }

        let start = calendar.startOfDay(for: startDate)
        let end = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: endDate) ?? endDate

        return date >= start && date <= end
    }

    var title: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateStyle = .medium

        switch (startDate, endDate) {
        case let (start?, end?):
            return "\(formatter.string(from: start)) — \(formatter.string(from: end))"
        case let (start?, nil):
            return "От \(formatter.string(from: start))"
        default:
            return "Диапазон не выбран"
        }
    }
}