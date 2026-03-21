import Foundation

enum CategoryRuleEngine {
    static func matchCategoryName(
        operationType: String,
        details: String,
        rules: [CategoryRule]
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

        return ExpenseCategoryGuesser.guessCategoryName(
            for: operationType,
            details: details
        )
    }
}
