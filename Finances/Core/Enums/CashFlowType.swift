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
            return expense.countsAsExpenseInAnalytics
        case .income:
            return expense.countsAsIncomeInAnalytics
        }
    }
}
