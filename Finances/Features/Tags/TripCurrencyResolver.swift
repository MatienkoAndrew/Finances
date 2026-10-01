//
//  TripCurrencyResolver.swift
//  Finances
//
//  В какой стране была трата, если платили «международной» валютой.
//
//  Долларами и евро платят по всему миру: в Корее терминал предлагает списать
//  в USD вместо KRW, на Шри-Ланке отели и экскурсии стоят в долларах. По одной
//  валюте такая трата попала бы в «США». Поэтому страну для USD и EUR берём по
//  соседним операциям: если в тот же и соседние дни трат в другой валюте не
//  меньше — трата относится к её стране.
//

import Foundation
import SwiftData

struct TripCurrencyResolver {

    /// Валюты, которыми платят далеко за пределами их страны.
    static let internationalCurrencies: Set<String> = ["USD", "EUR"]

    /// Сколько дней по обе стороны от траты смотреть на соседей.
    private static let windowDays = 1

    private let calendar: Calendar
    /// Начало дня → сколько операций в каждой валюте мерчанта.
    private let countsByDay: [Date: [String: Int]]

    init(transactions: [Transaction], calendar: Calendar = .current) {
        self.calendar = calendar
        var counts: [Date: [String: Int]] = [:]
        for transaction in transactions where transaction.kind != .transfer {
            guard let code = CurrencyTagSuggestions.merchantCurrency(of: transaction) else { continue }
            counts[calendar.startOfDay(for: transaction.date), default: [:]][code, default: 0] += 1
        }
        countsByDay = counts
    }

    /// Соседи одной операции из базы — когда её добавили или изменили вручную.
    init(around transaction: Transaction, context: ModelContext, calendar: Calendar = .current) {
        let day = calendar.startOfDay(for: transaction.date)
        var neighbors: [Transaction] = []
        if let from = calendar.date(byAdding: .day, value: -Self.windowDays, to: day),
           let to = calendar.date(byAdding: .day, value: Self.windowDays + 1, to: day) {
            let descriptor = FetchDescriptor<Transaction>(predicate: #Predicate { $0.date >= from && $0.date < to })
            neighbors = (try? context.fetch(descriptor)) ?? []
        }
        let id = transaction.persistentModelID
        self.init(transactions: neighbors.filter { $0.persistentModelID != id } + [transaction], calendar: calendar)
    }

    /// Валюта страны, где была трата. Обычно это валюта мерчанта, а для USD и EUR —
    /// валюта, которой в эти дни платили не реже. Рубли тоже голосуют: доллары
    /// среди рублёвых трат — это дом, а не США.
    func locationCurrency(of transaction: Transaction) -> String? {
        guard let code = CurrencyTagSuggestions.merchantCurrency(of: transaction) else { return nil }
        guard Self.internationalCurrencies.contains(code) else { return code }

        let day = calendar.startOfDay(for: transaction.date)
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
