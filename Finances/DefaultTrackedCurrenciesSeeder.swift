//
//  DefaultTrackedCurrenciesSeeder.swift
//  Finances
//
//  Created by Андрей Матиенко on 31.03.2026.
//


import Foundation
import SwiftData

enum DefaultTrackedCurrenciesSeeder {
    struct Seed {
        let code: String
        let displayName: String
        let flag: String
    }

    static let defaults: [Seed] = [
        .init(code: "USD", displayName: "Доллар США", flag: "🇺🇸"),
        .init(code: "EUR", displayName: "Евро", flag: "🇪🇺"),
        .init(code: "CNY", displayName: "Китайский юань", flag: "🇨🇳"),
        .init(code: "VND", displayName: "Вьетнамский донг", flag: "🇻🇳"),
        .init(code: "SGD", displayName: "Сингапурский доллар", flag: "🇸🇬")
    ]

    @discardableResult
    static func seedMissing(
        existingRates: [TrackedExchangeRate],
        modelContext: ModelContext
    ) -> [TrackedExchangeRate] {
        let existingCodes = Set(existingRates.map { $0.code.uppercased() })
        var inserted: [TrackedExchangeRate] = []

        for item in defaults where !existingCodes.contains(item.code) {
            let rate = TrackedExchangeRate(
                code: item.code,
                displayName: item.displayName,
                flag: item.flag,
                rubPerUnit: 0
            )
            modelContext.insert(rate)
            inserted.append(rate)
        }

        if !inserted.isEmpty {
            try? modelContext.save()
        }

        return inserted
    }
}