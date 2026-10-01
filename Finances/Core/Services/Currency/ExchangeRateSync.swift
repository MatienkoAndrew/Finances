//
//  ExchangeRateSync.swift
//  Finances
//
//  Курсы по дням и ₽-эквивалент операций.
//
//  1. Собирает, какие валюты и дни встречаются в операциях.
//  2. Догружает недостающие курсы: у ЦБ РФ — одной выгрузкой на валюту за весь
//     период, для валют, которых у ЦБ нет, — по дням из currency-api.
//  3. Пересчитывает ₽-эквивалент каждой операции по курсу на её дату.
//
//  Запускается при старте, после импорта и после ручных правок. Без интернета
//  считает по уже загруженным курсам, а недостающие догрузит в следующий раз.
//

import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class ExchangeRateSync {
    static let shared = ExchangeRateSync()

    private(set) var isRunning = false
    private(set) var lastError: String?
    private(set) var lastUpdated: Date?

    @ObservationIgnored private var rerunRequested = false
    @ObservationIgnored private let defaults = UserDefaults.standard

    /// currency-api хранит снимки с этой даты.
    private static let currencyAPIStart = DateComponents(calendar: .current, year: 2024, month: 3, day: 2).date ?? .distantPast
    /// Сколько дней запасного источника загружать за один запуск.
    private static let currencyAPIDaysPerRun = 200

    private enum Keys {
        static let lastUpdated = "rates.lastUpdated"
        static let cbrCoverage = "rates.cbrCoverage"
        static let cbrIDs = "rates.cbrIDs"
    }

    private init() {
        let stored = defaults.double(forKey: Keys.lastUpdated)
        lastUpdated = stored > 0 ? Date(timeIntervalSince1970: stored) : nil
    }

    /// Обновить курсы и пересчитать ₽-эквиваленты. Если синхронизация уже идёт,
    /// она пройдёт ещё раз по окончании — чтобы подхватить новые операции.
    func run(context: ModelContext) async {
        if isRunning {
            rerunRequested = true
            return
        }
        isRunning = true
        defer { isRunning = false }

        repeat {
            rerunRequested = false
            await syncOnce(context: context)
        } while rerunRequested
    }

    // MARK: - Sync

    private func syncOnce(context: ModelContext) async {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        guard let transactions = try? context.fetch(FetchDescriptor<Transaction>()) else { return }

        addMissingCurrencies(from: transactions, context: context)
        let tracked = (try? context.fetch(FetchDescriptor<TrackedExchangeRate>())) ?? []

        // Валюта → дни, на которые нужен курс.
        var needed: [String: Set<Date>] = [:]
        for transaction in transactions {
            let code = CurrencyDisplay.normalizedCode(from: transaction.currencyCode)
            guard code != "RUB" else { continue }
            needed[code, default: []].insert(calendar.startOfDay(for: transaction.date))
        }
        for rate in tracked {
            let code = CurrencyDisplay.normalizedCode(from: rate.code)
            guard code != "RUB" else { continue }
            needed[code, default: []].insert(today)
        }

        var store = RateStore(context: context)
        var failed = false

        do {
            try await loadCBR(needed: needed, today: today, store: &store)
        } catch {
            failed = true
        }
        if await !loadCurrencyAPI(needed: needed, store: &store) {
            failed = true
        }

        let table = RubRateTable.load(context: context)
        recalculate(transactions, table: table)
        updateCurrentRates(tracked, table: table, context: context)
        try? context.save()

        if failed {
            lastError = "Не удалось обновить курсы — проверь интернет. Пока считаем по последним известным."
        } else {
            lastError = nil
            lastUpdated = .now
            defaults.set(Date.now.timeIntervalSince1970, forKey: Keys.lastUpdated)
        }
    }

    /// ЦБ: справочник валют и курсы на сегодня, потом по валюте — недостающие куски периода.
    private func loadCBR(needed: [String: Set<Date>], today: Date, store: inout RateStore) async throws {
        let calendar = Calendar.current
        let daily = try await CBRRatesClient.daily()
        var ids = cbrIDs
        for rate in daily.rates {
            ids[rate.code] = rate.id
            if needed[rate.code] != nil {
                store.upsert(code: rate.code, day: daily.day, rubPerUnit: rate.rubPerUnit, source: "CBR")
            }
        }
        cbrIDs = ids

        var coverage = cbrCoverage
        for (code, days) in needed {
            guard let id = ids[code], let firstDay = days.min() else { continue }
            // С запасом в две недели до первой операции: на праздники ЦБ курс не ставит.
            let from = calendar.date(byAdding: .day, value: -14, to: firstDay) ?? firstDay

            var ranges: [(Date, Date)] = []
            if let covered = coverage[code], store.hasRates(for: code) {
                if from < covered.from { ranges.append((from, covered.from)) }
                if covered.to < today { ranges.append((covered.to, today)) }
            } else {
                ranges.append((from, today))
            }

            for (start, end) in ranges {
                let records = try await CBRRatesClient.dynamic(id: id, from: start, to: end)
                for record in records {
                    store.upsert(code: code, day: record.day, rubPerUnit: record.rubPerUnit, source: "CBR")
                }
                let previous = coverage[code]
                coverage[code] = (min(previous?.from ?? start, start), max(previous?.to ?? end, end))
                cbrCoverage = coverage
            }
        }
    }

    /// Валюты, которых нет у ЦБ: курс на каждый нужный день из currency-api.
    /// Возвращает false, если что-то не загрузилось.
    private func loadCurrencyAPI(needed: [String: Set<Date>], store: inout RateStore) async -> Bool {
        let cbrCodes = Set(cbrIDs.keys)
        guard !cbrCodes.isEmpty else { return true }

        let codes = needed.keys.filter { !cbrCodes.contains($0) }
        var days = Set<Date>()
        for code in codes {
            for day in needed[code] ?? [] where day >= Self.currencyAPIStart && !store.has(code: code, day: day) {
                days.insert(day)
            }
        }
        guard !days.isEmpty else { return true }

        // Сначала свежие дни; остальное догрузится в следующие запуски.
        let batch = Array(days.sorted(by: >).prefix(Self.currencyAPIDaysPerRun))
        var results: [Date: [String: Double]] = [:]
        for chunk in stride(from: 0, to: batch.count, by: 6).map({ Array(batch[$0..<min($0 + 6, batch.count)]) }) {
            await withTaskGroup(of: (Date, [String: Double]?).self) { group in
                for day in chunk {
                    group.addTask { (day, try? await CurrencyAPIClient.rubPerUnit(on: day)) }
                }
                for await (day, rates) in group {
                    if let rates { results[day] = rates }
                }
            }
        }

        for (day, rates) in results {
            for code in codes {
                if let rate = rates[code] {
                    store.upsert(code: code, day: day, rubPerUnit: rate, source: "currency-api")
                }
            }
        }
        return results.count == batch.count
    }

    // MARK: - Apply

    /// ₽-эквивалент каждой операции — по курсу на её дату. Если по валюте ещё
    /// нет ни одного курса по дням, старое значение не трогаем.
    private func recalculate(_ transactions: [Transaction], table: RubRateTable) {
        for transaction in transactions {
            let code = CurrencyDisplay.normalizedCode(from: transaction.currencyCode)
            guard code == "RUB" || table.hasDailyRates(for: code),
                  let value = table.rubAmount(amount: transaction.amount, currencyCode: code, on: transaction.date) else { continue }
            if let current = transaction.rubAmount, abs(abs(current) - value) < 0.005 { continue }
            transaction.rubAmount = value
        }
    }

    /// Текущие курсы для экрана валют и старых расчётов.
    private func updateCurrentRates(_ tracked: [TrackedExchangeRate], table: RubRateTable, context: ModelContext) {
        for rate in tracked {
            if let latest = table.latest(rate.code), latest.rubPerUnit > 0 {
                rate.rubPerUnit = latest.rubPerUnit
            }
        }
        if let kzt = table.latest("KZT"), kzt.rubPerUnit > 0 {
            if let settings = try? context.fetch(FetchDescriptor<AppSettings>()).first {
                settings.kztPerRub = 1 / kzt.rubPerUnit
            } else {
                context.insert(AppSettings(kztPerRub: 1 / kzt.rubPerUnit))
            }
        }
    }

    /// Каждая валюта из операций — в списке валют (тенге — всегда).
    private func addMissingCurrencies(from transactions: [Transaction], context: ModelContext) {
        let tracked = (try? context.fetch(FetchDescriptor<TrackedExchangeRate>())) ?? []
        var known = Set(tracked.map { CurrencyDisplay.normalizedCode(from: $0.code) })
        var codes = Set(transactions.map { CurrencyDisplay.normalizedCode(from: $0.currencyCode) })
        codes.insert("KZT")

        for code in codes.sorted() where code != "RUB" && !known.contains(code) {
            let currency = SupportedCurrency.byCode(code)
            context.insert(TrackedExchangeRate(
                code: code,
                displayName: currency.name,
                flag: CurrencyDisplay.flag(for: code),
                rubPerUnit: 0
            ))
            known.insert(code)
        }
    }

    // MARK: - Stored metadata

    /// Код валюты → её ID у ЦБ (R01335 для KZT).
    private var cbrIDs: [String: String] {
        get { defaults.dictionary(forKey: Keys.cbrIDs) as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: Keys.cbrIDs) }
    }

    /// За какой период курсы ЦБ по валюте уже загружены.
    private var cbrCoverage: [String: (from: Date, to: Date)] {
        get {
            let raw = defaults.dictionary(forKey: Keys.cbrCoverage) as? [String: [Double]] ?? [:]
            return raw.compactMapValues { pair in
                pair.count == 2 ? (Date(timeIntervalSince1970: pair[0]), Date(timeIntervalSince1970: pair[1])) : nil
            }
        }
        set {
            let raw = newValue.mapValues { [$0.from.timeIntervalSince1970, $0.to.timeIntervalSince1970] }
            defaults.set(raw, forKey: Keys.cbrCoverage)
        }
    }
}

/// Курсы в базе с быстрым поиском по (валюта, день).
@MainActor
private struct RateStore {
    private let context: ModelContext
    private var rows: [String: DailyExchangeRate] = [:]
    private var codes: Set<String> = []

    init(context: ModelContext) {
        self.context = context
        for row in (try? context.fetch(FetchDescriptor<DailyExchangeRate>())) ?? [] {
            rows[Self.key(row.code, row.day)] = row
            codes.insert(row.code)
        }
    }

    func has(code: String, day: Date) -> Bool {
        rows[Self.key(code, day)] != nil
    }

    func hasRates(for code: String) -> Bool {
        codes.contains(code)
    }

    mutating func upsert(code: String, day: Date, rubPerUnit: Double, source: String) {
        guard rubPerUnit > 0 else { return }
        let day = Calendar.current.startOfDay(for: day)
        let key = Self.key(code, day)
        if let row = rows[key] {
            if abs(row.rubPerUnit - rubPerUnit) > .ulpOfOne {
                row.rubPerUnit = rubPerUnit
                row.source = source
            }
        } else {
            let row = DailyExchangeRate(day: day, code: code, rubPerUnit: rubPerUnit, source: source)
            context.insert(row)
            rows[key] = row
            codes.insert(code)
        }
    }

    private static func key(_ code: String, _ day: Date) -> String {
        "\(code.uppercased())|\(Int(day.timeIntervalSince1970))"
    }
}
