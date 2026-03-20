//
//  MonthSelection.swift
//  Finances
//
//  Created by Андрей Матиенко on 20.03.2026.
//


import Foundation

struct MonthSelection: Hashable, Identifiable {
    let year: Int
    let month: Int

    var id: String { "\(year)-\(month)" }

    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let comps = calendar.dateComponents([.year, .month], from: date)
        return comps.year == year && comps.month == month
    }

    var title: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = 1

        let calendar = Calendar.current
        let date = calendar.date(from: comps) ?? Date()

        formatter.dateFormat = "MMM yyyy"
        return formatter.string(from: date)
    }
}