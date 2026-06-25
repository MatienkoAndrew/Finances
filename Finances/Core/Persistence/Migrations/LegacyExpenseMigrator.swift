//
//  LegacyExpenseMigrator.swift
//  Finances
//
//  Created by Андрей Матиенко on 30.03.2026.
//


import Foundation
import SwiftData

enum LegacyExpenseMigrator {
    private static let migrationKey = "hasMigratedLegacyExpensesToTransactions_v2"

    static func migrateIfNeeded(
        expenses: [Expense],
        existingTransactions: [Transaction],
        accounts: [Account],
        modelContext: ModelContext
    ) {
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        guard !expenses.isEmpty else {
            UserDefaults.standard.set(true, forKey: migrationKey)
            return
        }

        guard !accounts.isEmpty else { return }

        // Чтобы случайно не задублировать новые реальные транзакции.
        guard existingTransactions.isEmpty else { return }

        for expense in expenses {
            let transaction = makeTransaction(from: expense, accounts: accounts)
            modelContext.insert(transaction)
        }

        do {
            try modelContext.save()
            UserDefaults.standard.set(true, forKey: migrationKey)
        } catch {
            print("Failed to migrate legacy expenses: \(error)")
        }
    }

    private static func makeTransaction(from expense: Expense, accounts: [Account]) -> Transaction {
        let absoluteAmount = abs(expense.amount)

        switch expense.operationType {
        case "Покупка":
            return Transaction(
                date: expense.date,
                kindRaw: TransactionKind.expense.rawValue,
                amount: absoluteAmount,
                currencyCode: expense.accountCurrency,
                details: expense.details,
                foreignAmount: expense.foreignAmount.map(abs),
                foreignCurrencyCode: expense.foreignCurrency,
                rubAmount: expense.rubAmount,
                categoryName: expense.categoryName,
                note: expense.note,
                fingerprint: expense.fingerprint,
                sourceFileName: expense.sourceFileName,
                importedAt: expense.importedAt,
                createdAt: expense.createdAt,
                fromAccount: AccountLookup.preferredExpenseAccount(for: expense, in: accounts),
                toAccount: nil
            )

        case "Пополнение":
            return Transaction(
                date: expense.date,
                kindRaw: TransactionKind.income.rawValue,
                amount: absoluteAmount,
                currencyCode: expense.accountCurrency,
                details: expense.details,
                foreignAmount: expense.foreignAmount.map(abs),
                foreignCurrencyCode: expense.foreignCurrency,
                rubAmount: expense.rubAmount,
                categoryName: expense.categoryName,
                note: expense.note,
                fingerprint: expense.fingerprint,
                sourceFileName: expense.sourceFileName,
                importedAt: expense.importedAt,
                createdAt: expense.createdAt,
                fromAccount: nil,
                toAccount: AccountLookup.preferredIncomeAccount(for: expense, in: accounts)
            )

        case "Снятие":
            let destinationCurrency = expense.foreignCurrency ?? expense.accountCurrency
            let destinationAmount = abs(expense.foreignAmount ?? expense.amount)

            return Transaction(
                date: expense.date,
                kindRaw: TransactionKind.transfer.rawValue,
                amount: absoluteAmount,
                currencyCode: expense.accountCurrency,
                toAmount: destinationAmount,
                toCurrencyCode: destinationCurrency,
                details: expense.details,
                rubAmount: expense.rubAmount,
                categoryName: expense.categoryName,
                note: expense.note,
                fingerprint: expense.fingerprint,
                sourceFileName: expense.sourceFileName,
                importedAt: expense.importedAt,
                createdAt: expense.createdAt,
                fromAccount: AccountLookup.kaspi(in: accounts),
                toAccount: AccountLookup.cashAccount(currencyCode: destinationCurrency, in: accounts)
            )

        case "Перевод":
            let destinationCurrency = expense.foreignCurrency ?? expense.accountCurrency
            let destinationAmount = abs(expense.foreignAmount ?? expense.amount)

            return Transaction(
                date: expense.date,
                kindRaw: TransactionKind.transfer.rawValue,
                amount: absoluteAmount,
                currencyCode: expense.accountCurrency,
                toAmount: destinationAmount,
                toCurrencyCode: destinationCurrency,
                details: expense.details,
                rubAmount: expense.rubAmount,
                categoryName: expense.categoryName,
                note: expense.note,
                fingerprint: expense.fingerprint,
                sourceFileName: expense.sourceFileName,
                importedAt: expense.importedAt,
                createdAt: expense.createdAt,
                fromAccount: AccountLookup.kaspi(in: accounts),
                toAccount: AccountLookup.cashAccount(currencyCode: destinationCurrency, in: accounts)
            )

        default:
            if expense.amount >= 0 {
                return Transaction(
                    date: expense.date,
                    kindRaw: TransactionKind.income.rawValue,
                    amount: absoluteAmount,
                    currencyCode: expense.accountCurrency,
                    details: expense.details,
                    foreignAmount: expense.foreignAmount.map(abs),
                    foreignCurrencyCode: expense.foreignCurrency,
                    rubAmount: expense.rubAmount,
                    categoryName: expense.categoryName,
                    note: expense.note,
                    fingerprint: expense.fingerprint,
                    sourceFileName: expense.sourceFileName,
                    importedAt: expense.importedAt,
                    createdAt: expense.createdAt,
                    fromAccount: nil,
                    toAccount: AccountLookup.preferredIncomeAccount(for: expense, in: accounts)
                )
            } else {
                return Transaction(
                    date: expense.date,
                    kindRaw: TransactionKind.expense.rawValue,
                    amount: absoluteAmount,
                    currencyCode: expense.accountCurrency,
                    details: expense.details,
                    foreignAmount: expense.foreignAmount.map(abs),
                    foreignCurrencyCode: expense.foreignCurrency,
                    rubAmount: expense.rubAmount,
                    categoryName: expense.categoryName,
                    note: expense.note,
                    fingerprint: expense.fingerprint,
                    sourceFileName: expense.sourceFileName,
                    importedAt: expense.importedAt,
                    createdAt: expense.createdAt,
                    fromAccount: AccountLookup.preferredExpenseAccount(for: expense, in: accounts),
                    toAccount: nil
                )
            }
        }
    }
}