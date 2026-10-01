//
//  RubRateTable.swift
//  Finances
//
//  Курсы к рублю по дням — снимок из базы для быстрых расчётов.
//  Курс на дату — последний известный на этот день (в выходные и праздники
//  ЦБ курс не устанавливает); если дата раньше всех известных — самый ранний.
//

import Foundation
import SwiftData

struct RubRateTable {
    /// Код → курсы по возрастанию дня.
    private var rates: [String: [(day: Date, rubPerUnit: Double)]] = [:]
    /// Последний известный курс, если по дням ничего нет (например, без интернета).
    private let fallback: [String: Double]
    private let calendar: Calendar

    init(rates: [DailyExchangeRate] = [], fallback: [String: Double] = [:], calendar: Calendar = .current) {
        self.fallback = fallback
        self.calendar = calendar
        for rate in rates where rate.rubPerUnit > 0 {
            self.rates[rate.code.uppercased(), default: []].append((rate.day, rate.rubPerUnit))
        }
        for code in self.rates.keys {
            self.rates[code]?.sort { $0.day < $1.day }
        }
    }

    /// Таблица из базы: курсы по дням и, на крайний случай, текущие курсы из настроек.
    @MainActor
    static func load(context: ModelContext) -> RubRateTable {
        let rates = (try? context.fetch(FetchDescriptor<DailyExchangeRate>())) ?? []
        let tracked = (try? context.fetch(FetchDescriptor<TrackedExchangeRate>())) ?? []
        let settings = try? context.fetch(FetchDescriptor<AppSettings>()).first

        var fallback: [String: Double] = [:]
        for rate in tracked where rate.rubPerUnit > 0 {
            fallback[rate.code.uppercased()] = rate.rubPerUnit
        }
        if let kztPerRub = settings?.kztPerRub, kztPerRub > 0, fallback["KZT"] == nil {
            fallback["KZT"] = 1 / kztPerRub
        }
        return RubRateTable(rates: rates, fallback: fallback)
    }

    /// Сколько рублей за 1 единицу валюты на этот день.
    func rubPerUnit(_ code: String, on date: Date) -> Double? {
        let code = CurrencyDisplay.normalizedCode(from: code)
        if code == "RUB" { return 1 }

        guard let series = rates[code], !series.isEmpty else { return fallback[code] }
        let day = calendar.startOfDay(for: date)

        // Последний курс не позже этого дня (бинарный поиск).
        var low = 0
        var high = series.count - 1
        var found: Int?
        while low <= high {
            let mid = (low + high) / 2
            if series[mid].day <= day {
                found = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return series[found ?? 0].rubPerUnit
    }

    /// Последний известный курс и предыдущий — для экрана валют.
    func latest(_ code: String) -> (rubPerUnit: Double, day: Date, previous: Double?)? {
        let code = CurrencyDisplay.normalizedCode(from: code)
        guard let series = rates[code], let last = series.last else {
            return fallback[code].map { ($0, .distantPast, nil) }
        }
        let previous = series.count > 1 ? series[series.count - 2].rubPerUnit : nil
        return (last.rubPerUnit, last.day, previous)
    }

    /// ₽-эквивалент суммы в валюте на дату операции.
    func rubAmount(amount: Double, currencyCode: String, on date: Date) -> Double? {
        rubPerUnit(currencyCode, on: date).map { abs(amount) * $0 }
    }

    func hasDailyRates(for code: String) -> Bool {
        rates[CurrencyDisplay.normalizedCode(from: code)]?.isEmpty == false
    }
}
