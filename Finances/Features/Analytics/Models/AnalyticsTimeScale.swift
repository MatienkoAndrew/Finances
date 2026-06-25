//
//  AnalyticsTimeScale.swift
//  Finances
//
//  Created by Андрей Матиенко on 31.03.2026.
//


import Foundation

enum AnalyticsTimeScale: String, CaseIterable, Identifiable {
    case week = "W"
    case month = "M"
    case year = "Y"

    var id: String { rawValue }

    // Подпись для верхних вкладок (стиль Alipay).
    var tabTitle: String {
        switch self {
        case .week: return "Неделя"
        case .month: return "Месяц"
        case .year: return "Год"
        }
    }

    var averageTitle: String {
        switch self {
        case .week, .month:
            return "СРЕДНЕЕ В ДЕНЬ"
        case .year:
            return "СРЕДНЕЕ В МЕСЯЦ"
        }
    }

    var selectedPointTitle: String {
        switch self {
        case .week, .month:
            return "ДЕНЬ"
        case .year:
            return "МЕСЯЦ"
        }
    }
}