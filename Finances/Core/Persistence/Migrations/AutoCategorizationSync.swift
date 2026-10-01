import Foundation
import SwiftData

/// Переопределяет категорию у операций, оставшихся в «Другом» или без категории:
/// по правилам, по тому, что пользователь сам выбирал для мерчанта, и по встроенному
/// словарю. Заодно проставляет подкатегорию, если категория уже совпадает.
/// Категории, выбранные вручную, не трогает. Безопасно запускать при каждом старте.
enum AutoCategorizationSync {
    private static let fallbackCategory = "другое"

    @discardableResult
    static func run(context: ModelContext) -> Int {
        guard let transactions = try? context.fetch(FetchDescriptor<Transaction>()),
              let rules = try? context.fetch(FetchDescriptor<CategoryRule>()),
              let categories = try? context.fetch(FetchDescriptor<ExpenseCategoryItem>()) else { return 0 }

        let memory = MerchantCategoryMemory(transactions: transactions)
        var updated = 0

        for transaction in transactions where transaction.kind == .expense && transaction.isCategoryManuallySet != true {
            guard let match = CategoryRuleEngine.match(
                operationType: transaction.ruleOperationType,
                details: transaction.details,
                rules: rules,
                existingCategories: categories,
                memory: memory
            ) else { continue }

            let current = transaction.categoryName.map(CategoryNameNormalizer.normalize)
            let isFallback = current == nil || current == fallbackCategory

            if isFallback, CategoryNameNormalizer.normalize(match.category) != fallbackCategory {
                transaction.categoryName = match.category
                transaction.subcategoryName = match.subcategory
                updated += 1
            } else if current == CategoryNameNormalizer.normalize(match.category),
                      transaction.subcategoryName == nil,
                      let subcategory = match.subcategory {
                transaction.subcategoryName = subcategory
                updated += 1
            }
        }

        if updated > 0 {
            try? context.save()
        }
        return updated
    }
}
