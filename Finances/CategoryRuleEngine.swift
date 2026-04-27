import Foundation

enum CategoryRuleEngine {
    static func matchCategoryName(
        operationType: String,
        details: String,
        rules: [CategoryRule],
        existingCategories: [ExpenseCategoryItem]
    ) -> String? {
        let normalizedDetails = details.uppercased()

        let sortedRules = rules
            .filter { $0.isEnabled }
            .sorted { lhs, rhs in
                if lhs.priority != rhs.priority {
                    return lhs.priority > rhs.priority
                }
                return lhs.createdAt < rhs.createdAt
            }

        for rule in sortedRules {
            let pattern = rule.pattern
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()

            guard !pattern.isEmpty else { continue }

            if normalizedDetails.contains(pattern) {
                return rule.categoryName
            }
        }

        // Пытаемся угадать категорию
        let guessedName = ExpenseCategoryGuesser.guessCategoryName(
            for: operationType,
            details: details
        )
        
        // Возвращаем угаданную категорию если она существует
        if let guessedName, existingCategories.contains(where: { $0.name == guessedName }) {
            return guessedName
        }
        
        // Fallback на "Другое" если категория не найдена
        if existingCategories.contains(where: { $0.name == "Другое" }) {
            return "Другое"
        }
        
        return nil
    }
}
