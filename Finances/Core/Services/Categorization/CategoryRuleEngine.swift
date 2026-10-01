import Foundation

enum CategoryRuleEngine {
    static func matchCategoryName(
        operationType: String,
        details: String,
        rules: [CategoryRule],
        existingCategories: [ExpenseCategoryItem]
    ) -> String? {
        match(
            operationType: operationType,
            details: details,
            rules: rules,
            existingCategories: existingCategories
        )?.category
    }

    /// Категория и подкатегория для операции. Порядок: правила пользователя →
    /// что пользователь сам выбирал для этого мерчанта → встроенный словарь → «Другое».
    static func match(
        operationType: String,
        details: String,
        rules: [CategoryRule],
        existingCategories: [ExpenseCategoryItem],
        memory: MerchantCategoryMemory = .empty
    ) -> CategoryMatch? {
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
                return resolved(rule.categoryName, rule.subcategoryName, in: existingCategories)
                    ?? CategoryMatch(category: rule.categoryName, subcategory: nil)
            }
        }

        if let remembered = memory.match(for: details),
           let match = resolved(remembered.category, remembered.subcategory, in: existingCategories) {
            return match
        }

        // Пытаемся угадать категорию
        let guesses = ExpenseCategoryGuesser.guesses(for: operationType, details: details)
        for guess in guesses {
            if let match = resolved(guess.category, guess.subcategory, in: existingCategories) {
                return match
            }
        }

        // Fallback на "Другое" если категория не найдена
        return resolved("Другое", nil, in: existingCategories)
    }

    /// Категория, как она называется у пользователя, и подкатегория, если она у неё есть.
    /// nil — такой категории у пользователя нет.
    private static func resolved(
        _ category: String,
        _ subcategory: String?,
        in categories: [ExpenseCategoryItem]
    ) -> CategoryMatch? {
        guard let item = CategoryLookup.findCategory(named: category, in: categories) else { return nil }
        let known = DefaultSubcategoryDefinitions.subcategories(for: item.name)?.map(\.name) ?? []
        return CategoryMatch(
            category: item.name,
            subcategory: subcategory.flatMap { known.contains($0) ? $0 : nil }
        )
    }
}
