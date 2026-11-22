import Foundation

/// Суммы расходов по категориям и их подкатегориям для аналитики.
///
/// Операция без подкатегории в категории, где они есть, попадает в подкатегорию
/// по умолчанию («Другое») — так же её предлагает выбор категории. Курсовая разница
/// сюда отдельно не попадает: она уже входит в сумму своей покупки.
/// Категории и подкатегории с нулевой суммой не показываются.
struct CategoryTotalsAccumulator {
    static let uncategorized = "Без категории"

    /// Сумма, которая после округления до копеек остаётся расходом.
    static func isPositive(_ total: Double) -> Bool {
        total >= 0.005
    }

    private var totals: [String: Double] = [:]
    private var counts: [String: Int] = [:]
    private var subcategoryTotals: [String: [String: Double]] = [:]
    private var subcategoryCounts: [String: [String: Int]] = [:]

    static func categoryName(of transaction: Transaction) -> String {
        transaction.categoryName ?? uncategorized
    }

    /// Подкатегория операции в аналитике, nil — у категории нет подкатегорий.
    static func subcategoryName(of transaction: Transaction) -> String? {
        transaction.subcategoryName ?? DefaultSubcategoryDefinitions.defaultSubcategory(for: transaction.categoryName)
    }

    /// - Parameter isPurchase: false — возврат: уменьшает сумму, но не число покупок.
    mutating func addExpense(_ transaction: Transaction, rub: Double, isPurchase: Bool = true) {
        add(
            category: Self.categoryName(of: transaction),
            subcategory: Self.subcategoryName(of: transaction),
            rub: rub,
            isPurchase: isPurchase
        )
    }

    /// То же по готовым названиям — из `AnalyticsIndex`, без чтения полей модели.
    mutating func add(category: String, subcategory: String?, rub: Double, isPurchase: Bool) {
        add(category: category, subcategory: subcategory, rub: rub, count: isPurchase ? 1 : 0)
    }

    /// Уже сложенные суммы и число покупок пары «категория + подкатегория».
    mutating func add(category: String, subcategory: String?, rub: Double, count: Int) {
        totals[category, default: 0] += rub
        counts[category, default: 0] += count

        guard let subcategory else { return }
        subcategoryTotals[category, default: [:]][subcategory, default: 0] += rub
        subcategoryCounts[category, default: [:]][subcategory, default: 0] += count
    }

    func result() -> [AnalyticsCategoryTotal] {
        totals
            .filter { Self.isPositive($0.value) }
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
        let totals = totals.filter { Self.isPositive($0.value) }
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
