//
//  PriorityLevel.swift
//  Finances
//
//  Created by Андрей Матиенко on 01.04.2026.
//


import Foundation

enum PriorityLevel: Int, CaseIterable, Identifiable {
    case low = 100
    case medium = 500
    case high = 900

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .low: return "Низкий"
        case .medium: return "Средний"
        case .high: return "Высокий"
        }
    }

    static func from(_ raw: Int) -> PriorityLevel {
        switch raw {
        case ..<300:
            return .low
        case 300..<700:
            return .medium
        default:
            return .high
        }
    }
}