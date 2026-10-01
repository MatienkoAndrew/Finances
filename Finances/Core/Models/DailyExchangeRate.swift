//
//  DailyExchangeRate.swift
//  Finances
//
//  Курс валюты к рублю на конкретный день: по нему считается ₽-эквивалент
//  операций этого дня. Основной источник — ЦБ РФ, для валют, которых у ЦБ нет
//  (например, LKR), — открытый currency-api.
//

import Foundation
import SwiftData

@Model
final class DailyExchangeRate {
    /// Начало дня, с которого действует курс.
    var day: Date
    /// ISO-код валюты, например "KZT".
    var code: String
    /// Сколько рублей за 1 единицу валюты.
    var rubPerUnit: Double
    /// "CBR" или "currency-api".
    var source: String

    init(day: Date, code: String, rubPerUnit: Double, source: String) {
        self.day = Calendar.current.startOfDay(for: day)
        self.code = code.uppercased()
        self.rubPerUnit = rubPerUnit
        self.source = source
    }
}
