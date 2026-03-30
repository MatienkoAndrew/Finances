//
//  ExpenseRubRecalculator.swift
//  Finances
//
//  Created by Андрей Матиенко on 22.03.2026.
//


import Foundation

enum ExpenseRubRecalculator {
    static func recalculate(
        expenses: [Expense],
        rates: [ExchangeRateEntry],
        fallbackKztPerRub: Double?
    ) {
        for expense in expenses {
            expense.rubAmount = HistoricalCurrencyConverter.rubAmount(
                for: expense.amount,
                on: expense.date,
                rates: rates,
                fallbackKztPerRub: fallbackKztPerRub
            )
        }
    }
}