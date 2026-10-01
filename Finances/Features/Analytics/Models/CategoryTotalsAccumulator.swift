import Foundation

/// Суммы расходов по категориям и их подкатегориям для аналитики.
///
/// Операция без подкатегории в категории, где они есть, попадает в подкатегорию
/// по умолчанию («Другое») — так же её предлагает выбор категории. Курсовая разница
/// «в плюс» уменьшает ту подкатегорию, в которой у мерчанта больше всего покупок
/// за период: своей подкатегории у неё обычно нет.
struct CategoryTotalsAccumulator {
    static let uncategorized = "Без категории"

    private var totals: [String: Double] = [:]
    private var counts: [String: Int] = [:]
    private var subcategoryTotals: [String: [String: Double]] = [:]
    private var subcategoryCounts: [String: [String: Int]] = [:]
    /// Категория → мерчант → подкатегория → число покупок.
    private var merchantSubcategories: [String: [String: [String: Int]]] = [:]
    private var pendingRefunds: [(category: String, merchant: String, rub: Double)] = []

    static func categoryName(of transaction: Transaction) -> String {
        transaction.categoryName ?? uncategorized
    }

    /// Подкатегория операции в аналитике, nil — у категории нет подкатегорий.
    static func subcategoryName(of transaction: Transaction) -> String? {
        transaction.subcategoryName ?? DefaultSubcategoryDefinitions.defaultSubcategory(for: transaction.categoryName)
    }

    mutating func addExpense(_ transaction: Transaction, rub: Double) {
        let category = Self.categoryName(of: transaction)
        totals[category, default: 0] += rub
        counts[category, default: 0] += 1

        guard let subcategory = Self.subcategoryName(of: transaction) else { return }
        subcategoryTotals[category, default: [:]][subcategory, default: 0] += rub
        subcategoryCounts[category, default: [:]][subcategory, default: 0] += 1

        let merchant = StatementDeduplicator.normalizedDetails(transaction.details)
        merchantSubcategories[category, default: [:]][merchant, default: [:]][subcategory, default: 0] += 1
    }

    /// Возврат части покупки (курсовая разница «в плюс»): уменьшает расходы, в счётчик не идёт.
    mutating func addRefund(_ transaction: Transaction, rub: Double) {
        let category = Self.categoryName(of: transaction)
        totals[category, default: 0] -= rub

        if let subcategory = transaction.subcategoryName {
            subcategoryTotals[category, default: [:]][subcategory, default: 0] -= rub
        } else if Self.subcategoryName(of: transaction) != nil {
            let merchant = StatementDeduplicator.normalizedDetails(transaction.details)
            pendingRefunds.append((category, merchant, rub))
        }
    }

    func result() -> [AnalyticsCategoryTotal] {
        var subcategoryTotals = subcategoryTotals

        for refund in pendingRefunds {
            let subcategory = merchantSubcategories[refund.category]?[refund.merchant]?
                .max { ($0.value, $1.key) < ($1.value, $0.key) }?.key
                ?? DefaultSubcategoryDefinitions.defaultSubcategory(for: refund.category)
                ?? DefaultSubcategoryDefinitions.defaultName
            subcategoryTotals[refund.category, default: [:]][subcategory, default: 0] -= refund.rub
        }

        return totals
            .map { category, total in
                AnalyticsCategoryTotal(
                    category: category,
                    total: total,
                    count: counts[category] ?? 0,
                    subcategories: subcategories(of: category, totals: subcategoryTotals[category] ?? [:])
                )
            }
            .sorted { $0.total > $1.total }
    }

    private func subcategories(of category: String, totals: [String: Double]) -> [AnalyticsSubcategoryTotal] {
        // Всё в «Другом» — подкатегории никто не выбирал, разбивка ничего не скажет.
        guard totals.keys.contains(where: { $0 != DefaultSubcategoryDefinitions.defaultName }) else { return [] }

        let emojis = Dictionary(
            (DefaultSubcategoryDefinitions.subcategories(for: category) ?? []).map { ($0.name, $0.emoji) },
            uniquingKeysWith: { first, _ in first }
        )

        return totals
            .map { name, total in
                AnalyticsSubcategoryTotal(
                    name: name,
                    emoji: emojis[name],
                    total: total,
                    count: subcategoryCounts[category]?[name] ?? 0
                )
            }
            .sorted { ($0.total, $1.name) > ($1.total, $0.name) }
    }
}
