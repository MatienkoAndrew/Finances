import Foundation
import SwiftData

/// Курсовые разницы, приписанные к своим покупкам, — только для отображения.
///
/// В базе курсовая разница остаётся отдельной операцией, как в выписке: так работают
/// повторный импорт, отмена импорта и сверка баланса. На экране она прячется, а у покупки
/// показывается итоговая сумма.
struct FoldedExchangeRateDifferences {
    static let empty = FoldedExchangeRateDifferences(differencesByPurchase: [:])

    /// Покупка → приписанные к ней курсовые разницы.
    let differencesByPurchase: [PersistentIdentifier: [Transaction]]

    /// Курсовые разницы, для которых нашлась покупка: отдельной строкой их не показываем.
    var foldedIDs: Set<PersistentIdentifier> {
        Set(differencesByPurchase.values.flatMap { $0.map(\.persistentModelID) })
    }

    func differences(for purchase: Transaction) -> [Transaction] {
        differencesByPurchase[purchase.persistentModelID] ?? []
    }

    /// Итоговое списание по покупке в валюте счёта: курсовая разница «в плюс» его уменьшает,
    /// «в минус» (доплата) — увеличивает.
    func finalAmount(for purchase: Transaction) -> Double {
        differences(for: purchase).reduce(purchase.amount) { $0 + ExchangeRateDifferenceMatcher.signedCharge(of: $1) }
    }

    /// То же в рублях — для сумм за день.
    func finalRubAmount(for purchase: Transaction) -> Double? {
        guard let rub = purchase.rubAmount else { return nil }
        return differences(for: purchase).reduce(rub) { total, difference in
            let sign = ExchangeRateDifferenceMatcher.signedCharge(of: difference) < 0 ? -1.0 : 1.0
            return total + sign * abs(difference.rubAmount ?? 0)
        }
    }
}

/// Находит, к какой покупке относится курсовая разница.
///
/// Однозначной связи в выписке нет: у мерчанта часто несколько покупок за те же дни.
/// Кандидат — валютная покупка того же мерчанта за 0–30 дней до разницы, и разница
/// не больше 3% от суммы. У каждой покупки не больше одной разницы; из нескольких
/// кандидатов выбираем ту, что была примерно за 3 дня (обычный срок проведения).
/// Ошибка выбора влияет только на то, у какой из одинаковых покупок показана разница:
/// итоги по категориям и мерчантам считаются по самим операциям и остаются точными.
enum ExchangeRateDifferenceMatcher {
    struct Item {
        let day: Int
        let merchant: String
        /// Сумма в валюте счёта без знака.
        let amount: Double
        let isDifference: Bool
        /// Покупка в иностранной валюте — только к таким бывает курсовая разница.
        let isForeignPurchase: Bool
    }

    private static let maxDaysAfterPurchase = 30
    private static let maxShareOfPurchase = 0.03
    private static let typicalDaysAfterPurchase = 3

    static func fold(_ transactions: [Transaction]) -> FoldedExchangeRateDifferences {
        let relevant = transactions.filter { $0.isExchangeRateDifference || isForeignPurchase($0) }
        guard relevant.contains(where: \.isExchangeRateDifference) else { return .empty }

        let items = relevant.map { transaction in
            Item(
                day: StatementDeduplicator.dayNumber(of: TransactionSnapshot(
                    date: transaction.date,
                    details: transaction.details,
                    amount: transaction.amount,
                    currencyCode: transaction.currencyCode,
                    foreignAmount: transaction.foreignAmount,
                    foreignCurrencyCode: transaction.foreignCurrencyCode,
                    direction: 0,
                    wasImported: transaction.fingerprint != nil
                )),
                merchant: StatementDeduplicator.normalizedDetails(transaction.details),
                amount: transaction.amount,
                isDifference: transaction.isExchangeRateDifference,
                isForeignPurchase: isForeignPurchase(transaction)
            )
        }

        var result: [PersistentIdentifier: [Transaction]] = [:]
        for (difference, purchase) in pair(items) {
            result[relevant[purchase].persistentModelID, default: []].append(relevant[difference])
        }
        return FoldedExchangeRateDifferences(differencesByPurchase: result)
    }

    /// Индекс курсовой разницы → индекс покупки.
    static func pair(_ items: [Item]) -> [Int: Int] {
        let purchasesByMerchant = Dictionary(
            grouping: items.indices.filter { items[$0].isForeignPurchase },
            by: { items[$0].merchant }
        )

        var options: [(cost: Int, difference: Int, purchase: Int)] = []
        for (index, difference) in items.enumerated() where difference.isDifference {
            for candidate in purchasesByMerchant[difference.merchant] ?? [] {
                let purchase = items[candidate]
                let gap = difference.day - purchase.day
                guard gap >= 0, gap <= maxDaysAfterPurchase,
                      difference.amount <= purchase.amount * maxShareOfPurchase else { continue }
                options.append((abs(gap - typicalDaysAfterPurchase), index, candidate))
            }
        }

        // Сначала самые правдоподобные пары; при равенстве — по порядку, чтобы результат был стабильным.
        options.sort { ($0.cost, $0.difference, $0.purchase) < ($1.cost, $1.difference, $1.purchase) }

        var result: [Int: Int] = [:]
        var usedPurchases = Set<Int>()
        for option in options where result[option.difference] == nil && !usedPurchases.contains(option.purchase) {
            result[option.difference] = option.purchase
            usedPurchases.insert(option.purchase)
        }
        return result
    }

    /// Вклад курсовой разницы в списание: «в плюс» (зачисление) — отрицательный.
    static func signedCharge(of difference: Transaction) -> Double {
        difference.kind == .income ? -difference.amount : difference.amount
    }

    private static func isForeignPurchase(_ transaction: Transaction) -> Bool {
        transaction.kind == .expense && !transaction.isExchangeRateDifference && transaction.foreignAmount != nil
    }
}
