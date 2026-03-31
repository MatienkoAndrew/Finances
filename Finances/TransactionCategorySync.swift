import Foundation
import SwiftData

enum TransactionCategorySync {
    static func renameCategory(
        from oldName: String,
        to newName: String,
        transactions: [Transaction],
        legacyExpenses: [Expense],
        rules: [CategoryRule]
    ) {
        guard oldName != newName else { return }

        for transaction in transactions where transaction.categoryName == oldName {
            transaction.categoryName = newName
        }

        for expense in legacyExpenses where expense.categoryName == oldName {
            expense.categoryName = newName
        }

        for rule in rules where rule.categoryName == oldName {
            rule.categoryName = newName
        }
    }

    static func clearCategoryReferences(
        named name: String,
        transactions: [Transaction],
        legacyExpenses: [Expense],
        rules: [CategoryRule],
        fallbackCategoryName: String = "Другое"
    ) {
        for transaction in transactions where transaction.categoryName == name {
            transaction.categoryName = nil
        }

        for expense in legacyExpenses where expense.categoryName == name {
            expense.categoryName = nil
        }

        for rule in rules where rule.categoryName == name {
            rule.categoryName = fallbackCategoryName
        }
    }

    static func reassignCategoryReferences(
        from oldName: String,
        to newName: String,
        transactions: [Transaction],
        legacyExpenses: [Expense],
        rules: [CategoryRule]
    ) {
        guard oldName != newName else { return }

        for transaction in transactions where transaction.categoryName == oldName {
            transaction.categoryName = newName
        }

        for expense in legacyExpenses where expense.categoryName == oldName {
            expense.categoryName = newName
        }

        for rule in rules where rule.categoryName == oldName {
            rule.categoryName = newName
        }
    }

    static func autoCategorizeTransactions(
        _ transactions: [Transaction],
        rules: [CategoryRule],
        overwriteExisting: Bool = false
    ) {
        for transaction in transactions {
            guard transaction.kind == .expense else { continue }

            if !overwriteExisting, transaction.categoryName != nil {
                continue
            }

            let guessed = CategoryRuleEngine.matchCategoryName(
                operationType: transaction.ruleOperationType,
                details: transaction.details,
                rules: rules
            )

            if let guessed {
                transaction.categoryName = guessed
            }
        }
    }
}

extension Transaction {
    var ruleOperationType: String {
        switch kind {
        case .expense:
            return "Покупка"
        case .income:
            return "Пополнение"
        case .transfer:
            return "Перевод"
        }
    }
}
