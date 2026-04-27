import Foundation

enum ExpenseCategoryGuesser {
    static func guessCategoryName(for operationType: String, details: String) -> String? {
        let text = details.uppercased()

        if operationType == "Снятие" {
            return "Снятие наличных"
        }

        if operationType == "Перевод" {
            return "Перевод"
        }

        if operationType == "Пополнение" {
            return nil
        }

        // Используем встроенные правила
        let activeRules = BuiltInCategoryRulesManager.getActiveRules()
        for rule in activeRules {
            if text.contains(rule.pattern) {
                return rule.categoryName
            }
        }

        return nil
    }
}
