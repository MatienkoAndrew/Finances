import Foundation
import SwiftData

/// Курсовые разницы, приписанные к своим покупкам, — для списков и аналитики.
///
/// В базе курсовая разница остаётся отдельной операцией, как в выписке: так работают
/// повторный импорт, отмена импорта и сверка баланса. В списке она не показывается,
/// а в итогах дня и в аналитике считается вместе со своей покупкой.
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

    /// Курсовые разницы покупки в рублях для аналитики: доплата — плюс, возврат — минус.
    ///
    /// В аналитике разница считается внутри своей покупки — в её дне, категории и
    /// подкатегории, — а не отдельной операцией: иначе возврат, пришедший в следующем
    /// месяце, давал там категорию с минусом и «0 шт.».
    func rubAdjustment(
        for purchase: Transaction,
        settings: AppSettings?,
        trackedRates: [TrackedExchangeRate]
    ) -> Double {
        differences(for: purchase).reduce(0) { total, difference in
            let rub = TransactionRubConverter.displayRubAmount(
                for: difference,
                settings: settings,
                trackedRates: trackedRates
            ) ?? 0
            let sign = ExchangeRateDifferenceMatcher.signedCharge(of: difference) < 0 ? -1.0 : 1.0
            return total + sign * rub
        }
    }
}

/// Находит, к какой покупке относится курсовая разница.
///
/// Однозначной связи в выписке нет: у мерчанта часто несколько покупок за те же дни.
/// Кандидат — валютная покупка или снятие наличных того же мерчанта за 0–30 дней
/// до разницы, и разница не больше 3% от суммы. У каждой покупки не больше одной
/// разницы; из нескольких кандидатов выбираем ту, что была примерно за 3 дня
/// (обычный срок проведения).
///
/// Название мерчанта у разницы Kaspi пишет не всегда так же, как у покупки: обрезает
/// на другой длине («WEI TAI LANG YU HSIEN T» и «WEI TAI LANG YU HSIEN»), по-другому
/// пишет японские названия латиницей («TABIBENTOUKIYOUTOICHIGOU» и «TABIBENTOKYOTOICHIGO»),
/// у снятия добавляет «Банкомат». Поэтому названия сравниваются по `merchantKey`,
/// и одно может быть началом другого; точное совпадение всегда важнее.
enum ExchangeRateDifferenceMatcher {
    struct Item {
        let day: Int
        let merchant: String
        /// Сумма в валюте счёта без знака.
        let amount: Double
        let isDifference: Bool
        /// Покупка или снятие в иностранной валюте — только к таким бывает курсовая разница.
        let isForeignPurchase: Bool
    }

    private static let maxDaysAfterPurchase = 30
    private static let maxShareOfPurchase = 0.03
    private static let typicalDaysAfterPurchase = 3
    /// Короче — слишком легко совпасть с чужим мерчантом по началу названия.
    private static let minPrefixLength = 5
    /// Больше любой разницы в днях: пара по точному названию всегда выигрывает.
    private static let prefixMatchPenalty = 100

    /// Название мерчанта для поиска пары: без «Банкомат», только буквы и цифры,
    /// японская латиница приведена к одному написанию («OU» → «O», «KIYO» → «KYO»).
    static func merchantKey(_ details: String) -> String {
        var text = details.trimmingCharacters(in: .whitespaces)
        if let range = text.range(of: "Банкомат", options: [.caseInsensitive, .anchored]) {
            text.removeSubrange(range)
        }
        return StatementDeduplicator.normalizedDetails(text)
            .replacingOccurrences(of: "OU", with: "O")
            .replacingOccurrences(of: "UU", with: "U")
            .replacingOccurrences(of: "IYO", with: "YO")
            .replacingOccurrences(of: "IYA", with: "YA")
            .replacingOccurrences(of: "IYU", with: "YU")
    }

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
                merchant: merchantKey(transaction.details),
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
        let purchaseIndices = items.indices.filter { items[$0].isForeignPurchase }
        let purchasesByMerchant = Dictionary(grouping: purchaseIndices, by: { items[$0].merchant })

        // Начало названия → покупки, чьё название с него начинается (и само название целиком).
        var purchasesByPrefix: [Substring: [Int]] = [:]
        for (merchant, indices) in purchasesByMerchant where merchant.count >= minPrefixLength {
            for length in minPrefixLength..<merchant.count {
                purchasesByPrefix[merchant.prefix(length), default: []].append(contentsOf: indices)
            }
        }

        var options: [(cost: Int, difference: Int, purchase: Int)] = []
        for (index, difference) in items.enumerated() where difference.isDifference {
            let merchant = difference.merchant
            var candidates = (purchasesByMerchant[merchant] ?? []).map { ($0, 0) }
            if merchant.count >= minPrefixLength {
                // У покупки название длиннее: «WEI TAI LANG YU HSIEN T» ← «WEI TAI LANG YU HSIEN TAIPEI».
                candidates += (purchasesByPrefix[Substring(merchant)] ?? []).map { ($0, prefixMatchPenalty) }
                // У покупки название короче: «WEI TAI LANG YU HSIEN T» ← «WEI TAI LANG YU HSIEN».
                for length in minPrefixLength..<merchant.count {
                    candidates += (purchasesByMerchant[String(merchant.prefix(length))] ?? []).map { ($0, prefixMatchPenalty) }
                }
            }

            for (candidate, penalty) in candidates {
                let purchase = items[candidate]
                let gap = difference.day - purchase.day
                guard gap >= 0, gap <= maxDaysAfterPurchase,
                      difference.amount <= purchase.amount * maxShareOfPurchase else { continue }
                options.append((penalty + abs(gap - typicalDaysAfterPurchase), index, candidate))
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

    /// Валютная покупка или снятие наличных в валюте (оно импортируется переводом).
    private static func isForeignPurchase(_ transaction: Transaction) -> Bool {
        (transaction.kind == .expense || transaction.kind == .transfer)
            && !transaction.isExchangeRateDifference
            && transaction.foreignAmount != nil
    }
}
