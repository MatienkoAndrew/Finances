//
//  WalletAmountParser.swift
//  Finances
//
//  Сумма оплаты из автоматизации «Транзакция». «Команды» передают её текстом,
//  отформатированным по языку телефона: «2 450,00 ₸», «₸2,450.00», «$4.50»,
//  «65.000 ₫», «KZT 2450». Валюта — по символу или коду, если они есть.
//

import Foundation

nonisolated enum WalletAmountParser {
    struct Amount: Equatable {
        let value: Double
        /// ISO-код валюты; nil — в тексте нет ни символа, ни кода.
        let currencyCode: String?
    }

    static func parse(_ text: String) -> Amount? {
        guard let value = number(in: text), value > 0 else { return nil }
        return Amount(value: value, currencyCode: currencyCode(in: text))
    }

    // MARK: - Number

    private static let groupSeparators: Set<Character> = [" ", "\u{00A0}", "\u{202F}", "'", "’"]

    /// Первое число в тексте. Знак не важен: это всегда списание.
    static func number(in text: String) -> Double? {
        var token = ""
        for character in text {
            if character.isASCIIDigit {
                token.append(character)
            } else if !token.isEmpty, groupSeparators.contains(character) || character == "." || character == "," {
                token.append(character)
            } else if !token.isEmpty {
                break
            }
        }
        while let last = token.last, !last.isASCIIDigit {
            token.removeLast()
        }
        guard !token.isEmpty else { return nil }

        let digits = token.filter { !groupSeparators.contains($0) }
        let decimalSeparator = self.decimalSeparator(in: digits)

        var normalized = ""
        for (index, character) in zip(digits.indices, digits) {
            if character.isASCIIDigit {
                normalized.append(character)
            } else if character == decimalSeparator, index == digits.lastIndex(of: character) {
                normalized.append(".")
            }
        }
        return Double(normalized)
    }

    /// Если в числе есть и точка, и запятая, дробная часть — после последнего из них
    /// («1.234,56», «1,234.56»). Один разделитель — дробная часть, только если он
    /// встречается один раз и после него одна-две цифры («2450,5», «4.50»); три цифры —
    /// это тысячи («65.000 ₫», «1,200 ¥»).
    private static func decimalSeparator(in digits: String) -> Character? {
        let lastDot = digits.lastIndex(of: ".")
        let lastComma = digits.lastIndex(of: ",")

        switch (lastDot, lastComma) {
        case let (dot?, comma?):
            return dot > comma ? "." : ","
        case (_?, nil):
            return hasFraction(after: ".", in: digits) ? "." : nil
        case (nil, _?):
            return hasFraction(after: ",", in: digits) ? "," : nil
        case (nil, nil):
            return nil
        }
    }

    private static func hasFraction(after separator: Character, in digits: String) -> Bool {
        let parts = digits.split(separator: separator, omittingEmptySubsequences: false)
        return parts.count == 2 && (1...2).contains(parts[1].count)
    }

    // MARK: - Currency

    /// Символы, которые Wallet ставит вместо кода. Сначала длинные: «S$» раньше «$».
    private static let symbols: [(symbol: String, code: String)] = [
        ("US$", "USD"), ("S$", "SGD"), ("HK$", "HKD"), ("A$", "AUD"), ("C$", "CAD"),
        ("₸", "KZT"), ("₽", "RUB"), ("€", "EUR"), ("£", "GBP"), ("₩", "KRW"), ("₫", "VND"),
        ("฿", "THB"), ("₹", "INR"), ("₺", "TRY"), ("₴", "UAH"), ("₾", "GEL"), ("¥", "JPY"),
        ("$", "USD")
    ]

    /// Сокращения на русском: «2 450 тг», «500 руб.».
    private static let words: [(word: String, code: String)] = [
        ("тенге", "KZT"), ("тнг", "KZT"), ("тг", "KZT"), ("руб", "RUB")
    ]

    private static let isoCodes = Set(Locale.Currency.isoCurrencies.map(\.identifier))

    static func currencyCode(in text: String) -> String? {
        // Код из трёх заглавных латинских букв: «KZT 2 450», «2 450 VND».
        let letterRuns = text.split { !($0.isASCII && $0.isUppercase) }
        if let code = letterRuns.first(where: { $0.count == 3 && isoCodes.contains(String($0)) }) {
            return String(code)
        }

        if let match = symbols.first(where: { text.contains($0.symbol) }) {
            return match.code
        }

        let lowercased = text.lowercased()
        return words.first(where: { lowercased.contains($0.word) })?.code
    }
}

private extension Character {
    nonisolated var isASCIIDigit: Bool {
        isASCII && isNumber
    }
}
