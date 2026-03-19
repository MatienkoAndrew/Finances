//
//  CategoryRuleEngine.swift
//  Finances
//
//  Created by Андрей Матиенко on 20.03.2026.
//


import Foundation

enum CategoryRuleEngine {
    static func matchCategory(
        operationType: String,
        details: String,
        rules: [CategoryRule]
    ) -> ExpenseCategory? {
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
                return rule.category
            }
        }

        return ExpenseCategoryGuesser.guessCategory(
            for: operationType,
            details: details
        )
    }
}