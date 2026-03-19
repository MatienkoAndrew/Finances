//
//  AnalyticsPeriod.swift
//  Finances
//
//  Created by Андрей Матиенко on 19.03.2026.
//


import Foundation

enum AnalyticsPeriod: String, CaseIterable {
    case day = "День"
    case week = "Неделя"
    case month = "Месяц"
    case all = "Все"

    func contains(_ date: Date, now: Date = Date()) -> Bool {
        let calendar = Calendar.current

        switch self {
        case .day:
            return calendar.isDate(date, inSameDayAs: now)

        case .week:
            guard let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) else {
                return true
            }
            return date >= weekAgo && date <= now

        case .month:
            guard let monthAgo = calendar.date(byAdding: .month, value: -1, to: now) else {
                return true
            }
            return date >= monthAgo && date <= now

        case .all:
            return true
        }
    }
}