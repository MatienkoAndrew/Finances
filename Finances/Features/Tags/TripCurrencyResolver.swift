//
//  TripCurrencyResolver.swift
//  Finances
//
//  В какой стране была трата, если платили не местной валютой.
//
//  В Корее терминал предлагает списать в USD вместо KRW, Alipay списывает в юанях,
//  на Шри-Ланке отели и экскурсии стоят в долларах. По одной валюте такая трата
//  попала бы в «США» или «Китай». Поэтому:
//  1. Даты поездки важнее валюты: если у метки страны заданы даты, то траты
//     в иностранной валюте за эти дни относятся к ней.
//  2. Без поездки на эти дни доллары и евро относятся к стране, в валюте
//     которой в тот же и соседние дни платили не реже.
//

import Foundation
import SwiftData

struct TripCurrencyResolver {

    /// Валюты, которыми платят далеко за пределами их страны.
    static let internationalCurrencies: Set<String> = ["USD", "EUR"]

    /// Метка страны: её валюта и, если заданы, даты поездки.
    /// Метки на USD и EUR сюда не входят — по ним не понять, где была трата.
    struct CountryTag {
        let code: String
        /// От начала первого дня до начала дня после последнего.
        let period: DateInterval?

        init?(code: String?, start: Date?, end: Date?, calendar: Calendar = .current) {
            guard let code = code?.uppercased(), !code.isEmpty,
                  code != CurrencyTagSuggestions.baseCurrencyCode,
                  !TripCurrencyResolver.internationalCurrencies.contains(code) else { return nil }
            self.code = code
            if let start, let end,
               let dayAfterEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end)) {
                let firstDay = calendar.startOfDay(for: start)
                period = DateInterval(start: firstDay, end: max(dayAfterEnd, firstDay))
            } else {
                period = nil
            }
        }

        init?(tag: TransactionTag) {
            self.init(code: tag.autoCurrencyCode, start: tag.startDate, end: tag.endDate)
        }

        func covers(_ date: Date) -> Bool {
            guard let period else { return false }
            return date >= period.start && date < period.end
        }
    }

    /// Сколько дней по обе стороны от траты смотреть на соседей.
    private static let windowDays = 1

    private let calendar: Calendar
    private let countryTags: [CountryTag]
    /// Начало дня → сколько операций в каждой валюте мерчанта.
    private let countsByDay: [Date: [String: Int]]

    init(transactions: [Transaction], countryTags: [CountryTag], calendar: Calendar = .current) {
        self.calendar = calendar
        self.countryTags = countryTags
        // Голосуют только расходы: зарплата в тенге не говорит, где ты был.
        var counts: [Date: [String: Int]] = [:]
        for transaction in transactions where transaction.kind == .expense {
            guard let code = CurrencyTagSuggestions.merchantCurrency(of: transaction) else { continue }
            counts[calendar.startOfDay(for: transaction.date), default: [:]][code, default: 0] += 1
        }
        countsByDay = counts
    }

    init(transactions: [Transaction], tags: [TransactionTag], calendar: Calendar = .current) {
        self.init(transactions: transactions, countryTags: tags.compactMap(CountryTag.init(tag:)), calendar: calendar)
    }

    /// Соседи одной операции из базы — когда её добавили или изменили вручную.
    init(around transaction: Transaction, tags: [TransactionTag], context: ModelContext, calendar: Calendar = .current) {
        let day = calendar.startOfDay(for: transaction.date)
        var neighbors: [Transaction] = []
        if let from = calendar.date(byAdding: .day, value: -Self.windowDays, to: day),
           let to = calendar.date(byAdding: .day, value: Self.windowDays + 1, to: day) {
            let descriptor = FetchDescriptor<Transaction>(predicate: #Predicate { $0.date >= from && $0.date < to })
            neighbors = (try? context.fetch(descriptor)) ?? []
        }
        let id = transaction.persistentModelID
        self.init(transactions: neighbors.filter { $0.persistentModelID != id } + [transaction], tags: tags, calendar: calendar)
    }

    /// Валюта страны, где была трата. Обычно это валюта мерчанта; иностранная
    /// валюта в даты поездки — валюта поездки; доллары и евро вне поездок —
    /// валюта, которой в эти дни платили не реже. Рубли — это дом.
    func locationCurrency(of transaction: Transaction) -> String? {
        guard let code = CurrencyTagSuggestions.merchantCurrency(of: transaction) else { return nil }
        if code == CurrencyTagSuggestions.baseCurrencyCode { return code }

        let trips = countryTags.filter { $0.covers(transaction.date) }
        let tripCode = trips.min {
            ($0.period?.duration ?? 0, $0.code) < ($1.period?.duration ?? 0, $1.code)
        }?.code
        let isForeign = Self.isForeignPayment(transaction, code: code)

        // Своя метка у валюты есть: вона — это Корея, если только в эти дни
        // не было другой поездки, а платили картой в иностранной валюте.
        let own = countryTags.filter { $0.code == code }
        if !own.isEmpty {
            if own.contains(where: { $0.period == nil || $0.covers(transaction.date) }) { return code }
            if isForeign, let tripCode { return tripCode }
            return code
        }

        if isForeign, let tripCode { return tripCode }
        guard Self.internationalCurrencies.contains(code) else { return code }
        return majorityCurrency(around: transaction.date, against: code)
    }

    // MARK: - Private

    /// Оплата не в валюте своего счёта: картой в тенге списали доллары, юани, воны.
    /// Тенге с тенгевой карты сюда не попадают — это траты дома, а не в поездке.
    private static func isForeignPayment(_ transaction: Transaction, code: String) -> Bool {
        if internationalCurrencies.contains(code) { return true }
        guard let foreign = transaction.foreignCurrencyCode?.uppercased(), !foreign.isEmpty else { return false }
        return foreign != transaction.currencyCode.uppercased()
    }

    private func majorityCurrency(around date: Date, against code: String) -> String {
        let day = calendar.startOfDay(for: date)
        var votes: [String: Int] = [:]
        for offset in -Self.windowDays...Self.windowDays {
            guard let date = calendar.date(byAdding: .day, value: offset, to: day),
                  let counts = countsByDay[calendar.startOfDay(for: date)] else { continue }
            votes.merge(counts, uniquingKeysWith: +)
        }

        let own = max(votes.removeValue(forKey: code) ?? 0, 1)
        let local = votes.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.first
        guard let local, local.value >= own else { return code }
        return local.key
    }
}
