//
//  SupportedCurrency.swift
//  Finances
//
//  Created by Андрей Матиенко on 31.03.2026.
//


import Foundation

struct SupportedCurrency: Identifiable, Hashable {
    let code: String
    let name: String
    let symbol: String

    var id: String { code }

    var title: String {
        "\(code) — \(name)"
    }

    var subtitle: String {
        symbol == code ? code : symbol
    }

    static let favorites: [String] = [
        "VND", "KZT", "RUB", "USD", "EUR", "CNY", "SGD", "THB", "LKR", "JPY"
    ]

    static let all: [SupportedCurrency] = {
        let locale = Locale(identifier: "ru_RU")

        return Locale.commonISOCurrencyCodes
            .map { code in
                SupportedCurrency(
                    code: code,
                    // Заглавная только первая буква: «Доллар США», а не «Доллар Сша».
                    name: locale.localizedString(forCurrencyCode: code).map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? code,
                    symbol: symbol(for: code)
                )
            }
            .sorted { lhs, rhs in
                let li = favorites.firstIndex(of: lhs.code) ?? Int.max
                let ri = favorites.firstIndex(of: rhs.code) ?? Int.max

                if li != ri { return li < ri }
                return lhs.code < rhs.code
            }
    }()

    static func byCode(_ code: String) -> SupportedCurrency {
        let normalized = CurrencyDisplay.normalizedCode(from: code)
        return all.first(where: { $0.code == normalized })
            ?? SupportedCurrency(code: normalized, name: normalized, symbol: normalized)
    }

    private static func symbol(for code: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        formatter.locale = Locale(identifier: "en_US")
        return formatter.currencySymbol ?? code
    }
}