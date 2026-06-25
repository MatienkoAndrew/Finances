import Foundation
import CryptoKit

struct ParsedStatementRow {
    let date: Date
    let amount: Double
    let accountCurrency: String
    let operationType: String
    let details: String
    let foreignAmount: Double?
    let foreignCurrency: String?
    let fingerprint: String
}

enum KaspiStatementParser {
    private static let operationTypes: Set<String> = [
        "Покупка",
        "Пополнение",
        "Перевод",
        "Снятие",
        "Разное"
    ]

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yy"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    static func parse(lines: [PDFTextLine]) -> [ParsedStatementRow] {
        let filteredLines = lines
            .map(\.text)
            .map(cleanupLine)
            .filter { !$0.isEmpty }
            .filter { !shouldSkipLine($0) }

        var result: [ParsedStatementRow] = []
        var index = 0

        while index < filteredLines.count {
            let line = filteredLines[index]

            guard let parsedMain = parseMainTransactionLine(line) else {
                index += 1
                continue
            }

            var foreignAmount: Double?
            var foreignCurrency: String?

            if index + 1 < filteredLines.count {
                let nextLine = filteredLines[index + 1]

                if !startsWithDate(nextLine),
                   let parsedForeign = parseForeignAmountLine(nextLine) {

                    if parsedMain.operationType == "Пополнение" {
                        foreignAmount = abs(parsedForeign.amount)
                    } else {
                        foreignAmount = -abs(parsedForeign.amount)
                    }

                    foreignCurrency = parsedForeign.currency
                    index += 1
                }
            }

            let fingerprint = makeFingerprint(
                date: parsedMain.date,
                amount: parsedMain.amount,
                accountCurrency: parsedMain.accountCurrency,
                operationType: parsedMain.operationType,
                details: parsedMain.details,
                foreignAmount: foreignAmount,
                foreignCurrency: foreignCurrency
            )

            result.append(
                ParsedStatementRow(
                    date: parsedMain.date,
                    amount: parsedMain.amount,
                    accountCurrency: parsedMain.accountCurrency,
                    operationType: parsedMain.operationType,
                    details: parsedMain.details,
                    foreignAmount: foreignAmount,
                    foreignCurrency: foreignCurrency,
                    fingerprint: fingerprint
                )
            )

            index += 1
        }

        return result
    }

    private static func parseMainTransactionLine(_ line: String) -> (
        date: Date,
        amount: Double,
        accountCurrency: String,
        operationType: String,
        details: String
    )? {
        let parts = line.split(separator: " ").map(String.init)
        guard parts.count >= 4 else { return nil }

        let dateString = parts[0]
        guard let date = dateFormatter.date(from: dateString) else { return nil }

        guard let operationIndex = parts.firstIndex(where: { operationTypes.contains($0) }) else {
            return nil
        }

        let amountTokens = Array(parts[1..<operationIndex])
        let amountString = amountTokens.joined(separator: " ")

        guard let parsedAmount = parseNumber(amountString) else {
            return nil
        }

        let operationType = parts[operationIndex]
        let detailsTokens = Array(parts[(operationIndex + 1)...])
        let details = detailsTokens.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)

        let signedAmount: Double
        if operationType == "Пополнение" {
            signedAmount = abs(parsedAmount)
        } else {
            signedAmount = -abs(parsedAmount)
        }

        return (
            date: date,
            amount: signedAmount,
            accountCurrency: "₸",
            operationType: operationType,
            details: details
        )
    }

    
    private static func parseForeignAmountLine(_ line: String) -> (amount: Double, currency: String)? {
        let parts = line.split(separator: " ").map(String.init)
        guard parts.count >= 2 else { return nil }

        let currency = parts.last!
        let amountString = parts.dropLast().joined(separator: " ")

        guard let amount = parseNumber(amountString) else { return nil }
        return (amount, currency)
    }

    private static func parseNumber(_ string: String) -> Double? {
        let normalized = string
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")

        return Double(normalized)
    }

    private static func startsWithDate(_ line: String) -> Bool {
        let pattern = #"^\d{2}\.\d{2}\.\d{2}\b"#
        return line.range(of: pattern, options: .regularExpression) != nil
    }

    private static func shouldSkipLine(_ line: String) -> Bool {
        if line.hasPrefix("АО Kaspi Bank") { return true }
        if line == "Дата Сумма Операция Детали" { return true }
        if line == "ВЫПИСКА" { return true }
        if line.hasPrefix("по Kaspi Gold за период") { return true }
        if line.hasPrefix("Краткое содержание операций") { return true }
        if line.hasPrefix("Доступно на ") { return true }
        if line.hasPrefix("Пополнения ") { return true }
        if line.hasPrefix("Переводы ") { return true }
        if line.hasPrefix("Покупки ") { return true }
        if line.hasPrefix("Снятия ") { return true }
        if line.hasPrefix("Разное ") { return true }
        if line.hasPrefix("Сумма заблокирована") { return true }
        return false
    }

    private static func cleanupLine(_ line: String) -> String {
        line
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func makeFingerprint(
        date: Date,
        amount: Double,
        accountCurrency: String,
        operationType: String,
        details: String,
        foreignAmount: Double?,
        foreignCurrency: String?
    ) -> String {
        let foreignAmountString: String
        if let foreignAmount {
            foreignAmountString = String(foreignAmount)
        } else {
            foreignAmountString = ""
        }

        let components: [String] = [
            isoDateString(date),
            String(amount),
            accountCurrency,
            operationType,
            details,
            foreignAmountString,
            foreignCurrency ?? ""
        ]

        let raw = components.joined(separator: "|")
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    
    private static func isoDateString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.string(from: date)
    }
}
