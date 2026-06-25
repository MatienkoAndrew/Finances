//
//  ExpenseFilter.swift
//  Finances
//
//  Created by Андрей Матиенко on 19.03.2026.
//


import Foundation

enum ExpenseFilter: String, CaseIterable {
    case all = "Все"
    case purchase = "Покупки"
    case topUp = "Пополнения"
    case transfer = "Переводы"
    case withdrawal = "Снятия"

    func matches(_ expense: Expense) -> Bool {
        switch self {
        case .all:
            return true
        case .purchase:
            return expense.operationType == "Покупка"
        case .topUp:
            return expense.operationType == "Пополнение"
        case .transfer:
            return expense.operationType == "Перевод"
        case .withdrawal:
            return expense.operationType == "Снятие"
        }
    }
}