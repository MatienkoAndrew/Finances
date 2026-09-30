import Foundation
import SwiftData

/// Проставляет категорию курсовым разницам «в плюс», у которых её нет.
///
/// В аналитике такая строка уменьшает расходы своей категории (см.
/// `Transaction.reducesExpensesInAnalytics`), но первая версия нового импорта при
/// исправлении знака очищала категорию. Берём самую частую категорию покупок
/// того же мерчанта. Безопасно запускать при каждом старте: трогает только пустые.
enum ExchangeRateDifferenceCategorySync {
    static func run(context: ModelContext) {
        guard let transactions = try? context.fetch(FetchDescriptor<Transaction>()) else { return }

        let uncategorized = transactions.filter { $0.reducesExpensesInAnalytics && $0.categoryName == nil }
        guard !uncategorized.isEmpty else { return }

        var categoryCounts: [String: [String: Int]] = [:]
        for transaction in transactions where transaction.kind == .expense {
            guard let category = transaction.categoryName else { continue }
            let merchant = StatementDeduplicator.normalizedDetails(transaction.details)
            categoryCounts[merchant, default: [:]][category, default: 0] += 1
        }

        var changed = false
        for transaction in uncategorized {
            let merchant = StatementDeduplicator.normalizedDetails(transaction.details)
            guard let category = categoryCounts[merchant]?.max(by: { $0.value < $1.value })?.key else { continue }
            transaction.categoryName = category
            changed = true
        }

        if changed {
            try? context.save()
        }
    }
}
