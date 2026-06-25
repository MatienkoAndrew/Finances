//
//  ExchangeRateEntry.swift
//  Finances
//
//  Created by Андрей Матиенко on 22.03.2026.
//


import Foundation
import SwiftData

@Model
final class ExchangeRateEntry {
    var date: Date
    /// Сколько KZT за 1 RUB
    var kztPerRub: Double
    var source: String
    var createdAt: Date

    init(
        date: Date,
        kztPerRub: Double,
        source: String = "NBK",
        createdAt: Date = Date()
    ) {
        self.date = Calendar.current.startOfDay(for: date)
        self.kztPerRub = kztPerRub
        self.source = source
        self.createdAt = createdAt
    }
}