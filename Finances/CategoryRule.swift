//
//  CategoryRule.swift
//  Finances
//
//  Created by Андрей Матиенко on 20.03.2026.
//


import Foundation
import SwiftData

@Model
final class CategoryRule {
    var pattern: String
    var categoryRaw: String
    var priority: Int
    var isEnabled: Bool
    var createdAt: Date

    var category: ExpenseCategory {
        get { ExpenseCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    init(
        pattern: String,
        category: ExpenseCategory,
        priority: Int = 0,
        isEnabled: Bool = true,
        createdAt: Date = Date()
    ) {
        self.pattern = pattern
        self.categoryRaw = category.rawValue
        self.priority = priority
        self.isEnabled = isEnabled
        self.createdAt = createdAt
    }
}