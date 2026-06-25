//
//  SupportedInputCurrency.swift
//  Finances
//
//  Created by Андрей Матиенко on 22.03.2026.
//


import Foundation

struct SupportedInputCurrency: Identifiable, Hashable {
    let code: String
    let displayName: String
    let flag: String

    var id: String { code }
}

enum SupportedInputCurrencies {
    static let all: [SupportedInputCurrency] = [
        .init(code: "KZT", displayName: "Казахстанский тенге", flag: "🇰🇿"),
        .init(code: "RUB", displayName: "Российский рубль", flag: "🇷🇺"),
        .init(code: "USD", displayName: "Доллар США", flag: "🇺🇸"),
        .init(code: "VND", displayName: "Вьетнамский донг", flag: "🇻🇳"),
        .init(code: "EUR", displayName: "Евро", flag: "🇪🇺"),
        .init(code: "THB", displayName: "Тайский бат", flag: "🇹🇭"),
        .init(code: "CNY", displayName: "Китайский юань", flag: "🇨🇳"),
        .init(code: "KRW", displayName: "Южнокорейская вона", flag: "🇰🇷"),
        .init(code: "JPY", displayName: "Японская иена", flag: "🇯🇵"),
        .init(code: "GBP", displayName: "Фунт стерлингов", flag: "🇬🇧"),
        .init(code: "TRY", displayName: "Турецкая лира", flag: "🇹🇷"),
        .init(code: "AED", displayName: "Дирхам ОАЭ", flag: "🇦🇪")
    ]
}