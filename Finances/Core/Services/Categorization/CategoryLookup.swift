//
//  CategoryLookup.swift
//  Finances
//
//  Created by Андрей Матиенко on 21.03.2026.
//


import Foundation

enum CategoryLookup {
    static func findCategory(
        named name: String?,
        in categories: [ExpenseCategoryItem]
    ) -> ExpenseCategoryItem? {
        guard let name else { return nil }

        return categories.first {
            CategoryNameNormalizer.normalize($0.name) == CategoryNameNormalizer.normalize(name)
        }
    }
}