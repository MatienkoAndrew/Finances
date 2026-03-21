//
//  CategorySeeder.swift
//  Finances
//
//  Created by Андрей Матиенко on 20.03.2026.
//


import Foundation
import SwiftData

enum CategorySeeder {
    static func seedIfNeeded(existing: [ExpenseCategoryItem], modelContext: ModelContext) {
        guard existing.isEmpty else { return }

        for name in DefaultCategories.names {
            let item = ExpenseCategoryItem(name: name, isSystem: true)
            modelContext.insert(item)
        }
    }
}