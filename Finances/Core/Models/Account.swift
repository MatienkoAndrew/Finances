//
//  Account.swift
//  Finances
//
//  Created by Андрей Матиенко on 30.03.2026.
//


import Foundation
import SwiftData

@Model
final class Account {
    var name: String
    var currencyCode: String
    var typeRaw: String
    var note: String?
    var isArchived: Bool
    var createdAt: Date

    init(
        name: String,
        currencyCode: String,
        typeRaw: String,
        note: String? = nil,
        isArchived: Bool = false,
        createdAt: Date = Date()
    ) {
        self.name = name
        self.currencyCode = currencyCode
        self.typeRaw = typeRaw
        self.note = note
        self.isArchived = isArchived
        self.createdAt = createdAt
    }
}

extension Account {
    var type: AccountType {
        get { AccountType(rawValue: typeRaw) ?? .cash }
        set { typeRaw = newValue.rawValue }
    }

    var displayTitle: String {
        "\(name) • \(currencyCode)"
    }
}

enum AccountType: String, CaseIterable, Identifiable {
    case cash
    case bankCard
    case bankAccount
    case savings
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cash: return "Наличные"
        case .bankCard: return "Карта"
        case .bankAccount: return "Банковский счет"
        case .savings: return "Накопления"
        case .other: return "Другое"
        }
    }

    var systemImage: String {
        switch self {
        case .cash: return "banknote"
        case .bankCard: return "creditcard"
        case .bankAccount: return "building.columns"
        case .savings: return "tray.full"
        case .other: return "square.stack"
        }
    }
}