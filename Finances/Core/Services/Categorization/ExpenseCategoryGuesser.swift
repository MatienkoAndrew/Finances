import Foundation

enum ExpenseCategoryGuesser {
    static func guessCategoryName(for operationType: String, details: String) -> String? {
        guesses(for: operationType, details: details).first?.category
    }

    /// Подходящие категории по убыванию уверенности. Первая может не существовать
    /// у пользователя («Красота») — тогда берётся следующая.
    static func guesses(for operationType: String, details: String) -> [CategoryMatch] {
        if operationType == "Снятие" {
            return [CategoryMatch(category: "Снятие наличных", subcategory: nil)]
        }

        if operationType == "Перевод" {
            return [CategoryMatch(category: "Перевод", subcategory: nil)]
        }

        if operationType == "Пополнение" {
            return []
        }

        // Используем встроенные правила
        let text = MerchantText(details)
        return BuiltInCategoryRulesManager.getActiveRules()
            .filter { $0.matches(text) }
            .map { CategoryMatch(category: $0.categoryName, subcategory: $0.subcategoryName) }
    }
}
