//
//  ManualExpenseCurrencyConverter.swift
//  Finances
//
//  Created by Андрей Матиенко on 22.03.2026.
//


import Foundation

enum ManualExpenseCurrencyConverter {
    static func kztAmount(
        enteredAmount: Double,
        currencyCode: String,
        kztPerRub: Double,
        trackedRates: [TrackedExchangeRate]
    ) -> Double? {
        let code = currencyCode.uppercased()

        switch code {
        case "KZT":
            return enteredAmount

        case "RUB":
            return enteredAmount * kztPerRub

        default:
            guard let tracked = trackedRates.first(where: { $0.code.uppercased() == code }) else {
                return nil
            }

            let kztPerUnit = tracked.rubPerUnit * kztPerRub
            return enteredAmount * kztPerUnit
        }
    }

    static func rubAmount(
        enteredAmount: Double,
        currencyCode: String,
        kztPerRub: Double,
        trackedRates: [TrackedExchangeRate]
    ) -> Double? {
        let code = currencyCode.uppercased()

        switch code {
        case "RUB":
            return enteredAmount

        case "KZT":
            guard kztPerRub > 0 else { return nil }
            return enteredAmount / kztPerRub

        default:
            guard let tracked = trackedRates.first(where: { $0.code.uppercased() == code }) else {
                return nil
            }
            return enteredAmount * tracked.rubPerUnit
        }
    }
}