//
//  CurrencyDisplay.swift
//  Finances
//
//  Created by Андрей Матиенко on 31.03.2026.
//


import Foundation

enum CurrencyDisplay {
    static func normalizedCode(from value: String) -> String {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "₽", "RUB", "RUR":
            return "RUB"
        case "₸", "KZT":
            return "KZT"
        case "₫", "VND":
            return "VND"
        case "$", "USD":
            return "USD"
        case "€", "EUR":
            return "EUR"
        case "¥", "JPY":
            return "JPY"
        case "S$", "SGD":
            return "SGD"
        case "CNY", "RMB":
            return "CNY"
        case "THB", "฿":
            return "THB"
        case "LKR":
            return "LKR"
        default:
            return value.uppercased()
        }
    }

    static func title(for storedValue: String) -> String {
        SupportedCurrency.byCode(storedValue).title
    }

    static func symbol(for storedValue: String) -> String {
        SupportedCurrency.byCode(storedValue).symbol
    }

    /// Флаг страны валюты: первые две буквы кода — это страна (KZT → KZ).
    static func flag(for storedValue: String) -> String {
        let code = normalizedCode(from: storedValue)
        if code == "EUR" { return "🇪🇺" }
        let region = String(code.prefix(2))
        guard code.count == 3,
              Locale.Region.isoRegions.contains(where: { $0.identifier == region }) else { return "🏳️" }
        return region.unicodeScalars
            .compactMap { Unicode.Scalar(0x1F1E6 - 0x41 + $0.value) }
            .map(String.init)
            .joined()
    }
}