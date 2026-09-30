import Foundation

enum KaspiOperationType: String, CaseIterable {
    case purchase = "Покупка"
    case topUp = "Пополнение"
    case transfer = "Перевод"
    case withdrawal = "Снятие"
    case misc = "Разное"

    /// Как тип называется в блоке «Краткое содержание операций».
    var summaryTitle: String {
        switch self {
        case .purchase: return "Покупки"
        case .topUp: return "Пополнения"
        case .transfer: return "Переводы"
        case .withdrawal: return "Снятия"
        case .misc: return "Разное"
        }
    }
}

struct ParsedStatementRow {
    /// День операции (полдень по локальному времени — см. `KaspiStatementParser.makeDate`).
    let date: Date
    /// Сумма в валюте счёта со знаком, как в выписке: «+» — зачисление, «-» — списание.
    let amount: Double
    let accountCurrency: String
    let operationType: KaspiOperationType
    let details: String
    /// Сумма в валюте операции со знаком, если операция была не в тенге.
    let foreignAmount: Double?
    let foreignCurrency: String?
    /// Kaspi пересчитал сумму ранее проведённой валютной покупки
    /// и довёл/вернул разницу отдельной строкой («Курсовая разница»).
    let isExchangeRateDifference: Bool
}

struct KaspiStatement {
    let periodStart: Date?
    let periodEnd: Date?
    let rows: [ParsedStatementRow]
    /// Итоги из блока «Краткое содержание операций по карте».
    let summaryTotals: [KaspiOperationType: Double]
    /// Строки, похожие на операцию (начинаются с даты и суммы), но не распознанные.
    let unrecognizedLines: [String]

    /// Типы операций, по которым сумма распознанных строк не сходится с итогом выписки.
    /// Пусто — значит, все операции прочитаны без потерь.
    var mismatchedTypes: [KaspiOperationType] {
        KaspiOperationType.allCases.filter { type in
            guard let expected = summaryTotals[type] else { return false }
            let actual = rows
                .filter { $0.operationType == type }
                .reduce(0) { $0 + $1.amount }
            return abs(actual - expected) > 0.005
        }
    }
}

/// Парсер выписки Kaspi Gold.
///
/// Формат строк после `PDFLayoutTextExtractor`:
/// ```
/// 29.09.26 - 4 613,91 ₸ Покупка MAMSTERCHILAB ITAEWONJ
/// (- 14 000,00 KRW)
/// 29.09.26 + 4,57 ₸ Покупка GS25SEOKYOTEUNTEUNJUM
/// Курсовая разница
/// ```
enum KaspiStatementParser {
    private static let amountPattern = #"([+-])\s*(\d[\d\s]*,\d{2})"#

    private static let rowRegex = try! Regex(
        #"^(\d{2}\.\d{2}\.\d{2})\s+"# + amountPattern + #"\s*₸"#
        + #"(?:\s*\(\s*"# + amountPattern + #"\s+([A-Z]{3})\s*\))?"#
        + #"\s+(\#(KaspiOperationType.allCases.map(\.rawValue).joined(separator: "|")))"#
        + #"(?:\s+(.*))?$"#
    )

    private static let foreignAmountRegex = try! Regex(
        #"^\(\s*"# + amountPattern + #"\s+([A-Z]{3})\s*\)$"#
    )

    /// Похоже на начало строки операции — используется, чтобы не пропустить
    /// нераспознанную операцию молча.
    private static let rowLikeRegex = try! Regex(#"^\d{2}\.\d{2}\.\d{2}\s+[+-]"#)

    private static let periodRegex = try! Regex(
        #"за период с (\d{2}\.\d{2}\.\d{2}) по (\d{2}\.\d{2}\.\d{2})"#
    )

    private static let summaryRegex = try! Regex(
        #"^(\#(KaspiOperationType.allCases.map(\.summaryTitle).joined(separator: "|")))\s+"#
        + amountPattern + #"\s*₸"#
    )

    private static let exchangeRateDifferenceLine = "Курсовая разница"
    private static let blockedAmountPrefix = "- Сумма заблокирована"

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yy"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    static func parse(lines: [PDFTextLine]) -> KaspiStatement {
        let texts = lines
            .map { normalizeWhitespace($0.text) }
            .filter { !$0.isEmpty }

        var periodStart: Date?
        var periodEnd: Date?
        var summaryTotals: [KaspiOperationType: Double] = [:]
        var rows: [ParsedStatementRow] = []
        var unrecognizedLines: [String] = []

        // Строка операции, к которой ещё могут относиться строки-продолжения.
        var pending: PendingRow?

        func flushPending() {
            if let row = pending?.build() {
                rows.append(row)
            }
            pending = nil
        }

        for text in texts {
            if let row = parseRowLine(text) {
                flushPending()
                pending = row
                continue
            }

            if var current = pending {
                if current.foreignAmount == nil, let foreign = parseForeignAmountLine(text) {
                    current.foreignAmount = foreign.amount
                    current.foreignCurrency = foreign.currency
                    pending = current
                    continue
                }

                if text == exchangeRateDifferenceLine {
                    current.isExchangeRateDifference = true
                    pending = current
                    continue
                }

                // Сноска под таблицей, к конкретной строке не привязана.
                if text.hasPrefix(blockedAmountPrefix) {
                    continue
                }

                // Любая другая строка (колонтитул, шапка страницы) закрывает операцию.
                flushPending()
            }

            if rows.isEmpty, periodStart == nil,
               let match = text.firstMatch(of: periodRegex) {
                periodStart = parseDate(match.output[1].substring)
                periodEnd = parseDate(match.output[2].substring)
                continue
            }

            if rows.isEmpty,
               let match = text.firstMatch(of: summaryRegex),
               let title = match.output[1].substring,
               let type = KaspiOperationType.allCases.first(where: { $0.summaryTitle == title }),
               summaryTotals[type] == nil,
               let amount = parseSignedAmount(sign: match.output[2].substring, digits: match.output[3].substring) {
                summaryTotals[type] = amount
                continue
            }

            if text.firstMatch(of: rowLikeRegex) != nil {
                unrecognizedLines.append(text)
            }
        }

        flushPending()

        return KaspiStatement(
            periodStart: periodStart,
            periodEnd: periodEnd,
            rows: rows,
            summaryTotals: summaryTotals,
            unrecognizedLines: unrecognizedLines
        )
    }

    // MARK: - Lines

    private struct PendingRow {
        let date: Date
        let amount: Double
        let operationType: KaspiOperationType
        let details: String
        var foreignAmount: Double?
        var foreignCurrency: String?
        var isExchangeRateDifference = false

        func build() -> ParsedStatementRow {
            ParsedStatementRow(
                date: date,
                amount: amount,
                accountCurrency: "KZT",
                operationType: operationType,
                details: details,
                foreignAmount: foreignAmount,
                foreignCurrency: foreignCurrency,
                isExchangeRateDifference: isExchangeRateDifference
            )
        }
    }

    private static func parseRowLine(_ text: String) -> PendingRow? {
        guard let match = text.wholeMatch(of: rowRegex),
              let date = parseDate(match.output[1].substring),
              let amount = parseSignedAmount(sign: match.output[2].substring, digits: match.output[3].substring),
              let typeRaw = match.output[7].substring,
              let operationType = KaspiOperationType(rawValue: String(typeRaw)) else {
            return nil
        }

        let details = match.output[8].substring.map(String.init) ?? ""

        var row = PendingRow(
            date: date,
            amount: amount,
            operationType: operationType,
            details: details.trimmingCharacters(in: .whitespaces)
        )

        // Валютная сумма обычно на следующей строке, но может оказаться и на этой.
        if let foreign = parseSignedAmount(sign: match.output[4].substring, digits: match.output[5].substring),
           let currency = match.output[6].substring {
            row.foreignAmount = foreign
            row.foreignCurrency = String(currency)
        }

        return row
    }

    private static func parseForeignAmountLine(_ text: String) -> (amount: Double, currency: String)? {
        guard let match = text.wholeMatch(of: foreignAmountRegex),
              let amount = parseSignedAmount(sign: match.output[1].substring, digits: match.output[2].substring),
              let currency = match.output[3].substring else {
            return nil
        }
        return (amount, String(currency))
    }

    // MARK: - Values

    private static func parseSignedAmount(sign: Substring?, digits: Substring?) -> Double? {
        guard let sign, let digits else { return nil }

        let normalized = digits
            .filter { !$0.isWhitespace }
            .replacingOccurrences(of: ",", with: ".")

        guard let value = Double(normalized) else { return nil }
        return sign == "-" ? -value : value
    }

    private static func parseDate(_ string: Substring?) -> Date? {
        guard let string, let day = dateFormatter.date(from: String(string)) else { return nil }
        return makeDate(day)
    }

    /// Дата операции хранится на полдень, а не на полночь: так день не «уезжает»
    /// на соседний, если приложение открыть в другом часовом поясе (±11 часов).
    private static func makeDate(_ day: Date) -> Date {
        Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
    }

    private static func normalizeWhitespace(_ text: String) -> String {
        text
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
