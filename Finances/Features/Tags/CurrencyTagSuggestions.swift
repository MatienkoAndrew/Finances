//
//  CurrencyTagSuggestions.swift
//  Finances
//
//  «Умные метки» — подсказки тегов-стран на основе валют транзакций.
//  Если в данных встречаются транзакции в HKD, SGD, VND и т.д., приложение
//  предлагает одним тапом создать метку для соответствующей страны и сразу
//  применить её ко всем подходящим тратам.
//

import Foundation
import SwiftData

struct CurrencyCountryInfo {
    let code: String        // ISO-код валюты, например "HKD"
    let countryName: String // Имя метки, например "Гонконг"
    let icon: String        // Эмодзи-флаг
    let colorHex: String    // Hex цвета метки
}

struct CurrencyTagSuggestion: Identifiable {
    var id: String { info.code }
    let info: CurrencyCountryInfo
    let transactionCount: Int
    let firstDate: Date
    let lastDate: Date
}

enum CurrencyTagSuggestions {

    /// Валюта приложения по умолчанию. Транзакции в ней не считаются «иностранными»
    /// и не порождают подсказку метки-страны.
    static let baseCurrencyCode = "RUB"

    /// Карта поддерживаемых валют → страна / иконка / цвет.
    /// Список умышленно не исчерпывающий: то, что не покрыто, просто
    /// не превратится в подсказку, и это нормально.
    static let countryByCurrency: [String: CurrencyCountryInfo] = [
        // Азия
        "HKD": .init(code: "HKD", countryName: "Гонконг", icon: "🇭🇰", colorHex: "#FF3B30"),
        "SGD": .init(code: "SGD", countryName: "Сингапур", icon: "🇸🇬", colorHex: "#FF3B30"),
        "MYR": .init(code: "MYR", countryName: "Малайзия", icon: "🇲🇾", colorHex: "#FFCC00"),
        "THB": .init(code: "THB", countryName: "Таиланд", icon: "🇹🇭", colorHex: "#5AC8FA"),
        "VND": .init(code: "VND", countryName: "Вьетнам", icon: "🇻🇳", colorHex: "#FF3B30"),
        "IDR": .init(code: "IDR", countryName: "Индонезия", icon: "🇮🇩", colorHex: "#FF3B30"),
        "PHP": .init(code: "PHP", countryName: "Филиппины", icon: "🇵🇭", colorHex: "#007AFF"),
        "JPY": .init(code: "JPY", countryName: "Япония", icon: "🇯🇵", colorHex: "#FF3B30"),
        "KRW": .init(code: "KRW", countryName: "Южная Корея", icon: "🇰🇷", colorHex: "#007AFF"),
        "CNY": .init(code: "CNY", countryName: "Китай", icon: "🇨🇳", colorHex: "#FF3B30"),
        "TWD": .init(code: "TWD", countryName: "Тайвань", icon: "🇹🇼", colorHex: "#007AFF"),
        "INR": .init(code: "INR", countryName: "Индия", icon: "🇮🇳", colorHex: "#FF9500"),
        "LKR": .init(code: "LKR", countryName: "Шри-Ланка", icon: "🇱🇰", colorHex: "#FF9500"),
        "NPR": .init(code: "NPR", countryName: "Непал", icon: "🇳🇵", colorHex: "#FF3B30"),
        "PKR": .init(code: "PKR", countryName: "Пакистан", icon: "🇵🇰", colorHex: "#34C759"),
        "BDT": .init(code: "BDT", countryName: "Бангладеш", icon: "🇧🇩", colorHex: "#34C759"),
        "MVR": .init(code: "MVR", countryName: "Мальдивы", icon: "🇲🇻", colorHex: "#5AC8FA"),
        "KHR": .init(code: "KHR", countryName: "Камбоджа", icon: "🇰🇭", colorHex: "#007AFF"),
        "LAK": .init(code: "LAK", countryName: "Лаос", icon: "🇱🇦", colorHex: "#FF3B30"),
        "MMK": .init(code: "MMK", countryName: "Мьянма", icon: "🇲🇲", colorHex: "#FFCC00"),
        "MNT": .init(code: "MNT", countryName: "Монголия", icon: "🇲🇳", colorHex: "#5AC8FA"),
        "BND": .init(code: "BND", countryName: "Бруней", icon: "🇧🇳", colorHex: "#FFCC00"),
        "AED": .init(code: "AED", countryName: "ОАЭ", icon: "🇦🇪", colorHex: "#34C759"),
        "SAR": .init(code: "SAR", countryName: "Саудовская Аравия", icon: "🇸🇦", colorHex: "#34C759"),
        "QAR": .init(code: "QAR", countryName: "Катар", icon: "🇶🇦", colorHex: "#5AC8FA"),
        "OMR": .init(code: "OMR", countryName: "Оман", icon: "🇴🇲", colorHex: "#FF3B30"),
        "KWD": .init(code: "KWD", countryName: "Кувейт", icon: "🇰🇼", colorHex: "#34C759"),
        "BHD": .init(code: "BHD", countryName: "Бахрейн", icon: "🇧🇭", colorHex: "#FF3B30"),
        "JOD": .init(code: "JOD", countryName: "Иордания", icon: "🇯🇴", colorHex: "#FF3B30"),
        "LBP": .init(code: "LBP", countryName: "Ливан", icon: "🇱🇧", colorHex: "#FF3B30"),
        "ILS": .init(code: "ILS", countryName: "Израиль", icon: "🇮🇱", colorHex: "#007AFF"),

        // Кавказ / СНГ
        "GEL": .init(code: "GEL", countryName: "Грузия", icon: "🇬🇪", colorHex: "#FF3B30"),
        "AMD": .init(code: "AMD", countryName: "Армения", icon: "🇦🇲", colorHex: "#FF9500"),
        "AZN": .init(code: "AZN", countryName: "Азербайджан", icon: "🇦🇿", colorHex: "#34C759"),
        "KZT": .init(code: "KZT", countryName: "Казахстан", icon: "🇰🇿", colorHex: "#34C759"),
        "UZS": .init(code: "UZS", countryName: "Узбекистан", icon: "🇺🇿", colorHex: "#5AC8FA"),
        "KGS": .init(code: "KGS", countryName: "Кыргызстан", icon: "🇰🇬", colorHex: "#FF3B30"),
        "TRY": .init(code: "TRY", countryName: "Турция", icon: "🇹🇷", colorHex: "#FF3B30"),

        // Европа
        "EUR": .init(code: "EUR", countryName: "Еврозона", icon: "🇪🇺", colorHex: "#007AFF"),
        "GBP": .init(code: "GBP", countryName: "Великобритания", icon: "🇬🇧", colorHex: "#007AFF"),
        "CHF": .init(code: "CHF", countryName: "Швейцария", icon: "🇨🇭", colorHex: "#FF3B30"),
        "PLN": .init(code: "PLN", countryName: "Польша", icon: "🇵🇱", colorHex: "#FF3B30"),
        "CZK": .init(code: "CZK", countryName: "Чехия", icon: "🇨🇿", colorHex: "#FF3B30"),
        "RSD": .init(code: "RSD", countryName: "Сербия", icon: "🇷🇸", colorHex: "#FF3B30"),
        "HUF": .init(code: "HUF", countryName: "Венгрия", icon: "🇭🇺", colorHex: "#34C759"),
        "RON": .init(code: "RON", countryName: "Румыния", icon: "🇷🇴", colorHex: "#FFCC00"),
        "BGN": .init(code: "BGN", countryName: "Болгария", icon: "🇧🇬", colorHex: "#34C759"),

        // Америки
        "USD": .init(code: "USD", countryName: "США", icon: "🇺🇸", colorHex: "#007AFF"),
        "CAD": .init(code: "CAD", countryName: "Канада", icon: "🇨🇦", colorHex: "#FF3B30"),
        "ARS": .init(code: "ARS", countryName: "Аргентина", icon: "🇦🇷", colorHex: "#5AC8FA"),
        "BRL": .init(code: "BRL", countryName: "Бразилия", icon: "🇧🇷", colorHex: "#34C759"),
        "MXN": .init(code: "MXN", countryName: "Мексика", icon: "🇲🇽", colorHex: "#34C759"),

        // Африка
        "EGP": .init(code: "EGP", countryName: "Египет", icon: "🇪🇬", colorHex: "#FF9500"),
        "MAD": .init(code: "MAD", countryName: "Марокко", icon: "🇲🇦", colorHex: "#FF3B30"),
        "ZAR": .init(code: "ZAR", countryName: "ЮАР", icon: "🇿🇦", colorHex: "#34C759"),

        // Океания
        "AUD": .init(code: "AUD", countryName: "Австралия", icon: "🇦🇺", colorHex: "#34C759"),
        "NZD": .init(code: "NZD", countryName: "Новая Зеландия", icon: "🇳🇿", colorHex: "#34C759"),
    ]

    /// Возвращает «реальную» валюту транзакции — в какой стране была покупка.
    ///
    /// Если у транзакции есть `foreignCurrencyCode` (например, оплата картой в KZT
    /// в магазине, который списывает в HKD), берём его — это валюта мерчанта.
    /// Иначе берём `currencyCode` карты/счёта.
    static func merchantCurrency(of transaction: Transaction) -> String? {
        let raw = transaction.foreignCurrencyCode?.uppercased()
            ?? transaction.currencyCode.uppercased()
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Считает предложенные метки-страны.
    /// Скрывает те страны, для которых уже есть метка с таким же именем или валютой.
    /// Доллары и евро, потраченные в поездке, считаются за страну поездки.
    static func computeSuggestions(
        transactions: [Transaction],
        existingTags: [TransactionTag]
    ) -> [CurrencyTagSuggestion] {
        let existingNames = Set(existingTags.map { $0.name.lowercased() })
        let existingCodes = Set(existingTags.compactMap { $0.autoCurrencyCode?.uppercased() })
        let resolver = TripCurrencyResolver(transactions: transactions, tags: existingTags)

        var counts: [String: Int] = [:]
        var firstDates: [String: Date] = [:]
        var lastDates: [String: Date] = [:]

        for tx in transactions where tx.kind != .transfer {
            guard let code = resolver.locationCurrency(of: tx) else { continue }
            if code == baseCurrencyCode { continue }

            counts[code, default: 0] += 1

            if let cur = firstDates[code] {
                firstDates[code] = min(cur, tx.date)
            } else {
                firstDates[code] = tx.date
            }
            if let cur = lastDates[code] {
                lastDates[code] = max(cur, tx.date)
            } else {
                lastDates[code] = tx.date
            }
        }

        return counts.compactMap { (code, count) -> CurrencyTagSuggestion? in
            guard let info = countryByCurrency[code] else { return nil }
            if existingNames.contains(info.countryName.lowercased()) || existingCodes.contains(code) { return nil }
            guard let first = firstDates[code], let last = lastDates[code] else { return nil }
            return CurrencyTagSuggestion(
                info: info,
                transactionCount: count,
                firstDate: first,
                lastDate: last
            )
        }
        .sorted { $0.transactionCount > $1.transactionCount }
    }

    /// Создаёт метку из подсказки и применяет её ко всем подходящим транзакциям.
    static func createTag(
        from suggestion: CurrencyTagSuggestion,
        modelContext: ModelContext
    ) {
        // Второе касание по карточке, пока она исчезает, не должно создать копию.
        let existingTags = (try? modelContext.fetch(FetchDescriptor<TransactionTag>())) ?? []
        let isTaken = existingTags.contains {
            $0.name.caseInsensitiveCompare(suggestion.info.countryName) == .orderedSame
                || $0.autoCurrencyCode?.uppercased() == suggestion.info.code
        }
        guard !isTaken else { return }

        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: suggestion.firstDate)
        let endDate = calendar.startOfDay(for: suggestion.lastDate)

        let tag = TransactionTag(
            name: suggestion.info.countryName,
            startDate: startDate,
            endDate: endDate,
            icon: suggestion.info.icon,
            colorHex: suggestion.info.colorHex,
            autoCurrencyCode: suggestion.info.code
        )
        modelContext.insert(tag)

        // Заодно доллары и юани из этой поездки переедут из чужих меток.
        TransactionTagSync.run(context: modelContext)
    }

    /// Краткое описание периода: например "5–8 ноя 2025" или "окт 2024 – мар 2025".
    static func periodDescription(from start: Date, to end: Date) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")

        if calendar.isDate(start, inSameDayAs: end) {
            formatter.dateFormat = "d MMM yyyy"
            return formatter.string(from: start)
        }

        let startYear = calendar.component(.year, from: start)
        let endYear = calendar.component(.year, from: end)
        let startMonth = calendar.component(.month, from: start)
        let endMonth = calendar.component(.month, from: end)

        if startYear == endYear && startMonth == endMonth {
            formatter.dateFormat = "d"
            let s = formatter.string(from: start)
            formatter.dateFormat = "d MMM yyyy"
            return "\(s)–\(formatter.string(from: end))"
        }

        if startYear == endYear {
            formatter.dateFormat = "d MMM"
            let s = formatter.string(from: start)
            formatter.dateFormat = "d MMM yyyy"
            return "\(s)–\(formatter.string(from: end))"
        }

        formatter.dateFormat = "d MMM yyyy"
        return "\(formatter.string(from: start))–\(formatter.string(from: end))"
    }
}
