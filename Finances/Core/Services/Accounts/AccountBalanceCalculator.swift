import Foundation
import SwiftData

enum AccountBalanceCalculator {
    @MainActor private static var cache: (revision: Int, count: Int, balances: [PersistentIdentifier: Double])?

    /// Балансы, посчитанные один раз на ревизию операций.
    @MainActor
    static func cachedBalances(_ snapshot: AllTransactionsSnapshot) -> [PersistentIdentifier: Double] {
        if let cache, cache.revision == snapshot.revision, cache.count == snapshot.items.count {
            return cache.balances
        }
        let result = balances(transactions: snapshot.items)
        cache = (snapshot.revision, snapshot.items.count, result)
        return result
    }

    /// Балансы всех счетов за один проход по операциям — для списка счетов,
    /// где иначе каждый счёт заново перебирал бы все операции.
    static func balances(transactions: [Transaction]) -> [PersistentIdentifier: Double] {
        var result: [PersistentIdentifier: Double] = [:]

        for transaction in transactions {
            switch transaction.kind {
            case .expense:
                if let from = transaction.fromAccount?.persistentModelID {
                    result[from, default: 0] -= transaction.amount
                }

            case .income:
                if let to = transaction.toAccount?.persistentModelID {
                    result[to, default: 0] += transaction.amount
                }

            case .transfer:
                if let from = transaction.fromAccount?.persistentModelID {
                    result[from, default: 0] -= transaction.amount
                }

                if let to = transaction.toAccount?.persistentModelID {
                    result[to, default: 0] += transaction.creditedAmount
                }
            }
        }

        return result
    }

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
