//
//  AccountLookup.swift
//  Finances
//
//  Created by Андрей Матиенко on 30.03.2026.
//


import Foundation

enum AccountLookup {
    static func kaspi(in accounts: [Account]) -> Account? {
        accounts.first { $0.name == "Kaspi" && !$0.isArchived }
    }

    static func cashAccount(currencyCode: String, in accounts: [Account]) -> Account? {
        accounts.first {
            $0.type == .cash &&
            $0.currencyCode == currencyCode &&
            !$0.isArchived
        }
    }

    static func preferredExpenseAccount(for expense: Expense, in accounts: [Account]) -> Account? {
        if expense.sourceFileName != nil {
            return kaspi(in: accounts)
        }

        return cashAccount(currencyCode: expense.accountCurrency, in: accounts)
            ?? kaspi(in: accounts)
    }

    static func preferredIncomeAccount(for expense: Expense, in accounts: [Account]) -> Account? {
        kaspi(in: accounts) ?? cashAccount(currencyCode: expense.accountCurrency, in: accounts)
    }
}