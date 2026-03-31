//
//  TransactionKindFilter.swift
//  Finances
//
//  Created by Андрей Матиенко on 30.03.2026.
//


import Foundation

enum TransactionKindFilter: String, CaseIterable, Identifiable {
    case all = "Все"
    case expenses = "Расходы"
    case income = "Доходы"
    case transfers = "Переводы"

    var id: String { rawValue }

    func matches(_ transaction: Transaction) -> Bool {
        switch self {
        case .all:
            return true
        case .expenses:
            return transaction.kind == .expense
        case .income:
            return transaction.kind == .income
        case .transfers:
            return transaction.kind == .transfer
        }
    }
}