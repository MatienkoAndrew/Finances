//
//  TransactionRubConverter.swift
//  Finances
//
//  Created by Андрей Матиенко on 30.03.2026.
//


import Foundation

enum TransactionRubConverter {
    static func rubAmount(
        amount: Double,
        currencyCode: String,
        settings: AppSettings?,
        trackedRates: [TrackedExchangeRate]
    ) -> Double? {
        let absoluteAmount = abs(amount)
        let normalized = normalizedCode(currencyCode)

        switch normalized {
        case "RUB":
            return absoluteAmount

        case "KZT":
            guard let settings else { return nil }
            return CurrencyConverter.kztToRub(
                absoluteAmount,
                kztPerRub: settings.kztPerRub
            )

        default:
            guard let rateToRub = trackedRateToRub(for: normalized, trackedRates: trackedRates) else {
                return nil
            }
            return absoluteAmount * rateToRub
        }
    }

    static func displayRubAmount(
        for transaction: Transaction,
        settings: AppSettings?,
        trackedRates: [TrackedExchangeRate]
    ) -> Double? {
        if let rubAmount = transaction.rubAmount {
            return abs(rubAmount)
        }

        return rubAmount(
            amount: transaction.amount,
            currencyCode: transaction.currencyCode,
            settings: settings,
            trackedRates: trackedRates
        )
    }

    private static func trackedRateToRub(
        for normalizedCode: String,
        trackedRates: [TrackedExchangeRate]
    ) -> Double? {
        trackedRates.first {
            Self.normalizedCode($0.code) == normalizedCode
        }?.rubPerUnit
        // Если у тебя поле называется не rateToRub, а иначе
        // (например rubRate / valueInRub), поменяй только эту строчку.
    }

    static func normalizedCode(_ value: String) -> String {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "RUB", "RUR", "₽":
            return "RUB"
        case "KZT", "₸":
            return "KZT"
        case "VND", "₫":
            return "VND"
        case "USD", "$":
            return "USD"
        case "EUR", "€":
            return "EUR"
        case "JPY", "¥":
            return "JPY"
        default:
            return value.uppercased()
        }
    }
}
