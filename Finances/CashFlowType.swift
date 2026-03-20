//
//  CashFlowType.swift
//  Finances
//
//  Created by Андрей Матиенко on 20.03.2026.
//


import Foundation

enum CashFlowType: String {
    case expenses = "Расходы"
    case income = "Пополнения"

    func matches(_ expense: Expense) -> Bool {
        switch self {
        case .expenses:
            return expense.amount < 0
        case .income:
            return expense.amount > 0
        }
    }
}