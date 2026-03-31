import Foundation
import SwiftData

enum AccountBalanceCalculator {
    static func balance(
        for account: Account,
        transactions: [Transaction]
    ) -> Double {
        transactions.reduce(0) { partial, transaction in
            switch transaction.kind {
            case .expense:
                if transaction.fromAccount?.persistentModelID == account.persistentModelID {
                    return partial - transaction.amount
                }
                return partial

            case .income:
                if transaction.toAccount?.persistentModelID == account.persistentModelID {
                    return partial + transaction.amount
                }
                return partial

            case .transfer:
                var result = partial

                if transaction.fromAccount?.persistentModelID == account.persistentModelID {
                    result -= transaction.amount
                }

                if transaction.toAccount?.persistentModelID == account.persistentModelID {
                    result += transaction.creditedAmount
                }

                return result
            }
        }
    }
}
