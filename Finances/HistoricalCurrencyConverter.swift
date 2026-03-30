//
//  HistoricalCurrencyConverter.swift
//  Finances
//
//  Created by Андрей Матиенко on 22.03.2026.
//


import Foundation

enum HistoricalCurrencyConverter {
    static func rubAmount(
        for amountKZT: Double,
        on date: Date,
        rates: [ExchangeRateEntry],
        fallbackKztPerRub: Double?
    ) -> Double? {
        let calendar = Calendar.current
        let targetDay = calendar.startOfDay(for: date)

        let sortedRates = rates.sorted { $0.date > $1.date }

        if let exact = sortedRates.first(where: { calendar.isDate($0.date, inSameDayAs: targetDay) }) {
            guard exact.kztPerRub > 0 else { return nil }
            return amountKZT / exact.kztPerRub
        }

        if let previous = sortedRates.first(where: { $0.date <= targetDay && $0.kztPerRub > 0 }) {
            return amountKZT / previous.kztPerRub
        }

        if let fallbackKztPerRub, fallbackKztPerRub > 0 {
            return amountKZT / fallbackKztPerRub
        }

        return nil
    }
}