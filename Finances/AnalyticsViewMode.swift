//
//  AnalyticsViewMode.swift
//  Finances
//
//  Created by Assistant on 10.04.2026.
//

import Foundation

/// Режим отображения аналитики: по времени или по меткам
enum AnalyticsViewMode: String, CaseIterable, Identifiable {
    case time = "Time"
    case tags = "Tags"
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .time:
            return "По периодам"
        case .tags:
            return "По меткам"
        }
    }
}
