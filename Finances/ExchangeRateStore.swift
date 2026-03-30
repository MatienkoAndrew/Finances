//
//  ExchangeRateStore.swift
//  Finances
//
//  Created by Андрей Матиенко on 22.03.2026.
//


import Foundation
import SwiftData

enum ExchangeRateStore {
    static func upsertRates(
        _ ratesByDate: [Date: Double],
        existingRates: [ExchangeRateEntry],
        modelContext: ModelContext
    ) {
        let calendar = Calendar.current

        for (date, rate) in ratesByDate {
            let day = calendar.startOfDay(for: date)

            if let existing = existingRates.first(where: { calendar.isDate($0.date, inSameDayAs: day) }) {
                existing.kztPerRub = rate
                existing.source = "NBK"
            } else {
                let item = ExchangeRateEntry(date: day, kztPerRub: rate, source: "NBK")
                modelContext.insert(item)
            }
        }
    }
}