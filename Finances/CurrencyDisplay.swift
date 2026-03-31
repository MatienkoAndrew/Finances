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
}