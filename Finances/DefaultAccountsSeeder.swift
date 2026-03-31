//
//  DefaultAccountsSeeder.swift
//  Finances
//
//  Created by Андрей Матиенко on 30.03.2026.
//


import Foundation
import SwiftData

enum DefaultAccountsSeeder {
    static func seedIfNeeded(
        existingAccounts: [Account],
        modelContext: ModelContext
    ) {
        guard existingAccounts.isEmpty else { return }

        let defaults = [
            Account(name: "Kaspi", currencyCode: "₸", typeRaw: AccountType.bankCard.rawValue),
            Account(name: "Cash KZT", currencyCode: "₸", typeRaw: AccountType.cash.rawValue),
            Account(name: "Cash RUB", currencyCode: "₽", typeRaw: AccountType.cash.rawValue),
            Account(name: "Cash VND", currencyCode: "₫", typeRaw: AccountType.cash.rawValue)
        ]

        for account in defaults {
            modelContext.insert(account)
        }

        try? modelContext.save()
    }
}