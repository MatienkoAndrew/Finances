//
//  TransactionRubRecalculator.swift
//  Finances
//
//  Created by Андрей Матиенко on 31.03.2026.
//


import Foundation

enum TransactionRubRecalculator {
    static func recalculate(
        transactions: [Transaction],
        settings: AppSettings?,
        trackedRates: [TrackedExchangeRate]
    ) {
        for transaction in transactions {
            switch transaction.kind {
            case .expense, .income:
                transaction.rubAmount = TransactionRubConverter.rubAmount(
                    amount: transaction.amount,
                    currencyCode: transaction.currencyCode,
                    settings: settings,
                    trackedRates: trackedRates
                )

            case .transfer:
                // Для перевода тоже сохраняем ₽-эквивалент списания.
                transaction.rubAmount = TransactionRubConverter.rubAmount(
                    amount: transaction.amount,
                    currencyCode: transaction.currencyCode,
                    settings: settings,
                    trackedRates: trackedRates
                )
            }
        }
    }
}